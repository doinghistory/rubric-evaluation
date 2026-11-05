-- Fix project INSERT ... RETURNING under project-scoped RLS.
-- Keep projects private: owner and invited members only.
begin;
drop policy if exists project_read on public.projects;
create policy project_read on public.projects
for select to authenticated
using (
  public.is_active_teacher()
  and (
    created_by = (select auth.uid())
    or exists (
      select 1 from public.project_members m
      where m.project_id = projects.id
        and m.user_id = (select auth.uid())
    )
  )
);
commit;
