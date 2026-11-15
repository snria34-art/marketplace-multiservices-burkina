-- Keep a single provider checkout session attached to each payment.
-- Concurrent Edge Function calls may both create a provider session before
-- either one persists its reference. The payment row lock makes the first
-- persisted reference authoritative and rejects a competing session.

create or replace function public.prepare_payment_processing(
  p_payment_id uuid,
  p_provider_reference text,
  p_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path to pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_payment_id is null
     or nullif(trim(p_provider_reference), '') is null then
    raise exception 'payment_session_invalid';
  end if;

  select *
  into v_payment
  from public.payments
  where id = p_payment_id
  for update;

  if not found then
    raise exception 'payment_not_found';
  end if;

  select *
  into v_order
  from public.orders
  where id = v_payment.order_id
    and customer_id = v_user
  for update;

  if not found then
    raise exception 'order_not_owned';
  end if;

  if v_order.status <> 'PENDING_PAYMENT' then
    raise exception 'order_not_payable';
  end if;

  if v_payment.status not in ('PENDING', 'PROCESSING') then
    raise exception 'payment_not_pending';
  end if;

  if v_payment.provider not in ('WAVE', 'ORANGE_MONEY', 'MOOV_MONEY', 'CINETPAY') then
    raise exception 'provider_not_supported';
  end if;

  -- A second caller may have created another external session while waiting
  -- for this row lock. Never replace the reference already persisted by the
  -- first caller, and never return the competing session as usable.
  if v_payment.status = 'PROCESSING'
     and nullif(trim(v_payment.provider_reference), '') is not null then
    if v_payment.provider_reference <> trim(p_provider_reference) then
      raise exception 'payment_session_already_prepared';
    end if;
    return true;
  end if;

  update public.payments
  set status = 'PROCESSING',
      provider_reference = coalesce(provider_reference, trim(p_provider_reference)),
      metadata = coalesce(metadata, '{}'::jsonb) || coalesce(p_metadata, '{}'::jsonb),
      updated_at = now()
  where id = p_payment_id;

  return true;
end;
$function$;

revoke all on function public.prepare_payment_processing(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.prepare_payment_processing(uuid, text, jsonb)
  to authenticated;
