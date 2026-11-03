create or replace function private.get_platform_repair_audit(p_limit integer default 20)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc),'[]'::jsonb) into v_result
  from (
    select id,repair_code,status,details,created_at
    from private.platform_repair_audit
    order by created_at desc
    limit greatest(1,least(coalesce(p_limit,20),100))
  ) q;
  return v_result;
end;
$$;
revoke all on function private.get_platform_repair_audit(integer) from public,anon;
grant execute on function private.get_platform_repair_audit(integer) to authenticated;

create or replace function public.get_platform_repair_audit(p_limit integer default 20)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.get_platform_repair_audit(p_limit);
$$;
revoke all on function public.get_platform_repair_audit(integer) from public,anon;
grant execute on function public.get_platform_repair_audit(integer) to authenticated;

create or replace function private.admin_run_safe_platform_repairs()
returns integer
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  return private.run_safe_platform_repairs();
end;
$$;
revoke all on function private.admin_run_safe_platform_repairs() from public,anon;
grant execute on function private.admin_run_safe_platform_repairs() to authenticated;

create or replace function public.admin_run_safe_platform_repairs()
returns integer language sql security invoker set search_path='' as $$
  select private.admin_run_safe_platform_repairs();
$$;
revoke all on function public.admin_run_safe_platform_repairs() from public,anon;
grant execute on function public.admin_run_safe_platform_repairs() to authenticated;
