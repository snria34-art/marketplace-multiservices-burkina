-- Validate provider data before claiming a refund and prevent duplicate provider calls.
-- PROCESSING and FAILED refunds require manual reconciliation; only REQUESTED/APPROVED may be claimed.
create or replace function public.admin_begin_refund(p_refund_id uuid)
returns table (
  refund_id uuid,
  payment_id uuid,
  order_id uuid,
  amount numeric,
  currency text,
  provider text,
  provider_reference text,
  status text
)
language plpgsql
security definer
set search_path to pg_catalog, public
as $function$
begin
  if not private.is_admin() then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;

  if p_refund_id is null then
    raise exception 'refund_id_required';
  end if;

  -- Validate all provider data before moving the refund to PROCESSING.
  if not exists (
    select 1
    from public.refunds r
    join public.payments p on p.id=r.payment_id
    where r.id=p_refund_id
      and r.amount>0
      and r.currency='XOF'
      and nullif(trim(p.provider),'') is not null
      and nullif(trim(p.provider_reference),'') is not null
      and p.provider in ('WAVE','CINETPAY','ORANGE_MONEY','MOOV_MONEY')
  ) then
    raise exception 'refund_provider_data_invalid';
  end if;

  -- Atomic claim: only an unstarted refund may move to PROCESSING.
  -- Failed or in-flight provider attempts require manual reconciliation.
  update public.refunds r
  set status='PROCESSING'
  where r.id=p_refund_id
    and r.status in ('REQUESTED','APPROVED');

  if not found then
    raise exception 'refund_not_requestable_or_requires_reconciliation';
  end if;

  return query
  select
    r.id,
    r.payment_id,
    r.order_id,
    r.amount,
    r.currency,
    p.provider,
    p.provider_reference,
    r.status
  from public.refunds r
  join public.payments p on p.id=r.payment_id
  where r.id=p_refund_id;
end;
$function$;

revoke all on function public.admin_begin_refund(uuid) from public;
revoke all on function public.admin_begin_refund(uuid) from anon;
grant execute on function public.admin_begin_refund(uuid) to authenticated;
