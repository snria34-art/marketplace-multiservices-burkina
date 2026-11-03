create or replace function private.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.admin_users au
    join public.profiles p on p.id=au.user_id
    where au.user_id=auth.uid() and au.active=true
      and p.status='ACTIVE'::public.account_status
  );
$$;
create or replace function public.is_admin_actor()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.user_roles ur
    join public.profiles p on p.id=ur.user_id
    where ur.user_id=auth.uid() and p.status='ACTIVE'::public.account_status
      and ur.role in ('ADMIN'::public.user_role,'SUPER_ADMIN'::public.user_role,'MODERATOR'::public.user_role)
  );
$$;
revoke all on function private.is_admin() from public, anon, authenticated;
revoke all on function public.is_admin_actor() from public, anon;
grant execute on function public.is_admin_actor() to authenticated;