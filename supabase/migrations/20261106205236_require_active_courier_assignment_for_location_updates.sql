create or replace function public.record_courier_location(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m numeric default null
)
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, extensions, public
as $function$
declare
  v_user uuid := auth.uid();
  v_id bigint;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not private.has_role('COURIER'::public.user_role) then
    raise exception 'courier_role_required' using errcode = '42501';
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90 then
    raise exception 'latitude_invalid' using errcode = '22023';
  end if;

  if p_longitude is null or p_longitude < -180 or p_longitude > 180 then
    raise exception 'longitude_invalid' using errcode = '22023';
  end if;

  if p_accuracy_m is not null and p_accuracy_m < 0 then
    raise exception 'accuracy_invalid' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.delivery_assignments da
    join public.order_packages op on op.id = da.package_id
    join public.order_groups og on og.id = op.order_group_id
    join public.orders o on o.id = og.order_id
    where da.courier_id = v_user
      and da.status in ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
      and op.status in ('READY_FOR_PICKUP', 'PICKED_UP', 'IN_TRANSIT')
      and og.status <> 'CANCELLED'
      and o.status not in ('CANCELLED', 'REFUNDED')
  ) then
    raise exception 'active_courier_assignment_required' using errcode = '42501';
  end if;

  insert into public.courier_locations(
    courier_id,
    location,
    accuracy_m,
    recorded_at
  )
  values(
    v_user,
    extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography,
    p_accuracy_m,
    now()
  )
  returning id into v_id;

  return v_id;
end;
$function$;

revoke all on function public.record_courier_location(double precision,double precision,numeric)
  from public, anon;
grant execute on function public.record_courier_location(double precision,double precision,numeric)
  to authenticated, service_role;
