
-- Phase 1: delivery enum repair, payment event idempotency, and safe refund holds.


create table if not exists private.refund_accounting_reconciliations (
  refund_id uuid primary key references public.refunds(id) on delete restrict,
  payment_id uuid not null references public.payments(id) on delete restrict,
  order_id uuid not null references public.orders(id) on delete restrict,
  amount numeric(14,2) not null check(amount>0),
  currency text not null check(currency='XOF'),
  status text not null check(status in ('PENDING_ALLOCATION','RECONCILED')),
  provider_reference text,
  note text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reconciled_at timestamptz
);
alter table private.refund_accounting_reconciliations enable row level security;
revoke all on private.refund_accounting_reconciliations from public,anon,authenticated;
create index if not exists idx_refund_accounting_reconciliation_payment on private.refund_accounting_reconciliations(payment_id,status);
create index if not exists idx_refund_accounting_reconciliation_order on private.refund_accounting_reconciliations(order_id,status);

create or replace function private.sync_refund_accounting_hold()
returns trigger language plpgsql security definer set search_path='' as $function$
declare v_hold_status text; v_note text;
begin
  perform s.id
  from public.sellers s
  join public.shops sh on sh.seller_id=s.id
  join public.order_groups og on og.shop_id=sh.id
  where og.order_id=new.order_id
  order by s.id
  for update of s;

  if new.status in ('REJECTED','CANCELLED') then
    v_hold_status := 'RECONCILED';
    v_note := 'Demande rejetée ou annulée : aucune allocation vendeur à comptabiliser.';
  else
    v_hold_status := 'PENDING_ALLOCATION';
    v_note := 'Rapprochement requis : identifier les articles/quantités, vendeurs, remises et commissions avant de libérer les paiements vendeurs.';
  end if;

  insert into private.refund_accounting_reconciliations(
    refund_id,payment_id,order_id,amount,currency,status,provider_reference,note
  )
  values(new.id,new.payment_id,new.order_id,new.amount,new.currency,v_hold_status,new.provider_reference,v_note)
  on conflict(refund_id) do update set
    payment_id=excluded.payment_id,order_id=excluded.order_id,amount=excluded.amount,
    currency=excluded.currency,status=excluded.status,provider_reference=excluded.provider_reference,
    note=excluded.note,updated_at=now(),
    reconciled_at=case when excluded.status='RECONCILED' then now() else null end;
  return new;
end;
$function$;
revoke all on function private.sync_refund_accounting_hold() from public,anon,authenticated;
drop trigger if exists trg_sync_refund_accounting_hold on public.refunds;
create trigger trg_sync_refund_accounting_hold
after insert or update of status,amount,payment_id,order_id,provider_reference
on public.refunds for each row execute function private.sync_refund_accounting_hold();

insert into private.refund_accounting_reconciliations(
  refund_id,payment_id,order_id,amount,currency,status,provider_reference,note
)
select r.id,r.payment_id,r.order_id,r.amount,r.currency,
  case when r.status in ('REJECTED','CANCELLED') then 'RECONCILED' else 'PENDING_ALLOCATION' end,
  r.provider_reference,
  case when r.status in ('REJECTED','CANCELLED')
    then 'Demande rejetée ou annulée : aucune allocation vendeur à comptabiliser.'
    else 'Revue historique requise : vérifier les écritures ledger existantes avant de libérer les paiements vendeurs.' end
from public.refunds r on conflict(refund_id) do nothing;


