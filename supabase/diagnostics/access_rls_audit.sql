-- 読み取り専用：RLSとポリシーの設定状況を一覧にします。
-- このSQLはデータを変更しません。SQL Editorで実行して構いません。
with protected_tables as (
  select unnest(array[
    'profiles','projects','project_members','targets','criteria',
    'assessments','assessment_scores','project_teacher_criteria'
  ]) as table_name
), table_status as (
  select c.relname as table_name, c.relrowsecurity as rls_on,
         c.relforcerowsecurity as force_rls
  from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relkind in ('r','p')
), policy_status as (
  select tablename as table_name, count(*) as policy_count,
         string_agg(policyname || ' (' || cmd || ')', ', ' order by policyname) as policies
  from pg_policies
  where schemaname = 'public'
  group by tablename
)
select t.table_name,
       case when s.table_name is null then 'テーブルなし'
            when s.rls_on then '有効'
            else '無効（要確認）' end as rls,
       coalesce(p.policy_count, 0) as policy_count,
       coalesce(p.policies, 'なし') as policy_names
from protected_tables t
left join table_status s on s.table_name = t.table_name
left join policy_status p on p.table_name = t.table_name
order by array_position(array[
  'profiles','projects','project_members','targets','criteria',
  'assessments','assessment_scores','project_teacher_criteria'
], t.table_name);
