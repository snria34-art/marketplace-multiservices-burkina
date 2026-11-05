create or replace function public.start_package_delivery(p_package_id uuid)
returns uuid
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_id uuid;
  v_user uuid := (select auth.uid());
begin
  perform private.require_active_account();
  if v_user is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if not private.has_role('COURIER'::public.user_role) then
    raise exception 'courier_role_required' using errcode='42501';
  end if;

  update public.order_packages p
  set status='IN_TRANSIT',updated_at=now()
  where p.id=p_package_id
    and p.status='PICKED_UP'
    and exists (
      select 1
      from public.delivery_assignments da
      where da.package_id=p.id
        and da.courier_id=v_user
        and da.status='PICKED_UP'
    )
  returning p.id into v_id;

  if v_id is null then
    raise exception 'package_not_in_courier_possession';
  end if;

  update public.delivery_assignments
  set status='IN_TRANSIT'
  where package_id=p_package_id
    and courier_id=v_user
    and status='PICKED_UP';

  return v_id;
end;
$function$;

revoke all on function public.start_package_delivery(uuid) from public,anon,authenticated;
grant execute on function public.start_package_delivery(uuid) to authenticated,service_role;