create or replace function public.assign_package_to_courier(
  p_package_id uuid,
  p_courier_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog','public'
as $function$
declare
  v_id uuid;
begin
  if not exists (
    select 1
    from public.delivery_drivers
    where id = p_courier_id
      and active = true
  ) then
    raise exception 'courier_not_found';
  end if;

  if exists (
    select 1
    from public.delivery_assignments
    where package_id = p_package_id
      and status not in ('CANCELLED','DELIVERED')
  ) then
    raise exception 'package_already_assigned';
  end if;

  update public.order_packages op
  set status = 'READY_FOR_PICKUP',
      updated_at = now()
  from public.order_groups og
  join public.orders o on o.id = og.order_id
  where op.id = p_package_id
    and op.order_group_id = og.id
    and op.status = 'CREATED'
    and o.status in (
      'PAID',
      'CONFIRMED',
      'PREPARING',
      'READY_FOR_PICKUP',
      'PARTIALLY_FULFILLED'
    )
    and og.status in (
      'PAID',
      'CONFIRMED',
      'PREPARING',
      'READY_FOR_PICKUP',
      'PARTIALLY_FULFILLED'
    )
  returning op.id into v_id;

  if v_id is null then
    raise exception 'package_not_ready_for_assignment';
  end if;

  insert into public.delivery_assignments(
    package_id,
    courier_id,
    status,
    assigned_at
  )
  values(
    p_package_id,
    p_courier_id,
    'ASSIGNED',
    now()
  )
  returning id into v_id;

  return v_id;
end;
$function$;
revoke all on function public.assign_package_to_courier(uuid,uuid) from public,anon,authenticated;
grant execute on function public.assign_package_to_courier(uuid,uuid) to service_role;

create or replace function public.sync_after_package_delivery(p_package_id uuid)
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare v_group uuid; v_order uuid; v_status public.order_status;
begin
 select op.order_group_id,og.order_id into v_group,v_order
 from public.order_packages op join public.order_groups og on og.id=op.order_group_id
 where op.id=p_package_id;
 if v_group is null then raise exception 'package_not_found'; end if;

 update public.delivery_assignments
 set status='DELIVERED',completed_at=now()
 where package_id=p_package_id and status in ('IN_TRANSIT','PICKED_UP','ACCEPTED');

 select public.sync_parent_order_status(v_order) into v_status;
 return true;
end;
$$;
revoke all on function public.sync_after_package_delivery(uuid) from public,anon,authenticated;
grant execute on function public.sync_after_package_delivery(uuid) to service_role;


alter table public.payment_events add column if not exists provider_event_id text;
alter table public.payment_events drop constraint if exists payment_events_provider_event_id_valid;
alter table public.payment_events add constraint payment_events_provider_event_id_valid
check(provider_event_id is null or length(trim(provider_event_id)) between 1 and 255);

drop index if exists public.uq_payment_events_provider_ref;
drop index if exists public.ux_payment_events_idempotency;
create index if not exists idx_payment_events_provider_reference on public.payment_events(provider_reference) where provider_reference is not null;
create unique index if not exists uq_payment_events_provider_event_id on public.payment_events(provider_event_id) where provider_event_id is not null;
create unique index if not exists uq_payment_events_legacy_idempotency on public.payment_events(payment_id,event_type,coalesce(provider_reference,'')) where provider_event_id is null;

create or replace function public.process_payment_event(
 p_payment_id uuid,p_event_type text,p_status public.payment_status,p_provider_reference text,
 p_amount numeric,p_provider_event_id text,p_payload jsonb default '{}'::jsonb
)
returns boolean language plpgsql security definer set search_path=pg_catalog,public as $function$
declare
  v_payment public.payments%rowtype;
  v_order public.orders%rowtype;
  v_item record;
  v_coupon_id uuid;
  v_refund_total numeric := 0;
  v_refund_inflight boolean := false;
  v_refund_remaining numeric := 0;
begin
  if p_payment_id is null
     or p_event_type is null
     or length(trim(p_event_type)) = 0 then
    raise exception 'payment_event_invalid';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'payment_amount_invalid';
  end if;

  select * into v_payment
  from public.payments
  where id=p_payment_id
  for update;

  if not found then
    raise exception 'payment_not_found';
  end if;

  if v_payment.amount <> p_amount or v_payment.currency <> 'XOF' then
    raise exception 'payment_amount_mismatch';
  end if;

  if p_provider_event_id is not null then
    if length(trim(p_provider_event_id)) = 0 or length(trim(p_provider_event_id)) > 255 then
      raise exception 'payment_provider_event_id_invalid';
    end if;
    if exists (
      select 1 from public.payment_events
      where provider_event_id=trim(p_provider_event_id) and payment_id=p_payment_id
    ) then return true; end if;
    if exists (
      select 1 from public.payment_events
      where provider_event_id=trim(p_provider_event_id) and payment_id<>p_payment_id
    ) then raise exception 'payment_provider_event_identity_conflict'; end if;
  else
    -- Compatibility path for older internal callers. New provider webhooks
    -- always send a stable event identity.
    if exists (
      select 1 from public.payment_events
      where payment_id=p_payment_id
        and event_type=trim(p_event_type)
        and provider_event_id is null
        and coalesce(provider_reference,'')=coalesce(p_provider_reference,'')
    ) then return true; end if;
  end if;

  insert into public.payment_events(
    payment_id,event_type,provider_reference,provider_event_id,payload
  )
  values(
    p_payment_id,trim(p_event_type),p_provider_reference,
    nullif(trim(p_provider_event_id),''),coalesce(p_payload,'{}'::jsonb)
  );

  if p_status = 'SUCCEEDED' then
    if v_payment.status not in ('SUCCEEDED','REFUNDED','PARTIALLY_REFUNDED') then
      update public.payments
      set status='SUCCEEDED',
          provider_reference=coalesce(p_provider_reference,provider_reference),
          metadata=coalesce(metadata,'{}'::jsonb) || coalesce(p_payload,'{}'::jsonb),
          updated_at=now()
      where id=p_payment_id;
    end if;

    select * into v_order
    from public.orders
    where id=v_payment.order_id
    for update;

    if not found then raise exception 'order_not_found'; end if;

    if v_order.status = 'CANCELLED' then
      -- The provider has captured money for an order that can no longer be
      -- fulfilled. Queue the outstanding refund for admin processing; never
      -- call a payment provider from this database transaction.
      select
        coalesce(sum(r.amount),0),
        coalesce(bool_or(r.status in ('REQUESTED','APPROVED','PENDING','PROCESSING','FAILED')),false)
      into v_refund_total,v_refund_inflight
      from public.refunds r
      where r.payment_id=p_payment_id
        and r.status not in ('REJECTED','CANCELLED');

      v_refund_remaining := greatest(0,v_payment.amount-v_refund_total);

      if not v_refund_inflight and v_refund_remaining > 0 then
        insert into public.refunds(
          payment_id,order_id,amount,currency,reason,status
        )
        values(
          p_payment_id,
          v_order.id,
          v_refund_remaining,
          'XOF',
          'Payment succeeded after order cancellation; refund required',
          'REQUESTED'
        );
      end if;

      return true;
    end if;

    if v_order.status = 'PENDING_PAYMENT' then
      update public.orders
      set status='PAID',updated_at=now()
      where id=v_order.id;

      update public.order_groups
      set status='PAID'
      where order_id=v_order.id
        and status='PENDING_PAYMENT';

      insert into public.order_events(
        order_id,actor_id,status,metadata
      )
      values(
        v_order.id,null,'PAID',
        jsonb_build_object(
          'payment_id',p_payment_id,
          'provider_reference',p_provider_reference
        )
      );
    end if;

    return true;
  end if;

  if v_payment.status in ('SUCCEEDED','REFUNDED','PARTIALLY_REFUNDED') then
    return true;
  end if;

  update public.payments
  set status=p_status,
      provider_reference=coalesce(p_provider_reference,provider_reference),
      metadata=coalesce(metadata,'{}'::jsonb) || coalesce(p_payload,'{}'::jsonb),
      updated_at=now()
  where id=p_payment_id;

  if p_status in ('FAILED','CANCELLED') then
    select * into v_order
    from public.orders
    where id=v_payment.order_id
    for update;

    if not found then raise exception 'order_not_found'; end if;

    if v_order.status = 'PENDING_PAYMENT' then
      for v_item in
        select oi.product_id, oi.variant_id, sum(oi.quantity)::integer as qty
        from public.order_items oi
        join public.order_groups og on og.id=oi.order_group_id
        where og.order_id=v_order.id
        group by oi.product_id,oi.variant_id
      loop
        if not public.release_variant_inventory(v_item.product_id,v_item.variant_id,v_item.qty) then
          raise exception 'reserved_inventory_release_failed';
        end if;
      end loop;

      select coupon_id into v_coupon_id
      from public.coupon_usage
      where order_id=v_order.id
      limit 1;

      delete from public.coupon_usage
      where order_id=v_order.id;

      if v_coupon_id is not null then
        update public.coupons
        set used_count=greatest(0,used_count-1)
        where id=v_coupon_id;
      end if;

      update public.order_packages op
      set status='CANCELLED', updated_at=now()
      from public.order_groups og
      where og.id=op.order_group_id
        and og.order_id=v_order.id
        and op.status='CREATED';

      update public.orders
      set status='CANCELLED',updated_at=now()
      where id=v_order.id;

      update public.order_groups
      set status='CANCELLED'
      where order_id=v_order.id
        and status='PENDING_PAYMENT';

      insert into public.order_events(
        order_id,actor_id,status,metadata
      )
      values(
        v_order.id,null,'CANCELLED',
        jsonb_build_object(
          'payment_id',p_payment_id,
          'reason','payment_failed'
        )
      );
    end if;
  end if;

  return true;
end;

$function$;

create or replace function public.process_payment_event(
 p_payment_id uuid,p_event_type text,p_status public.payment_status,p_provider_reference text,
 p_amount numeric,p_payload jsonb default '{}'::jsonb
)
returns boolean language sql security definer set search_path=pg_catalog,public as $function$
select public.process_payment_event(p_payment_id,p_event_type,p_status,p_provider_reference,p_amount,null,coalesce(p_payload,'{}'::jsonb));
$function$;

revoke all on function public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb) from public,anon,authenticated;
grant execute on function public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb) to service_role;
revoke all on function public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb) from public,anon,authenticated;
grant execute on function public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb) to service_role;



