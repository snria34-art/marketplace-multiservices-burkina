-- AUD-02: remove legacy prorated seller debits from provider confirmation.
-- Seller ledger entries are now created only by approved refund allocations.
begin;

create or replace function public.complete_refund(
  p_refund_id uuid,
  p_provider_reference text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_refund public.refunds%rowtype;
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
  v_total_refunded numeric(14,2);
begin
  if p_refund_id is null
     or nullif(trim(p_provider_reference), '') is null
     or length(trim(p_provider_reference)) > 200 then
    raise exception 'refund_completion_input_invalid';
  end if;

  select * into v_refund
  from public.refunds
  where id = p_refund_id
  for update;
  if not found then raise exception 'refund_not_found'; end if;
  if v_refund.status = 'COMPLETED' then return true; end if;
  if v_refund.status not in ('APPROVED','PROCESSING','FAILED') then
    raise exception 'refund_not_completable';
  end if;

  select * into v_payment
  from public.payments
  where id = v_refund.payment_id
  for update;
  if not found then raise exception 'payment_not_found'; end if;

  select * into v_order
  from public.orders
  where id = v_refund.order_id
  for update;
  if not found then raise exception 'order_not_found'; end if;

  -- Provider confirmation only changes payment/refund/order state.
  -- Seller ledger entries are posted exclusively by reconcile_refund_accounting
  -- from the immutable, explicitly approved refund_allocations.
  update public.refunds
  set status = 'COMPLETED',
      provider_reference = trim(p_provider_reference),
      completed_at = coalesce(completed_at, now())
  where id = p_refund_id;

  select coalesce(sum(r.amount), 0)
  into v_total_refunded
  from public.refunds r
  where r.payment_id = v_refund.payment_id
    and r.status = 'COMPLETED';

  if v_total_refunded >= v_payment.amount then
    update public.payments
    set status = 'REFUNDED', updated_at = now()
    where id = v_payment.id;

    update public.orders
    set status = 'REFUNDED', updated_at = now()
    where id = v_order.id
      and status in (
        'PAID','CONFIRMED','PREPARING','READY_FOR_PICKUP',
        'PARTIALLY_FULFILLED','IN_TRANSIT','DELIVERED','DISPUTED'
      );

    update public.order_groups
    set status = 'REFUNDED'
    where order_id = v_order.id and status <> 'REFUNDED';
  else
    update public.payments
    set status = 'PARTIALLY_REFUNDED', updated_at = now()
    where id = v_payment.id and status = 'SUCCEEDED';
  end if;

  return true;
end;
$function$;

revoke all on function public.complete_refund(uuid,text) from public, anon, authenticated;
grant execute on function public.complete_refund(uuid,text) to service_role;


create or replace function public.reconcile_refund_accounting(p_refund_id uuid)
returns boolean
language plpgsql security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_refund public.refunds%rowtype;
  v_hold private.refund_accounting_reconciliations%rowtype;
  v_allocation record;
  v_seller record;
  v_balance numeric(14,2);
  v_required numeric(14,2);
  v_total numeric(14,2);
  v_count integer;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  if p_refund_id is null then raise exception 'refund_id_required'; end if;

  select * into v_refund from public.refunds where id = p_refund_id for update;
  if not found then raise exception 'refund_not_found'; end if;
  if v_refund.status <> 'COMPLETED' then raise exception 'provider_refund_not_confirmed'; end if;

  select * into v_hold from private.refund_accounting_reconciliations
  where refund_id = p_refund_id for update;
  if not found or v_hold.status <> 'PENDING_ALLOCATION' then
    if found and v_hold.status = 'RECONCILED' then return true; end if;
    raise exception 'refund_not_pending_allocation';
  end if;

  -- Legacy complete_refund versions wrote a prorated seller REFUND entry.
  -- Never post a second debit when reconciling a refund already processed by that code.
  if exists (
    select 1 from public.seller_ledger
    where reference_id = p_refund_id and entry_type = 'REFUND'
  ) then
    raise exception 'refund_legacy_ledger_entries_present';
  end if;

  select count(*), coalesce(sum(customer_amount),0)
  into v_count, v_total from public.refund_allocations where refund_id = p_refund_id;
  if v_count = 0 then raise exception 'refund_allocations_required'; end if;
  if v_total <> v_refund.amount then raise exception 'refund_allocation_total_mismatch'; end if;

  -- Lock affected commission rows in a stable order. A concurrent allocation or
  -- reconciliation for the same order group must observe the latest reversal total.
  for v_seller in
    select distinct order_group_id
    from public.refund_allocations
    where refund_id = p_refund_id and commission_reversal_amount > 0
    order by order_group_id
  loop
    perform 1 from public.commissions
    where order_group_id = v_seller.order_group_id
    for update;
  end loop;

  -- Stable seller lock order serializes reconciliation against payout requests.
  for v_seller in
    select distinct seller_id from public.refund_allocations
    where refund_id = p_refund_id and (seller_net_debit > 0 or (commission_accounting_mode = 'GROSS_LEDGER' and commission_reversal_amount > 0)) order by seller_id
  loop
    perform 1 from public.sellers where id = v_seller.seller_id for update;
  end loop;

  for v_allocation in
    select * from public.refund_allocations where refund_id = p_refund_id order by id
  loop
    if (v_allocation.seller_net_debit > 0 or (v_allocation.commission_accounting_mode = 'GROSS_LEDGER' and v_allocation.commission_reversal_amount > 0)) and not exists (
      select 1 from public.seller_ledger sl
      where sl.seller_id = v_allocation.seller_id
        and sl.order_group_id = v_allocation.order_group_id
        and sl.entry_type = 'SALE' and sl.amount > 0
    ) then
      raise exception 'refund_seller_sale_not_credited';
    end if;
  end loop;

  for v_seller in
    select seller_id, sum(seller_net_debit)::numeric(14,2) as required_amount
    from public.refund_allocations
    where refund_id = p_refund_id and seller_net_debit > 0
    group by seller_id order by seller_id
  loop
    v_required := v_seller.required_amount;
    select coalesce(sum(amount),0) into v_balance
    from public.seller_ledger
    where seller_id = v_seller.seller_id and currency = 'XOF';
    if v_balance < v_required then raise exception 'refund_seller_balance_insufficient'; end if;
  end loop;

  -- A unique reference per allocation supports sellers with several shops in one order.
  for v_allocation in
    select * from public.refund_allocations where refund_id = p_refund_id order by id
  loop
    if v_allocation.commission_accounting_mode = 'GROSS_LEDGER' then
      insert into public.seller_ledger(
        seller_id, order_group_id, entry_type, amount, currency, reference_id
      ) values (
        v_allocation.seller_id, v_allocation.order_group_id, 'REFUND',
        -(v_allocation.seller_net_debit + v_allocation.commission_reversal_amount),
        'XOF', v_allocation.id
      );
      if v_allocation.commission_reversal_amount > 0 then
        insert into public.seller_ledger(
          seller_id, order_group_id, entry_type, amount, currency, reference_id
        ) values (
          v_allocation.seller_id, v_allocation.order_group_id, 'COMMISSION_REVERSAL',
          v_allocation.commission_reversal_amount, 'XOF', v_allocation.id
        );
      end if;
    elsif v_allocation.commission_accounting_mode = 'NET_SALE' then
      -- The commission was already withheld from SALE; never credit it again.
      if v_allocation.seller_net_debit > 0 then
        insert into public.seller_ledger(
          seller_id, order_group_id, entry_type, amount, currency, reference_id
        ) values (
          v_allocation.seller_id, v_allocation.order_group_id, 'REFUND',
          -v_allocation.seller_net_debit, 'XOF', v_allocation.id
        );
      end if;
    elsif v_allocation.seller_net_debit > 0 then
      insert into public.seller_ledger(
        seller_id, order_group_id, entry_type, amount, currency, reference_id
      ) values (
        v_allocation.seller_id, v_allocation.order_group_id, 'REFUND',
        -v_allocation.seller_net_debit, 'XOF', v_allocation.id
      );
    end if;
  end loop;

  update public.refund_allocations set ledger_posted_at = now() where refund_id = p_refund_id;

  -- Partial returns retain POSTED; only a fully reversed commission changes status.
  update public.commissions c
  set status = case when c.status = 'POSTED' then 'REVERSED' else 'CANCELLED' end
  where c.status in ('POSTED','PENDING')
    and exists (
      select 1 from public.refund_allocations ra
      where ra.refund_id = p_refund_id
        and ra.order_group_id = c.order_group_id
        and ra.commission_reversal_amount > 0
    )
    and (
      select coalesce(sum(ra2.commission_reversal_amount),0)
      from public.refund_allocations ra2
      join public.refunds r2 on r2.id = ra2.refund_id
      where ra2.order_group_id = c.order_group_id
        and ra2.ledger_posted_at is not null
        and r2.status not in ('REJECTED','CANCELLED')
    ) >= c.commission_amount;

  update private.refund_accounting_reconciliations
  set status = 'RECONCILED',
      note = 'Allocation exacte validée et écritures vendeur comptabilisées.',
      updated_at = now(), reconciled_at = now()
  where refund_id = p_refund_id and status = 'PENDING_ALLOCATION';
  return true;
end;
$function$;


revoke all on function public.reconcile_refund_accounting(uuid) from public, anon;
grant execute on function public.reconcile_refund_accounting(uuid) to authenticated;

commit;
