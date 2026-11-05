# 教員アカウント管理：Supabase公開手順

教員管理の画面とEdge FunctionのソースはGitHubにあります。**GitHub Pagesへの変更だけではEdge Functionは稼働しません。** 管理者がSupabaseへ関数をデプロイしてください。

## 公開する関数

- 関数名：`manage-staff`
- ソース：`supabase/functions/manage-staff/index.ts`
- 推奨の公開方法：Supabase Dashboard → Edge Functions → Deploy a new function → Via Editor
- エディターに `index.ts` 全文を貼り付け、`manage-staff` の名前でデプロイします。
- **Verify JWT を OFF** に設定してください。ブラウザから公開可能な新APIキーでアクセスできるようにし、関数自身がAuthorizationヘッダーを使って毎回 `auth.getUser()` でトークンを検証し、`profiles.role` と `is_active` で管理者だけを許可します。設定ファイルでは `verify_jwt = false` を指定してあります。
- Edge Functions の環境変数 `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` が利用可能か確認します。Supabaseでは通常自動設定されます。設定値をGitHubやフロントエンドにコピーしないでください。
- 関数が公開されれば、サイト上の「教員管理」画面から教員の新規登録・一覧確認・利用停止・再開が使えます。

## 確認事項

1. **管理者でログイン** → 左メニュー「教員管理」→「↻ 更新」で一覧が出る。
2. **テスト用の職員番号**で初期パスワード5文字以上を指定し登録する。
3. その番号で**別ブラウザ**からログインし、評価を保存する。
4. 管理者に戻り、その教員の利用を停止 → 停止された教員が再ログインできなくなるか確認する。
5. 停止した教員で管理関数を叩いても権限がないことを確認する。

## 注意

- 初期パスワードの共有は、校内の安全な方法で行ってください。CSVにパスワードを出力しません。
- 教員が自分のパスワードを変更できる機能や、停止したユーザーの既存セッションの即時失効はこの版には含まれません。停止後も、既存セッションのJWT有効期間内のAuth状態は残り得るため、すべてのテーブルのRLSが `is_active_user()` などで必ず停止を判定しているか本番導入前に確認してください。
- 同一対象に対する複数端末での同時上書きの競合を防ぐには、`assessments(project_id,target_id,teacher_id)` の一意制約とサーバー側のトランザクション化が別途必要です。
- 本番の生徒氏名・評価記録を登録する前に、RLSの全テーブルと複数教員テストを完了してください。