create or replace function public.complete_refund(p_refund_id uuid,p_provider_reference text)
returns boolean language plpgsql security definer set search_path=pg_catalog,public as $function$
declare v_refund public.refunds%rowtype; v_payment public.payments%rowtype; v_order public.orders%rowtype; v_total_refunded numeric:=0;
begin
  select * into v_refund from public.refunds where id=p_refund_id for update;
  if not found then raise exception 'refund_not_found'; end if;
  if v_refund.status='COMPLETED' then return true; end if;
  if nullif(trim(p_provider_reference),'') is null then raise exception 'provider_reference_required'; end if;
  select * into v_payment from public.payments where id=v_refund.payment_id for update;
  if not found then raise exception 'payment_not_found'; end if;
  select * into v_order from public.orders where id=v_refund.order_id for update;
  if not found then raise exception 'order_not_found'; end if;

  perform s.id
  from public.sellers s join public.shops sh on sh.seller_id=s.id
  join public.order_groups og on og.shop_id=sh.id
  where og.order_id=v_refund.order_id
  order by s.id for update of s;

  update public.refunds set status='COMPLETED',provider_reference=trim(p_provider_reference),completed_at=now()
  where id=p_refund_id;

  select coalesce(sum(r.amount),0) into v_total_refunded
  from public.refunds r where r.payment_id=v_refund.payment_id and r.status='COMPLETED';

  if v_total_refunded>=v_payment.amount then
    update public.payments set status='REFUNDED',updated_at=now() where id=v_payment.id;
  else
    update public.payments set status='PARTIALLY_REFUNDED',updated_at=now()
    where id=v_payment.id and status in ('SUCCEEDED','PARTIALLY_REFUNDED');
  end if;

  -- Refund trigger keeps all sellers in the order on hold. Do not prorate
  -- debits across unrelated sellers before line/quantity allocations are approved.
  return true;
