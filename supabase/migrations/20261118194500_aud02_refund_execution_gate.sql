-- AUD-02: require an immutable, balanced allocation before any provider refund.
begin;

create or replace function public.get_refund_allocation_candidates(p_refund_id uuid)
returns table (
  order_item_id uuid,
  order_group_id uuid,
  seller_id uuid,
  ordered_quantity integer,
  line_total numeric
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_order_id uuid;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  select r.order_id into v_order_id
  from public.refunds r where r.id = p_refund_id;
  if not found then raise exception 'refund_not_found'; end if;

  return query
  select oi.id, og.id, sh.seller_id, oi.quantity, oi.total_price
  from public.order_items oi
  join public.order_groups og on og.id = oi.order_group_id
  join public.shops sh on sh.id = og.shop_id
  where og.order_id = v_order_id
  order by og.id, oi.id;
end;
$function$;
revoke all on function public.get_refund_allocation_candidates(uuid) from public, anon;
grant execute on function public.get_refund_allocation_candidates(uuid) to authenticated;

create or replace function public.get_refund_allocation_status(p_refund_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  return exists (
    select 1 from public.refund_allocations
    where refund_id = p_refund_id
    group by refund_id
    having count(*) > 0 and sum(customer_amount) = (
      select r.amount from public.refunds r where r.id = p_refund_id
    )
  );
end;
$function$;
revoke all on function public.get_refund_allocation_status(uuid) from public, anon;
grant execute on function public.get_refund_allocation_status(uuid) to authenticated;

-- The normal provider path is only available after admin approval and exact allocation.
create or replace function public.admin_begin_refund(p_refund_id uuid)
returns table (
  refund_id uuid, payment_id uuid, order_id uuid, amount numeric,
  currency text, provider text, provider_reference text, status text
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_payment_id uuid;
  v_amount numeric(14,2);
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'ADMIN_REQUIRED' using errcode = '42501';
  end if;
  if p_refund_id is null then raise exception 'refund_id_required'; end if;

  select r.payment_id, r.amount into v_payment_id, v_amount
  from public.refunds r where r.id = p_refund_id for update;
  if not found or v_payment_id is null then raise exception 'refund_not_found'; end if;

  perform 1 from public.payments p where p.id = v_payment_id for update;
  if not found then raise exception 'payment_not_found'; end if;

  if not exists (
    select 1 from public.refunds r
    join public.payments p on p.id = r.payment_id
    where r.id = p_refund_id and r.status = 'APPROVED'
      and r.amount > 0 and r.amount = trunc(r.amount)
      and r.currency = 'XOF'
      and nullif(trim(p.provider),'') is not null
      and nullif(trim(p.provider_reference),'') is not null
      and p.provider in ('WAVE','CINETPAY','ORANGE_MONEY','MOOV_MONEY')
  ) then
    raise exception 'refund_provider_data_invalid_or_not_approved';
  end if;

  if not exists (
    select 1 from public.refund_allocations ra
    where ra.refund_id = p_refund_id
    group by ra.refund_id
    having count(*) > 0 and sum(ra.customer_amount) = v_amount
  ) then
    raise exception 'refund_allocations_required_or_unbalanced';
  end if;

  if exists (
    select 1
    from private.refund_accounting_reconciliations ar
    join public.refunds prior on prior.id = ar.refund_id
    where ar.payment_id = v_payment_id and ar.refund_id <> p_refund_id
      and ar.status = 'PENDING_ALLOCATION'
      and prior.status in ('PENDING','PROCESSING','COMPLETED','FAILED')
  ) then
    raise exception 'refund_financial_reconciliation_required';
  end if;

  update public.refunds r set status = 'PROCESSING'
  where r.id = p_refund_id and r.status = 'APPROVED';
  if not found then raise exception 'refund_not_requestable_or_requires_reconciliation'; end if;

  return query
  select r.id, r.payment_id, r.order_id, r.amount, r.currency,
         p.provider, p.provider_reference, r.status
  from public.refunds r join public.payments p on p.id = r.payment_id
  where r.id = p_refund_id;
end;
$function$;
revoke all on function public.admin_begin_refund(uuid) from public, anon;
grant execute on function public.admin_begin_refund(uuid) to authenticated;

-- CinetPay's external confirmation is recorded only after allocation exists;
-- local ledger reconciliation is in the same database transaction.
create or replace function public.admin_complete_manual_refund(
  p_refund_id uuid,
  p_provider_reference text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_provider text;
  v_status text;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'ADMIN_REQUIRED' using errcode = '42501';
  end if;
  if nullif(trim(p_provider_reference),'') is null then
    raise exception 'provider_reference_required';
  end if;

  select p.provider, r.status into v_provider, v_status
  from public.refunds r join public.payments p on p.id = r.payment_id
  where r.id = p_refund_id for update of r;
  if not found then raise exception 'refund_not_found'; end if;
  if v_provider <> 'CINETPAY' then raise exception 'manual_completion_not_for_provider'; end if;
  if v_status not in ('APPROVED','PROCESSING','FAILED') then raise exception 'refund_not_completable'; end if;

  if not exists (
    select 1 from public.refund_allocations ra
    join public.refunds r on r.id = ra.refund_id
    where ra.refund_id = p_refund_id
    group by ra.refund_id, r.amount
    having count(*) > 0 and sum(ra.customer_amount) = r.amount
  ) then
    raise exception 'refund_allocations_required_or_unbalanced';
  end if;

  perform public.complete_refund(p_refund_id, trim(p_provider_reference));
  perform public.reconcile_refund_accounting(p_refund_id);
  return true;
end;
$function$;
revoke all on function public.admin_complete_manual_refund(uuid,text) from public, anon;
grant execute on function public.admin_complete_manual_refund(uuid,text) to authenticated;

commit;
