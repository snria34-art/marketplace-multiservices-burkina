create or replace function private.admin_get_return_policy_settings()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then raise exception 'admin_access_required'; end if;
  select jsonb_agg(to_jsonb(x) order by x.is_default desc,x.name) into v_result
  from (
    select '00000000-0000-0000-0000-000000000000'::uuid as category_id,
      'Toutes les catégories (par défaut)'::text as name,
      coalesce((select r.return_window_hours from private.return_policy_rules r
        where r.category_id='00000000-0000-0000-0000-000000000000'::uuid),72) as return_window_hours,
      true as is_default
    union all
    select c.id,c.name,
      coalesce(r.return_window_hours,(select d.return_window_hours from private.return_policy_rules d
        where d.category_id='00000000-0000-0000-0000-000000000000'::uuid),72),false
    from public.categories c
    left join private.return_policy_rules r on r.category_id=c.id
    where c.is_active=true
  ) x;
  return coalesce(v_result,'[]'::jsonb);
end;
$$;
revoke all on function private.admin_get_return_policy_settings() from public,anon,authenticated;
create or replace function public.admin_get_return_policy_settings()
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.admin_get_return_policy_settings();
$$;
revoke all on function public.admin_get_return_policy_settings() from public,anon;
grant execute on function public.admin_get_return_policy_settings() to authenticated;