end;
$function$;
revoke all on function public.complete_refund(uuid,text) from public,anon,authenticated;
grant execute on function public.complete_refund(uuid,text) to service_role;


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
declare
  v_payment_id uuid;
begin
  if not private.is_admin() then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;

  if p_refund_id is null then
    raise exception 'refund_id_required';
  end if;

  -- Lock in a stable order: the refund row, then its payment row. This
  -- serializes separate refund requests for the same payment so concurrent
  -- requests cannot both pass the reconciliation preflight.
  select r.payment_id into v_payment_id
  from public.refunds r
  where r.id=p_refund_id
  for update;

  if not found or v_payment_id is null then
    raise exception 'refund_not_found';
  end if;

  select p.id into v_payment_id
  from public.payments p
  where p.id=v_payment_id
  for update;

  if not found then
    raise exception 'payment_not_found';
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

  -- Do not start another provider refund when a prior refund on this payment
  -- still needs item/seller allocation and ledger reconciliation.
  if exists (
    select 1
    from private.refund_accounting_reconciliations ar
    join public.refunds prior on prior.id=ar.refund_id
    where ar.payment_id=(select r0.payment_id from public.refunds r0 where r0.id=p_refund_id)
      and ar.refund_id<>p_refund_id
      and ar.status='PENDING_ALLOCATION'
      and prior.status in ('PENDING','PROCESSING','COMPLETED','FAILED')
  ) then
    raise exception 'refund_financial_reconciliation_required';
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
revoke all on function public.admin_begin_refund(uuid) from public,anon;
grant execute on function public.admin_begin_refund(uuid) to authenticated;

