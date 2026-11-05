-- Run ONCE in the rubric-evaluation Supabase project's SQL Editor.
-- No setting: every criterion is assigned (backwards compatible).
-- At least one row for a teacher/project: only those criteria are assigned.
create table if not exists public.project_teacher_criteria (
 project_id uuid not null references public.projects(id) on delete cascade,
 teacher_id uuid not null references public.profiles(id) on delete cascade,
 criterion_id uuid not null references public.criteria(id) on delete cascade,
 primary key (project_id, teacher_id, criterion_id)
);
create index if not exists project_teacher_criteria_teacher_idx
 on public.project_teacher_criteria(teacher_id, project_id);
alter table public.project_teacher_criteria enable row level security;
revoke all on public.project_teacher_criteria from anon;
grant select, insert, delete on public.project_teacher_criteria to authenticated;

drop policy if exists "assigned criteria read" on public.project_teacher_criteria;
create policy "assigned criteria read" on public.project_teacher_criteria
 for select to authenticated using (
  exists (select 1 from public.profiles p where p.id=auth.uid() and p.is_active=true)
 );
drop policy if exists "assigned criteria admin insert" on public.project_teacher_criteria;
create policy "assigned criteria admin insert" on public.project_teacher_criteria
 for insert to authenticated with check (
  exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.is_active=true)
  and exists(select 1 from public.criteria c where c.id=criterion_id and c.project_id=project_id)
 );
drop policy if exists "assigned criteria admin delete" on public.project_teacher_criteria;
create policy "assigned criteria admin delete" on public.project_teacher_criteria
 for delete to authenticated using (
  exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.is_active=true)
 );

-- Store one teacher's assignment as one transaction.
-- Empty array means "all criteria", no partial rows.
create or replace function public.set_project_teacher_criteria(
 p_project_id uuid, p_teacher_id uuid, p_criterion_ids uuid[]
) returns void language plpgsql security invoker set search_path=public as $$
declare item_count int; all_count int;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role='admin' and is_active=true) then
  raise exception '管理者のみ操作できます';
 end if;
 if not exists(select 1 from public.projects where id=p_project_id) then
  raise exception 'プロジェクトが見つかりません';
 end if;
 if not exists(select 1 from public.profiles where id=p_teacher_id and is_active=true) then
  raise exception '有効な教員を選択してください';
 end if;
 if array_position(p_criterion_ids,null) is not null then raise exception '無効な評価項目'; end if;
 select count(distinct c.id) into item_count from public.criteria c
  where c.project_id=p_project_id and c.id=any(p_criterion_ids);
 select count(*) into all_count from public.criteria where project_id=p_project_id;
 if coalesce(array_length(p_criterion_ids,1),0)=0 then raise exception '担当項目を少なくとも1つ選んでください'; end if;
 if item_count<>coalesce(array_length(p_criterion_ids,1),0) then raise exception '評価項目が不正または重複しています'; end if;
 delete from public.project_teacher_criteria where project_id=p_project_id and teacher_id=p_teacher_id;
 if item_count<all_count then
  insert into public.project_teacher_criteria(project_id,teacher_id,criterion_id)
   select p_project_id,p_teacher_id,unnest(p_criterion_ids);
 end if;
end $$;
revoke all on function public.set_project_teacher_criteria(uuid,uuid,uuid[]) from public;
grant execute on function public.set_project_teacher_criteria(uuid,uuid,uuid[]) to authenticated;

-- Assignment limits are also enforced on future score writes.
-- Prior ratings are preserved, but the frontend excludes unassigned past scores from aggregates.
create or replace function public.check_score_criterion_assignment()
returns trigger language plpgsql security definer set search_path=public as $$
declare owner_id uuid; parent_project uuid; criterion_project uuid;
begin
 select a.teacher_id,a.project_id into owner_id,parent_project
 from public.assessments a where a.id=new.assessment_id;
 select c.project_id into criterion_project from public.criteria c where c.id=new.criterion_id;
 if owner_id is null or criterion_project is distinct from parent_project then
  raise exception '異なるプロジェクトの項目を保存できません';
 end if;
 if exists(select 1 from public.project_teacher_criteria where project_id=parent_project and teacher_id=owner_id)
  and not exists(select 1 from public.project_teacher_criteria
    where project_id=parent_project and teacher_id=owner_id and criterion_id=new.criterion_id) then
  raise exception '担当外の評価項目は保存できません';
 end if;
 return new;
end $$;
drop trigger if exists check_score_assignment on public.assessment_scores;
create trigger check_score_assignment before insert or update of criterion_id,assessment_id,score
 on public.assessment_scores for each row execute function public.check_score_criterion_assignment();
