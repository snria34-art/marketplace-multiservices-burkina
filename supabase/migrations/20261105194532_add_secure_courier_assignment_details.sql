create or replace function public.get_courier_assignments()
returns table(
  assignment_id uuid,
  package_id uuid,
  status public.delivery_status,
  assigned_at timestamptz,
  shop_name text,
  shop_address text,
  shop_phone text,
  recipient_name text,
  recipient_phone text,
  delivery_address_line text,
  delivery_city text,
  delivery_latitude text,
  delivery_longitude text
)
language plpgsql
stable
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_user uuid := (select auth.uid());
begin
  perform private.require_active_account();
  if v_user is null then
    raise exception 'not_authenticated' using errcode='42501';
  end if;
  if not private.has_role('COURIER'::public.user_role) then
    raise exception 'courier_role_required' using errcode='42501';
  end if;

  return query
  select
    da.id,
    da.package_id,
    da.status,
    da.assigned_at,
    sh.name,
    sh.address,
    case
      when da.status in ('ACCEPTED','PICKED_UP','IN_TRANSIT') then sh.phone
      else null
    end,
    case
      when da.status in ('ACCEPTED','PICKED_UP','IN_TRANSIT') then o.delivery_address->>'recipient_name'
      else null
    end,
    case
      when da.status in ('ACCEPTED','PICKED_UP','IN_TRANSIT') then o.delivery_address->>'phone'
      else null
    end,
    o.delivery_address->>'address_line',
    o.delivery_address->>'city',
    o.delivery_address->>'latitude',
    o.delivery_address->>'longitude'
  from public.delivery_assignments da
  join public.order_packages op on op.id=da.package_id
  join public.order_groups og on og.id=op.order_group_id
  join public.shops sh on sh.id=og.shop_id
  join public.orders o on o.id=og.order_id
  where da.courier_id=v_user
    and da.status in ('ASSIGNED','ACCEPTED','PICKED_UP','IN_TRANSIT')
    and op.status in ('READY_FOR_PICKUP','PICKED_UP','IN_TRANSIT')
    and og.status<>'CANCELLED'
    and o.status not in ('CANCELLED','REFUNDED')
  order by da.assigned_at desc;
end;
$function$;

revoke all on function public.get_courier_assignments() from public,anon;
grant execute on function public.get_courier_assignments() to authenticated,service_role;
