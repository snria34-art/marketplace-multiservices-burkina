create or replace function public.admin_begin_refund(p_refund_id uuid)
returns table(
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
set search_path=pg_catalog,public
as $function$
begin
  if not private.is_admin() then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;

  if p_refund_id is null then
    raise exception 'refund_id_required';
  end if;

  -- Validate all provider data before moving the refund to PROCESSING. The
  -- Edge Function performs the external call only after this state transition.
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

  -- PROCESSING is deliberately excluded: a second concurrent/repeated call
  -- must not launch the same provider refund request again.
  update public.refunds r
  set status='PROCESSING'
  where r.id=p_refund_id
    and r.status in ('REQUESTED','APPROVED','FAILED');

  if not found then
    raise exception 'refund_not_requestable';
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
