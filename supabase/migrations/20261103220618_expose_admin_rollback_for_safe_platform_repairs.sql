create or replace function public.rollback_platform_repair(p_backup_id uuid)
returns boolean language sql security invoker set search_path='' as $$
  select private.rollback_platform_repair(p_backup_id);
$$;
revoke all on function public.rollback_platform_repair(uuid) from public,anon;
grant execute on function public.rollback_platform_repair(uuid) to authenticated;