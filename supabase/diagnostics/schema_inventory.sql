-- Read-only inventory of the current application's public database schema.
-- Run in Supabase SQL Editor. Save the results (CSV) to the school's restricted Drive.
-- This is DOCUMENTATION ONLY, not a restorable schema dump.
with app_tables as (
 select unnest(array[
 'profiles','projects','project_members','targets','criteria',
 'assessments','assessment_scores','project_teacher_criteria'
 ]) as tablename
)
select c.table_name, c.ordinal_position, c.column_name,
       c.data_type, c.udt_name, c.is_nullable, c.column_default,
       coalesce(pk.is_primary_key,false) as is_primary_key
from information_schema.columns c
join app_tables t on t.tablename=c.table_name
left join (
 select tc.table_schema, tc.table_name, kcu.column_name, true as is_primary_key
 from information_schema.table_constraints tc
 join information_schema.key_column_usage kcu
 on tc.constraint_name=kcu.constraint_name and tc.table_schema=kcu.table_schema
 and tc.table_name=kcu.table_name
 where tc.constraint_type='PRIMARY KEY' and tc.table_schema='public'
) pk on pk.table_schema=c.table_schema and pk.table_name=c.table_name
 and pk.column_name=c.column_name
where c.table_schema='public'
order by array_position(array[
 'profiles','projects','project_members','targets','criteria',
 'assessments','assessment_scores','project_teacher_criteria'
], c.table_name), c.ordinal_position;
