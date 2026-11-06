begin;

drop function public.get_provider_creative_bookings();

create function public.get_provider_creative_bookings()
returns table (
  booking_id uuid,
  service_id uuid,
  service_name text,
  category text,
  scheduled_at timestamptz,
  status text,
  agreed_amount numeric
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.service_providers sp where sp.user_id = v_user
  ) then
    raise exception 'CREATIVE_PROVIDER_PROFILE_REQUIRED'
      using errcode = '42501';
  end if;

  return query
  select
    cb.id,
    cb.service_id,
    cs.name,
    cs.category,
    cb.scheduled_at,
    cb.status,
    cb.agreed_amount
  from public.creative_bookings cb
  join public.creative_services cs on cs.id = cb.service_id
  join public.service_providers sp on sp.id = cs.provider_id
  where sp.user_id = v_user
  order by cb.scheduled_at nulls last, cb.id;
end;
$function$;

revoke all on function public.get_provider_creative_bookings()
  from public, anon;
grant execute on function public.get_provider_creative_bookings()
  to authenticated;

commit;
