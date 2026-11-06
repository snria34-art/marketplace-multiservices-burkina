-- Preserve admin cancellation access for unpaid orders after the global
-- transition was restricted to the unpaid-only cancellation workflow.
-- Admins may cancel any PENDING_PAYMENT order, but never a settled/dispatched one.

create or replace function public.cancel_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_is_admin boolean := false;
  v_order public.orders%rowtype;
  v_item record;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  v_is_admin := private.is_admin();

  select *
  into v_order
  from public.orders
  where id = p_order_id
    and (customer_id = v_user or v_is_admin)
  for update;

  if not found then
    raise exception 'order_not_found_or_not_authorized';
  end if;

  if v_order.status <> 'PENDING_PAYMENT' then
    raise exception 'order_not_cancellable';
  end if;

  if exists (
    select 1
    from public.payments p
    where p.order_id = p_order_id
      and p.status in ('SUCCEEDED','PARTIALLY_REFUNDED','REFUNDED')
  ) then
    raise exception 'order_payment_already_settled';
  end if;

  if exists (
    select 1
    from public.order_packages op
    join public.order_groups og on og.id = op.order_group_id
    where og.order_id = p_order_id
      and op.status in ('PICKED_UP','IN_TRANSIT','DELIVERED','RETURNED','DAMAGED','LOST')
  ) then
    raise exception 'unpaid_order_has_dispatched_package';
  end if;

  if exists (
    select 1
    from public.delivery_assignments da
    join public.order_packages op on op.id = da.package_id
    join public.order_groups og on og.id = op.order_group_id
    where og.order_id = p_order_id
      and da.status in ('PICKED_UP','IN_TRANSIT','DELIVERED','RETURNED','DAMAGED','LOST')
  ) then
    raise exception 'unpaid_order_has_dispatched_assignment';
  end if;

  if exists (
    select 1
    from public.order_packages op
    join public.order_groups og on og.id = op.order_group_id
    join public.package_inventory_consumptions pic on pic.package_id = op.id
    where og.order_id = p_order_id
  ) then
    raise exception 'unpaid_order_inventory_already_consumed';
  end if;

  for v_item in
    select
      oi.product_id,
      oi.variant_id,
      sum(oi.quantity)::integer as qty
    from public.order_items oi
    join public.order_groups og on og.id = oi.order_group_id
    where og.order_id = p_order_id
    group by oi.product_id, oi.variant_id
  loop
    if not public.release_variant_inventory(
      v_item.product_id,
      v_item.variant_id,
      v_item.qty
    ) then
      raise exception 'reserved_inventory_release_failed';
    end if;
  end loop;

  with cancelled_assignments as (
    update public.delivery_assignments da
    set status = 'CANCELLED'
    where da.package_id in (
      select op.id
      from public.order_packages op
      join public.order_groups og on og.id = op.order_group_id
      where og.order_id = p_order_id
    )
      and da.status in ('CREATED','ASSIGNED','ACCEPTED','READY_FOR_PICKUP')
    returning da.id
  )
  insert into public.delivery_assignment_events(
    assignment_id,
    actor_id,
    event_type,
    metadata
  )
  select
    id,
    v_user,
    'CANCELLED_BY_ORDER',
    jsonb_build_object(
      'order_id', p_order_id,
      'reason', 'unpaid_order_cancelled',
      'actor_type', case when v_is_admin then 'ADMIN' else 'CUSTOMER' end
    )
  from cancelled_assignments;

  update public.order_packages op
  set status = 'CANCELLED',
      updated_at = now()
  from public.order_groups og
  where og.id = op.order_group_id
    and og.order_id = p_order_id
    and op.status <> 'CANCELLED';

  update public.order_groups
  set status = 'CANCELLED'
  where order_id = p_order_id
    and status <> 'CANCELLED';

  with released_coupon_usage as (
    delete from public.coupon_usage
    where order_id = p_order_id
    returning coupon_id
  ),
  released_coupon_counts as (
    select coupon_id, count(*)::integer as usage_count
    from released_coupon_usage
    group by coupon_id
  )
  update public.coupons c
  set used_count = greatest(0, c.used_count - rc.usage_count)
  from released_coupon_counts rc
  where c.id = rc.coupon_id;

  update public.orders
  set status = 'CANCELLED',
      updated_at = now()
  where id = p_order_id;

  insert into public.order_events(
    order_id,
    actor_id,
    status,
    metadata
  )
  values (
    p_order_id,
    v_user,
    'CANCELLED',
    jsonb_build_object(
      'source', 'cancel_unpaid_order',
      'reason', 'cancelled_before_payment',
      'actor_type', case when v_is_admin then 'ADMIN' else 'CUSTOMER' end
    )
  );

  return true;
end;
$function$;

revoke all on function public.cancel_unpaid_order(uuid) from public, anon;
grant execute on function public.cancel_unpaid_order(uuid) to authenticated, service_role;
