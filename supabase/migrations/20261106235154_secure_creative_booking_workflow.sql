begin;

revoke insert, update, delete, truncate, references, trigger
  on table public.creative_bookings
  from anon, authenticated;

grant select on table public.creative_bookings to authenticated;

drop policy if exists creative_bookings_own on public.creative_bookings;
create policy creative_bookings_customer_read
  on public.creative_bookings
  for select
  to authenticated
  using (customer_id = (select auth.uid()));

create or replace function public.request_creative_booking(
  p_service_id uuid,
  p_scheduled_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_service_id uuid;
  v_booking_id uuid;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_service_id is null then
    raise exception 'CREATIVE_SERVICE_REQUIRED' using errcode = '22023';
  end if;

  if p_scheduled_at is not null and p_scheduled_at <= pg_catalog.now() then
    raise exception 'CREATIVE_BOOKING_SCHEDULE_MUST_BE_FUTURE'
      using errcode = '22023';
  end if;

  select cs.id
    into v_service_id
  from public.creative_services cs
  join public.service_providers sp on sp.id = cs.provider_id
  where cs.id = p_service_id
    and cs.active = true
    and sp.active = true
    and sp.verification_status = 'VERIFIED'::public.verification_status
  for share of cs, sp;

  if v_service_id is null then
    raise exception 'CREATIVE_SERVICE_NOT_AVAILABLE'
      using errcode = 'P0002';
  end if;

  insert into public.creative_bookings (
    service_id, customer_id, scheduled_at, status, agreed_amount
  )
  values (v_service_id, v_user, p_scheduled_at, 'REQUESTED', null)
  returning id into v_booking_id;

  return v_booking_id;
end;
$function$;

create or replace function public.cancel_creative_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_booking_id uuid;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_booking_id is null then
    raise exception 'CREATIVE_BOOKING_REQUIRED' using errcode = '22023';
  end if;

  update public.creative_bookings cb
  set status = 'CANCELLED'
  where cb.id = p_booking_id
    and cb.customer_id = v_user
    and cb.status = 'REQUESTED'
  returning cb.id into v_booking_id;

  if v_booking_id is null then
    raise exception 'CREATIVE_BOOKING_NOT_PENDING_OR_NOT_OWNED'
      using errcode = '42501';
  end if;
end;
$function$;

create or replace function public.get_provider_creative_bookings()
returns table (
  booking_id uuid,
  service_id uuid,
  service_name text,
  category text,
  customer_id uuid,
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
  select cb.id, cb.service_id, cs.name, cs.category, cb.customer_id,
         cb.scheduled_at, cb.status, cb.agreed_amount
  from public.creative_bookings cb
  join public.creative_services cs on cs.id = cb.service_id
  join public.service_providers sp on sp.id = cs.provider_id
  where sp.user_id = v_user
  order by cb.scheduled_at nulls last, cb.id;
end;
$function$;

create or replace function public.respond_creative_booking(
  p_booking_id uuid,
  p_decision text,
  p_agreed_amount numeric default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid := (select auth.uid());
  v_decision text := pg_catalog.upper(pg_catalog.trim(p_decision));
  v_booking_id uuid;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_booking_id is null then
    raise exception 'CREATIVE_BOOKING_REQUIRED' using errcode = '22023';
  end if;

  if v_decision not in ('CONFIRM', 'DECLINE') then
    raise exception 'CREATIVE_BOOKING_DECISION_INVALID'
      using errcode = '22023';
  end if;

  if v_decision = 'CONFIRM'
     and (p_agreed_amount is null or p_agreed_amount < 0) then
    raise exception 'CREATIVE_BOOKING_AMOUNT_REQUIRED'
      using errcode = '22023';
  end if;

  if v_decision = 'DECLINE' and p_agreed_amount is not null then
    raise exception 'CREATIVE_BOOKING_DECLINE_MUST_NOT_SET_AMOUNT'
      using errcode = '22023';
  end if;

  update public.creative_bookings cb
  set status = case
        when v_decision = 'CONFIRM' then 'CONFIRMED'
        else 'CANCELLED'
      end,
      agreed_amount = case
        when v_decision = 'CONFIRM' then p_agreed_amount
        else cb.agreed_amount
      end
  from public.creative_services cs
  join public.service_providers sp on sp.id = cs.provider_id
  where cb.id = p_booking_id
    and cb.service_id = cs.id
    and sp.user_id = v_user
    and cb.status = 'REQUESTED'
    and (
      v_decision = 'DECLINE'
      or (
        cs.active = true
        and sp.active = true
        and sp.verification_status = 'VERIFIED'::public.verification_status
      )
    )
  returning cb.id into v_booking_id;

  if v_booking_id is null then
    raise exception 'CREATIVE_BOOKING_NOT_PENDING_OR_NOT_OWNED'
      using errcode = '42501';
  end if;
end;
$function$;

revoke all on function public.request_creative_booking(uuid, timestamptz)
  from public, anon;
grant execute on function public.request_creative_booking(uuid, timestamptz)
  to authenticated;
revoke all on function public.cancel_creative_booking(uuid) from public, anon;
grant execute on function public.cancel_creative_booking(uuid) to authenticated;
revoke all on function public.get_provider_creative_bookings() from public, anon;
grant execute on function public.get_provider_creative_bookings() to authenticated;
revoke all on function public.respond_creative_booking(uuid, text, numeric)
  from public, anon;
grant execute on function public.respond_creative_booking(uuid, text, numeric)
  to authenticated;

comment on function public.request_creative_booking(uuid, timestamptz)
  is 'Creates a creative service booking for the authenticated active customer; service/provider availability is validated server-side.';
comment on function public.cancel_creative_booking(uuid)
  is 'Allows the authenticated customer to cancel only their own REQUESTED creative booking.';
comment on function public.get_provider_creative_bookings()
  is 'Returns creative bookings only for services owned by the authenticated active service provider.';
comment on function public.respond_creative_booking(uuid, text, numeric)
  is 'Allows the owning provider to confirm a pending booking with a server-recorded amount or decline it.';

commit;
