-- Multi-teacher project ownership & sharing.
-- Run in Supabase SQL Editor as database owner. Review against production backups.
begin;

create table if not exists public.project_members (
 project_id uuid not null references public.projects(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 role text not null default 'evaluator' check (role in ('editor','evaluator')),
 created_at timestamptz not null default now(),
 primary key(project_id,user_id)
);
create index if not exists project_members_user_idx on public.project_members(user_id,project_id);
alter table public.project_members enable row level security;
grant select, insert, update, delete on public.project_members to authenticated;
revoke all on public.project_members from anon;

-- Keep prior raters in historical projects so their work remains accessible.
insert into public.project_members(project_id,user_id,role)
select distinct a.project_id,a.teacher_id,'evaluator' from public.assessments a
join public.profiles p on p.id=a.teacher_id
join public.projects pr on pr.id=a.project_id
where a.teacher_id <> pr.created_by
on conflict (project_id,user_id) do nothing;

create or replace function public.is_active_teacher()
returns boolean language sql stable security definer set search_path = public as $$
 select exists(select 1 from public.profiles where id=auth.uid() and is_active=true)
$$;
create or replace function public.is_project_owner(p_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select public.is_active_teacher() and exists(
  select 1 from public.projects where id=p_id and created_by=auth.uid()
 )
$$;
create or replace function public.can_view_project(p_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select public.is_active_teacher() and (
  exists(select 1 from public.projects where id=p_id and created_by=auth.uid())
  or exists(select 1 from public.project_members where project_id=p_id and user_id=auth.uid())
 )
$$;
create or replace function public.can_manage_project(p_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select public.is_active_teacher() and (
  exists(select 1 from public.projects where id=p_id and created_by=auth.uid())
  or exists(select 1 from public.project_members where project_id=p_id and user_id=auth.uid() and role='editor')
 )
$$;
revoke all on function public.is_active_teacher() from public, anon;
revoke all on function public.is_project_owner(uuid) from public, anon;
revoke all on function public.can_view_project(uuid) from public, anon;
revoke all on function public.can_manage_project(uuid) from public, anon;
grant execute on function public.is_active_teacher() to authenticated;
grant execute on function public.is_project_owner(uuid) to authenticated;
grant execute on function public.can_view_project(uuid) to authenticated;
grant execute on function public.can_manage_project(uuid) to authenticated;

-- Replace permissive policies to prevent data leakage between projects.
-- Keep schema/table structures and existing rows intact.
do $$
declare row record;
begin
 for row in select schemaname,tablename,policyname from pg_policies
   where schemaname='public' and tablename in
   ('projects','project_members','targets','criteria','assessments','assessment_scores','project_teacher_criteria')
 loop
  execute format('drop policy if exists %I on %I.%I',row.policyname,row.schemaname,row.tablename);
 end loop;
end $$;

alter table public.projects enable row level security;
alter table public.targets enable row level security;
alter table public.criteria enable row level security;
alter table public.assessments enable row level security;
alter table public.assessment_scores enable row level security;
alter table public.project_teacher_criteria enable row level security;

create policy project_read on public.projects for select to authenticated
 using(public.can_view_project(id));
create policy project_insert on public.projects for insert to authenticated
 with check(public.is_active_teacher() and created_by=auth.uid());
create policy project_update on public.projects for update to authenticated
 using(public.can_manage_project(id)) with check(public.can_manage_project(id));
create policy project_delete on public.projects for delete to authenticated
 using(public.is_project_owner(id));

create policy member_read on public.project_members for select to authenticated
 using(public.can_view_project(project_id));
create policy member_insert on public.project_members for insert to authenticated
 with check(public.is_project_owner(project_id)
  and user_id <> (select created_by from public.projects where id=project_id));
create policy member_update on public.project_members for update to authenticated
 using(public.is_project_owner(project_id))
 with check(public.is_project_owner(project_id) and user_id <> (select created_by from public.projects where id=project_id));
create policy member_delete on public.project_members for delete to authenticated
 using(public.is_project_owner(project_id));

create policy target_read on public.targets for select to authenticated
 using(public.can_view_project(project_id));
create policy target_insert on public.targets for insert to authenticated
 with check(public.can_manage_project(project_id));
create policy target_update on public.targets for update to authenticated
 using(public.can_manage_project(project_id)) with check(public.can_manage_project(project_id));
create policy target_delete on public.targets for delete to authenticated
 using(public.can_manage_project(project_id));

create policy criterion_read on public.criteria for select to authenticated
 using(public.can_view_project(project_id));
create policy criterion_insert on public.criteria for insert to authenticated
 with check(public.can_manage_project(project_id));
create policy criterion_update on public.criteria for update to authenticated
 using(public.can_manage_project(project_id)) with check(public.can_manage_project(project_id));
create policy criterion_delete on public.criteria for delete to authenticated
 using(public.can_manage_project(project_id));

create policy assessment_read on public.assessments for select to authenticated
 using(public.can_view_project(project_id));
create policy assessment_insert on public.assessments for insert to authenticated
 with check(public.can_view_project(project_id) and teacher_id=auth.uid()
  and exists(select 1 from public.targets where id=target_id and project_id=assessments.project_id));
create policy assessment_update on public.assessments for update to authenticated
 using(public.can_view_project(project_id) and teacher_id=auth.uid())
 with check(public.can_view_project(project_id) and teacher_id=auth.uid()
  and exists(select 1 from public.targets where id=target_id and project_id=assessments.project_id));
create policy assessment_delete on public.assessments for delete to authenticated
 using(public.can_view_project(project_id) and teacher_id=auth.uid());

create policy score_read on public.assessment_scores for select to authenticated
 using(exists(select 1 from public.assessments a where a.id=assessment_id
  and public.can_view_project(a.project_id)));
create policy score_insert on public.assessment_scores for insert to authenticated
 with check(exists(select 1 from public.assessments a where a.id=assessment_id
  and a.teacher_id=auth.uid() and public.can_view_project(a.project_id))
  and exists(select 1 from public.criteria c join public.assessments a on a.id=assessment_id
    where c.id=criterion_id and c.project_id=a.project_id));
create policy score_update on public.assessment_scores for update to authenticated
 using(exists(select 1 from public.assessments a where a.id=assessment_id
  and a.teacher_id=auth.uid() and public.can_view_project(a.project_id)))
 with check(exists(select 1 from public.assessments a where a.id=assessment_id
  and a.teacher_id=auth.uid() and public.can_view_project(a.project_id))
  and exists(select 1 from public.criteria c join public.assessments a on a.id=assessment_id
    where c.id=criterion_id and c.project_id=a.project_id));
create policy score_delete on public.assessment_scores for delete to authenticated
 using(exists(select 1 from public.assessments a where a.id=assessment_id
  and a.teacher_id=auth.uid() and public.can_view_project(a.project_id)));

create policy assignments_read on public.project_teacher_criteria for select to authenticated
 using(public.can_view_project(project_id));
create policy assignments_insert on public.project_teacher_criteria for insert to authenticated
 with check(public.can_manage_project(project_id) and exists(
 select 1 from public.criteria where id=criterion_id and project_id=project_teacher_criteria.project_id)
 and (exists(select 1 from public.projects p where p.id=project_id and p.created_by=teacher_id)
 or exists(select 1 from public.project_members m where m.project_id=project_teacher_criteria.project_id and m.user_id=teacher_id)));
create policy assignments_delete on public.project_teacher_criteria for delete to authenticated
 using(public.can_manage_project(project_id));

-- The ownership identity must not be transferable through a generic project update.
create or replace function public.protect_project_creator()
returns trigger language plpgsql set search_path=public as $
begin
 if new.created_by is distinct from old.created_by then
  raise exception 'プロジェクトの作成者は変更できません';
 end if;
 return new;
end $;
drop trigger if exists protect_project_creator on public.projects;
create trigger protect_project_creator before update on public.projects
 for each row execute function public.protect_project_creator();

-- Update the atomic assignment RPC installed by the prior migration.
create or replace function public.set_project_teacher_criteria(
 p_project_id uuid, p_teacher_id uuid, p_criterion_ids uuid[]
) returns void language plpgsql security invoker set search_path=public as $$
declare item_count int; all_count int;
begin
 if not public.can_manage_project(p_project_id) then raise exception '担当設定の権限がありません'; end if;
 if not exists(select 1 from public.profiles where id=p_teacher_id and is_active=true) then raise exception '有効な教員を選択してください'; end if;
 if not (public.is_project_owner(p_project_id) or exists(
  select 1 from public.project_members where project_id=p_project_id and user_id=p_teacher_id
 )) then raise exception 'このプロジェクトの参加教員を選択してください'; end if;
 if p_criterion_ids is null or coalesce(array_length(p_criterion_ids,1),0)=0 then raise exception '担当項目を1つ以上選択してください'; end if;
 if array_position(p_criterion_ids,null) is not null then raise exception '無効な評価項目'; end if;
 select count(distinct id) into item_count from public.criteria
  where project_id=p_project_id and id=any(p_criterion_ids);
 select count(*) into all_count from public.criteria where project_id=p_project_id;
 if item_count<>array_length(p_criterion_ids,1) then raise exception '項目の不一致または重複'; end if;
 delete from public.project_teacher_criteria where project_id=p_project_id and teacher_id=p_teacher_id;
 if item_count<all_count then
  insert into public.project_teacher_criteria(project_id,teacher_id,criterion_id)
  select p_project_id,p_teacher_id,unnest(p_criterion_ids);
 end if;
end $$;
revoke all on function public.set_project_teacher_criteria(uuid,uuid,uuid[]) from public, anon;
grant execute on function public.set_project_teacher_criteria(uuid,uuid,uuid[]) to authenticated;

-- Profiles are readable by active staff for invited-teacher lookup,
-- but modification permissions should remain under the existing staff-management Edge Function.
-- Existing profile policies are intentionally not rewritten here.

commit;
