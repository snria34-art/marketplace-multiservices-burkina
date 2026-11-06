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
  v_decision text := pg_catalog.upper(pg_catalog.btrim(p_decision));
  v_booking_id uuid;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if p_booking_id is null then
    raise exception 'CREATIVE_BOOKING_REQUIRED' using errcode = '22023';
  end if;

  if v_decision is null or v_decision not in ('CONFIRM', 'DECLINE') then
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

revoke all on function public.respond_creative_booking(uuid, text, numeric)
  from public, anon;
grant execute on function public.respond_creative_booking(uuid, text, numeric)
  to authenticated;
