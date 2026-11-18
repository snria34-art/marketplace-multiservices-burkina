-- AUD-02: explicit line-level refund allocation and internal reconciliation.
-- This migration never contacts a payment provider.
begin;

create table if not exists public.refund_allocations (
  id uuid primary key default gen_random_uuid(),
  refund_id uuid not null references public.refunds(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  order_group_id uuid references public.order_groups(id) on delete restrict,
  order_item_id uuid references public.order_items(id) on delete restrict,
  seller_id uuid references public.sellers(id) on delete restrict,
  allocation_type text not null check (allocation_type in ('ITEM','PLATFORM_ADJUSTMENT')),
  quantity integer,
  customer_amount numeric(14,2) not null check (customer_amount > 0 and customer_amount = trunc(customer_amount)),
  seller_net_debit numeric(14,2) not null default 0 check (seller_net_debit >= 0 and seller_net_debit = trunc(seller_net_debit)),
  commission_reversal_amount numeric(14,2) not null default 0 check (commission_reversal_amount >= 0 and commission_reversal_amount = trunc(commission_reversal_amount)),
  commission_accounting_mode text not null default 'NONE' check (commission_accounting_mode in ('NONE','GROSS_LEDGER','NET_SALE')),
  platform_funded_amount numeric(14,2) not null default 0 check (platform_funded_amount >= 0 and platform_funded_amount = trunc(platform_funded_amount)),
  currency text not null default 'XOF' check (currency = 'XOF'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  ledger_posted_at timestamptz,
  constraint refund_allocation_funding_balanced check (seller_net_debit + commission_reversal_amount + platform_funded_amount = customer_amount),
  constraint refund_allocation_commission_mode_valid check (
    (commission_reversal_amount = 0 and commission_accounting_mode = 'NONE')
    or (commission_reversal_amount > 0 and commission_accounting_mode in ('GROSS_LEDGER','NET_SALE'))
  ),
  constraint refund_allocation_shape_valid check (
    (allocation_type = 'ITEM' and order_group_id is not null and order_item_id is not null
      and seller_id is not null and quantity is not null and quantity > 0)
    or
    (allocation_type = 'PLATFORM_ADJUSTMENT' and order_group_id is null and order_item_id is null
      and seller_id is null and quantity is null and seller_net_debit = 0)
  )
);

create unique index if not exists uq_refund_allocations_refund_item
  on public.refund_allocations(refund_id, order_item_id) where order_item_id is not null;
create index if not exists idx_refund_allocations_seller
  on public.refund_allocations(seller_id, created_at desc) where seller_id is not null;
create index if not exists idx_refund_allocations_order_item
  on public.refund_allocations(order_item_id) where order_item_id is not null;

alter table public.refund_allocations enable row level security;
revoke all on public.refund_allocations from public, anon, authenticated;

comment on table public.refund_allocations is
  'Immutable allocation frozen after approval and before provider execution, or attached to an in-flight/completed recovery. Seller liability is explicitly approved; no cross-seller prorating.';
comment on column public.refund_allocations.seller_net_debit is
  'Final net seller liability explicitly approved by finance after commission reversal.';
comment on column public.refund_allocations.commission_reversal_amount is
  'Explicit amount of original commission reversed/cancelled for this return; ledger treatment depends on the recorded commission accounting mode.';
comment on column public.refund_allocations.commission_accounting_mode is
  'GROSS_LEDGER reverses a separately debited commission in seller_ledger; NET_SALE cancels a commission withheld from the net SALE credit without a second seller-ledger credit.';

create or replace function public.set_refund_allocations(p_refund_id uuid, p_allocations jsonb)
returns integer
language plpgsql security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_refund public.refunds%rowtype;
  v_hold private.refund_accounting_reconciliations%rowtype;
  v_entry record;
  v_item public.order_items%rowtype;
  v_group public.order_groups%rowtype;
  v_commission public.commissions%rowtype;
  v_existing_commission_reversal numeric(14,2);
  v_commission_mode text := 'NONE';
  v_seller_id uuid;
  v_existing_qty integer;
  v_existing_amount numeric(14,2);
  v_inserted integer := 0;
  v_customer_total numeric(14,2) := 0;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  if p_refund_id is null or jsonb_typeof(p_allocations) <> 'array'
     or jsonb_array_length(p_allocations) = 0 then
    raise exception 'refund_allocations_required';
  end if;

  select * into v_refund from public.refunds where id = p_refund_id for update;
  if not found then raise exception 'refund_not_found'; end if;
  if v_refund.status not in ('APPROVED','PROCESSING','COMPLETED') then
    raise exception 'refund_not_eligible_for_allocation';
  end if;
  if v_refund.currency <> 'XOF' or v_refund.amount <> trunc(v_refund.amount) then
    raise exception 'refund_currency_or_amount_invalid';
  end if;

  select * into v_hold
  from private.refund_accounting_reconciliations
  where refund_id = p_refund_id for update;
  if not found or v_hold.status <> 'PENDING_ALLOCATION' then
    raise exception 'refund_not_pending_allocation';
  end if;
  if exists (select 1 from public.refund_allocations where refund_id = p_refund_id) then
    raise exception 'refund_allocations_are_immutable';
  end if;

  for v_entry in
    select * from jsonb_to_recordset(p_allocations) as x(
      allocation_type text, order_item_id uuid, quantity integer,
      customer_amount numeric, seller_net_debit numeric,
      commission_reversal_amount numeric, platform_funded_amount numeric
    )
  loop
    v_commission_mode := 'NONE';
    if v_entry.customer_amount is null or v_entry.customer_amount <= 0
       or v_entry.customer_amount <> trunc(v_entry.customer_amount)
       or coalesce(v_entry.seller_net_debit,0) < 0
       or coalesce(v_entry.seller_net_debit,0) <> trunc(coalesce(v_entry.seller_net_debit,0))
       or coalesce(v_entry.commission_reversal_amount,0) < 0
       or coalesce(v_entry.commission_reversal_amount,0) <> trunc(coalesce(v_entry.commission_reversal_amount,0))
       or coalesce(v_entry.platform_funded_amount,0) < 0
       or coalesce(v_entry.platform_funded_amount,0) <> trunc(coalesce(v_entry.platform_funded_amount,0))
       or coalesce(v_entry.seller_net_debit,0) + coalesce(v_entry.commission_reversal_amount,0)
          + coalesce(v_entry.platform_funded_amount,0) <> v_entry.customer_amount then
      raise exception 'refund_allocation_amount_invalid';
    end if;

    if v_entry.allocation_type = 'ITEM' then
      if v_entry.order_item_id is null or v_entry.quantity is null or v_entry.quantity <= 0 then
        raise exception 'refund_item_quantity_required';
      end if;
      select * into v_item from public.order_items where id = v_entry.order_item_id for update;
      if not found then raise exception 'refund_order_item_not_found'; end if;
      select * into v_group from public.order_groups
      where id = v_item.order_group_id and order_id = v_refund.order_id for update;
      if not found then raise exception 'refund_item_order_mismatch'; end if;
      select sh.seller_id into v_seller_id from public.shops sh where sh.id = v_group.shop_id;
      if v_seller_id is null then raise exception 'refund_item_seller_not_found'; end if;

      if coalesce(v_entry.commission_reversal_amount,0) > 0 then
        select * into v_commission
        from public.commissions
        where order_group_id = v_group.id and seller_id = v_seller_id
        for update;
        if not found then
          raise exception 'refund_commission_not_found';
        end if;

        if v_commission.status = 'POSTED'
           and exists (
             select 1 from public.seller_ledger sl
             where sl.seller_id = v_seller_id and sl.order_group_id = v_group.id
               and sl.entry_type = 'SALE' and sl.amount = v_commission.base_amount
           )
           and exists (
             select 1 from public.seller_ledger sl
             where sl.seller_id = v_seller_id and sl.order_group_id = v_group.id
               and sl.entry_type = 'COMMISSION' and sl.amount = -v_commission.commission_amount
           ) then
          v_commission_mode := 'GROSS_LEDGER';
        elsif v_commission.status = 'PENDING'
           and not exists (
             select 1 from public.seller_ledger sl
             where sl.seller_id = v_seller_id and sl.order_group_id = v_group.id
               and sl.entry_type = 'COMMISSION'
           )
           and (
             (v_commission.base_amount > v_commission.commission_amount and exists (
               select 1 from public.seller_ledger sl
               where sl.seller_id = v_seller_id and sl.order_group_id = v_group.id
                 and sl.entry_type = 'SALE'
                 and sl.amount = v_commission.base_amount - v_commission.commission_amount
             ))
             or
             (v_commission.base_amount = v_commission.commission_amount
               and not exists (
                 select 1 from public.seller_ledger sl
                 where sl.seller_id = v_seller_id and sl.order_group_id = v_group.id
                   and sl.entry_type = 'SALE'
               ))
           ) then
          v_commission_mode := 'NET_SALE';
        else
          raise exception 'refund_commission_ledger_convention_unknown';
        end if;

        select coalesce(sum(commission_reversal_amount),0)
        into v_existing_commission_reversal
        from public.refund_allocations ra
        join public.refunds r on r.id = ra.refund_id
        where ra.order_group_id = v_group.id
          and ra.commission_reversal_amount > 0
          and r.status not in ('REJECTED','CANCELLED');
        if v_existing_commission_reversal + v_entry.commission_reversal_amount > v_commission.commission_amount then
          raise exception 'refund_commission_reversal_exceeds_original';
        end if;
      end if;

      select coalesce(sum(ra.quantity),0), coalesce(sum(ra.customer_amount),0)
      into v_existing_qty, v_existing_amount
      from public.refund_allocations ra
      join public.refunds r on r.id = ra.refund_id
      where ra.order_item_id = v_item.id and r.status not in ('REJECTED','CANCELLED');
      if v_existing_qty + v_entry.quantity > v_item.quantity then
        raise exception 'refund_quantity_exceeds_ordered';
      end if;
      if v_existing_amount + v_entry.customer_amount > v_item.total_price then
        raise exception 'refund_item_amount_exceeds_line_total';
      end if;

      insert into public.refund_allocations(
        refund_id, order_id, order_group_id, order_item_id, seller_id,
        allocation_type, quantity, customer_amount, seller_net_debit,
        commission_reversal_amount, commission_accounting_mode, platform_funded_amount, currency, created_by
      ) values (
        p_refund_id, v_refund.order_id, v_group.id, v_item.id, v_seller_id,
        'ITEM', v_entry.quantity, v_entry.customer_amount,
        coalesce(v_entry.seller_net_debit,0), coalesce(v_entry.commission_reversal_amount,0),
        v_commission_mode, coalesce(v_entry.platform_funded_amount,0),
        'XOF', auth.uid()
      );
    elsif v_entry.allocation_type = 'PLATFORM_ADJUSTMENT' then
      if v_entry.order_item_id is not null or v_entry.quantity is not null
         or coalesce(v_entry.seller_net_debit,0) <> 0
         or coalesce(v_entry.commission_reversal_amount,0) <> 0
         or coalesce(v_entry.platform_funded_amount,0) <> v_entry.customer_amount then
        raise exception 'platform_adjustment_must_be_platform_funded';
      end if;
      insert into public.refund_allocations(
        refund_id, order_id, allocation_type, customer_amount,
        seller_net_debit, platform_funded_amount, currency, created_by
      ) values (
        p_refund_id, v_refund.order_id, 'PLATFORM_ADJUSTMENT', v_entry.customer_amount,
        0, v_entry.customer_amount, 'XOF', auth.uid()
      );
    else
      raise exception 'refund_allocation_type_invalid';
    end if;

    v_customer_total := v_customer_total + v_entry.customer_amount;
    v_inserted := v_inserted + 1;
  end loop;

  if v_customer_total <> v_refund.amount then raise exception 'refund_allocation_total_mismatch'; end if;
  return v_inserted;
end;
$function$;

revoke all on function public.set_refund_allocations(uuid,jsonb) from public, anon;
grant execute on function public.set_refund_allocations(uuid,jsonb) to authenticated;

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
    if v_allocation.seller_net_debit > 0
       or (v_allocation.commission_accounting_mode = 'GROSS_LEDGER' and v_allocation.commission_reversal_amount > 0) then
      insert into public.seller_ledger(
        seller_id, order_group_id, entry_type, amount, currency, reference_id
      ) values (
        v_allocation.seller_id, v_allocation.order_group_id, 'REFUND',
        -(v_allocation.seller_net_debit
          + case when v_allocation.commission_accounting_mode = 'GROSS_LEDGER'
                 then v_allocation.commission_reversal_amount else 0 end),
        'XOF', v_allocation.id
      );
    end if;
    if v_allocation.commission_accounting_mode = 'GROSS_LEDGER'
       and v_allocation.commission_reversal_amount > 0 then
      insert into public.seller_ledger(
        seller_id, order_group_id, entry_type, amount, currency, reference_id
      ) values (
        v_allocation.seller_id, v_allocation.order_group_id, 'COMMISSION_REVERSAL',
        v_allocation.commission_reversal_amount, 'XOF', v_allocation.id
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

-- Manual recovery path for a provider-confirmed refund whose local completion failed.
-- An administrator must verify the provider dashboard/reference before calling this RPC.
create or replace function public.record_provider_refund_confirmation(
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
  v_total_refunded numeric(14,2);
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  if p_refund_id is null or nullif(trim(p_provider_reference),'') is null
     or length(trim(p_provider_reference)) > 200 then
    raise exception 'provider_refund_reference_invalid';
  end if;

  select * into v_refund
  from public.refunds where id = p_refund_id for update;
  if not found then raise exception 'refund_not_found'; end if;

  if v_refund.status = 'COMPLETED' then
    if trim(coalesce(v_refund.provider_reference,'')) = trim(p_provider_reference) then
      return true;
    end if;
    raise exception 'provider_refund_reference_conflict';
  end if;
  if v_refund.status <> 'PROCESSING' then
    raise exception 'refund_not_processing';
  end if;

  select * into v_payment
  from public.payments where id = v_refund.payment_id for update;
  if not found then raise exception 'payment_not_found'; end if;
  if v_payment.currency <> 'XOF' or v_refund.currency <> 'XOF' then
    raise exception 'refund_currency_not_supported';
  end if;

  update public.refunds
  set status = 'COMPLETED',
      provider_reference = trim(p_provider_reference),
      completed_at = coalesce(completed_at, now())
  where id = p_refund_id;

  select coalesce(sum(amount),0) into v_total_refunded
  from public.refunds
  where payment_id = v_payment.id and status = 'COMPLETED';

  update public.payments
  set status = case when v_total_refunded >= v_payment.amount
                    then 'REFUNDED'::public.payment_status
                    else 'PARTIALLY_REFUNDED'::public.payment_status end,
      updated_at = now()
  where id = v_payment.id
    and status in ('SUCCEEDED','PARTIALLY_REFUNDED','REFUNDED');

  return true;
end;
$function$;

revoke all on function public.record_provider_refund_confirmation(uuid,text) from public, anon;
grant execute on function public.record_provider_refund_confirmation(uuid,text) to authenticated;

commit;