create or replace function public.request_seller_payout_secure(
  p_seller_id uuid,
  p_amount numeric,
  p_provider text
)
returns uuid
language plpgsql
security definer
set search_path to 'pg_catalog', 'public'
as $function$
declare
  v_user uuid := auth.uid();
  v_balance numeric;
  v_payout uuid;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select s.id
    into v_payout
  from public.sellers s
  where s.id = p_seller_id
    and s.user_id = v_user
    and s.verification_status = 'VERIFIED'::public.verification_status
  for update;

  if v_payout is null then
    raise exception 'seller_not_eligible';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'amount_invalid';
  end if;

  if p_provider is null
     or upper(trim(p_provider)) not in ('ORANGE_MONEY','WAVE','MOOV_MONEY') then
    raise exception 'provider_invalid';
  end if;

  if exists (
    select 1
    from private.refund_accounting_reconciliations ar
    join public.order_groups og on og.order_id=ar.order_id
    join public.shops sh on sh.id=og.shop_id
    where sh.seller_id=p_seller_id and ar.status='PENDING_ALLOCATION'
  ) then
    raise exception 'seller_payout_blocked_by_refund_reconciliation';
  end if;

  select coalesce(sum(amount), 0)
    into v_balance
  from public.seller_ledger
  where seller_id = p_seller_id;

  if p_amount > v_balance then
    raise exception 'insufficient_seller_balance';
  end if;

  insert into public.seller_payouts(
    seller_id, amount, currency, provider, status
  )
  values(
    p_seller_id,
    p_amount,
    'XOF',
    upper(trim(p_provider)),
    'PENDING'
  )
  returning id into v_payout;

  insert into public.seller_ledger(
    seller_id, entry_type, amount, currency, reference_id
  )
  values(
    p_seller_id,
    'PAYOUT',
    -p_amount,
    'XOF',
    v_payout
  );

  return v_payout;
end;
$function$;
revoke all on function public.request_seller_payout_secure(uuid,numeric,text) from public,anon;
grant execute on function public.request_seller_payout_secure(uuid,numeric,text) to authenticated;


drop function if exists public.get_admin_refunds();
create function public.get_admin_refunds()
returns table (
 refund_id uuid,order_id uuid,payment_id uuid,customer_id uuid,customer_name text,
 amount numeric,currency text,reason text,refund_status text,provider text,
 provider_reference text,created_at timestamptz,completed_at timestamptz,
 accounting_status text,accounting_note text
)
language sql security definer set search_path=pg_catalog,public as $function$
select r.id,r.order_id,r.payment_id,o.customer_id,coalesce(pr.display_name,'Client'),
 r.amount,r.currency,r.reason,r.status,p.provider,p.provider_reference,r.created_at,r.completed_at,
 ar.status,ar.note
from public.refunds r
join public.orders o on o.id=r.order_id
join public.payments p on p.id=r.payment_id
left join public.profiles pr on pr.id=o.customer_id
left join private.refund_accounting_reconciliations ar on ar.refund_id=r.id
where private.is_admin()
order by r.created_at desc limit 200;
$function$;
revoke all on function public.get_admin_refunds() from public,anon;
grant execute on function public.get_admin_refunds() to authenticated;

