-- Read-only snapshot of current security policy definitions.
-- Save as a restricted file. Reveals the app's access-control structure.
select schemaname, tablename, policyname, permissive, roles,
       cmd, qual as using_expression, with_check
from pg_policies
where schemaname='public'
  and tablename=any(array[
    'profiles','projects','project_members','targets','criteria',
    'assessments','assessment_scores','project_teacher_criteria'
  ])
order by tablename, policyname;
