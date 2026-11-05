// Supabase Edge Function: manage-staff
// Deploy this file as the "manage-staff" function in the Supabase Dashboard.
// The browser NEVER receives the server-side secret key.
import { createClient } from 'npm:@supabase/supabase-js@2';

const origin = 'https://doinghistory.github.io';
const cors = {
  'Access-Control-Allow-Origin': origin,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Vary': 'Origin',
};
function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' } });
}
function getSecret(): string {
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') || '{}');
    return typeof keys.default === 'string' ? keys.default : '';
  } catch { return ''; }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
  if (req.method !== 'POST') return response({ error: 'POSTのみ利用できます。' }, 405);
  // Origin is defense-in-depth, not an authentication mechanism.
  const requestOrigin = req.headers.get('Origin');
  if (requestOrigin && requestOrigin !== origin) return response({ error: 'このサイトからのみ利用できます。' }, 403);

  const url = Deno.env.get('SUPABASE_URL');
  const serverKey = getSecret();
  const publicKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!url || !serverKey || !publicKey) return response({ error: 'サーバー設定が不足しています。' }, 503);

  const jwt = (req.headers.get('Authorization') || '').match(/^Bearer (.+)$/i)?.[1];
  if (!jwt) return response({ error: 'ログインが必要です。' }, 401);
  const userClient = createClient(url, publicKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await userClient.auth.getUser(jwt);
  if (userError || !userData?.user) return response({ error: '認証情報が無効です。' }, 401);

  const adminClient = createClient(url, serverKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: caller, error: callerError } = await adminClient.from('profiles').select('id,role,is_active').eq('id', userData.user.id).maybeSingle();
  if (callerError || !caller || caller.role !== 'admin' || caller.is_active !== true) return response({ error: '管理者のみ利用できます。' }, 403);

  let payload: Record<string, unknown>;
  try { payload = await req.json(); } catch { return response({ error: 'リクエストの形式が正しくありません。' }, 400); }
  const action = payload.action;

  if (action === 'list') {
    const { data, error } = await adminClient.from('profiles').select('id,employee_no,display_name,role,is_active').order('employee_no').limit(1000);
    if (error) return response({ error: '教員一覧を取得できませんでした。' }, 500);
    return response({ staff: data || [] });
  }

  if (action === 'create') {
    const employeeNo = String(payload.employee_no || '').trim();
    const displayName = String(payload.display_name || '').trim();
    const password = typeof payload.password === 'string' ? payload.password : '';
    const role = payload.role;
    if (!/^\d{6}$/.test(employeeNo) || !displayName || displayName.length > 80 || password.length < 12 || password.length > 128 || !['teacher', 'admin'].includes(String(role))) {
      return response({ error: '職員番号・名前・権限・パスワード（12文字以上）を確認してください。' }, 400);
    }
    const { data: existing, error: checkError } = await adminClient.from('profiles').select('id').eq('employee_no', employeeNo).limit(1);
    if (checkError) return response({ error: '職員番号の確認に失敗しました。' }, 500);
    if (existing?.length) return response({ error: 'この職員番号はすでに使用されています。' }, 409);

    const email = 'staff' + employeeNo + '@rubric-login.example.com';
    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { display_name: displayName },
    });
    if (createError || !created?.user) return response({ error: '認証アカウントの作成に失敗しました。職員番号の重複やパスワードを確認してください。' }, 409);
    const userId = created.user.id;
    const { error: profileError } = await adminClient.from('profiles').upsert({
      id: userId, employee_no: employeeNo, display_name: displayName, role, is_active: true,
    }, { onConflict: 'id' });
    if (profileError) {
      // Restore pre-creation state when profile setup fails.
      await adminClient.auth.admin.deleteUser(userId);
      return response({ error: '教員情報を保存できませんでした。作成した認証アカウントは取り消しました。' }, 500);
    }
    return response({ ok: true, id: userId }, 201);
  }

  if (action === 'set-active') {
    const id = String(payload.id || '');
    if (!/^[0-9a-f-]{36}$/i.test(id) || typeof payload.is_active !== 'boolean') return response({ error: '指定された教員情報が不正です。' }, 400);
    if (id === userData.user.id && payload.is_active === false) return response({ error: '自分自身を利用停止にはできません。' }, 400);
    const { data: target, error: targetError } = await adminClient.from('profiles').select('id,role,is_active').eq('id', id).maybeSingle();
    if (targetError || !target) return response({ error: '教員が見つかりません。' }, 404);
    if (target.role === 'admin' && target.is_active && payload.is_active === false) {
      const { count, error } = await adminClient.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'admin').eq('is_active', true);
      if (error || (count || 0) <= 1) return response({ error: '最後の管理者は利用停止にできません。' }, 400);
    }
    const { error } = await adminClient.from('profiles').update({ is_active: payload.is_active }).eq('id', id);
    if (error) return response({ error: '利用状態の更新に失敗しました。' }, 500);
    return response({ ok: true });
  }
  return response({ error: '操作が不明です。' }, 400);
});
