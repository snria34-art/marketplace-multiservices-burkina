begin;

do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef(
    'public.transition_order_status(uuid,public.order_status,text)'::regprocedure
  );

  v_old := $old$
  if p_next_status = 'CANCELLED' then
    v_allowed := (
      (v_is_customer and v_order.status in ('PENDING_PAYMENT','PAID'))
      or v_is_admin
    );
  elsif p_next_status = 'DISPUTED' then
$old$;

  if position(v_old in v_def) = 0 then
    raise exception 'AUD03_transition_cancel_branch_not_found';
  end if;

  v_new := $new$
  if p_next_status = 'CANCELLED' then
    return public.cancel_unpaid_order(p_order_id);
  elsif p_next_status = 'DISPUTED' then
$new$;

  v_def := replace(v_def, v_old, v_new);

  v_old := $old$
  if p_next_status = 'CANCELLED'
     and v_order.status in ('PENDING_PAYMENT','PAID','CONFIRMED','PREPARING') then
    for v_item in
      select oi.product_id, oi.variant_id, oi.quantity
      from public.order_items oi
      join public.order_groups og on og.id = oi.order_group_id
      where og.order_id = p_order_id
    loop
      if not public.release_variant_inventory(v_item.product_id, v_item.variant_id, v_item.quantity) then raise exception 'reserved_inventory_release_failed'; end if;
    end loop;
  end if;
$old$;

  if position(v_old in v_def) = 0 then
    raise exception 'AUD03_transition_unsafe_stock_release_block_not_found';
  end if;
  v_def := replace(v_def, v_old, '');

  v_old := $old$
  if p_next_status = 'CANCELLED' then
    update public.order_groups
    set status = 'CANCELLED'
    where order_id = p_order_id
      and status not in ('DELIVERED','CANCELLED');
  end if;
$old$;

  if position(v_old in v_def) = 0 then
    raise exception 'AUD03_transition_unsafe_group_cancel_block_not_found';
  end if;
  v_def := replace(v_def, v_old, '');

  v_def := replace(v_def, '  v_item record;' || chr(10), '');

  if position('return public.cancel_unpaid_order(p_order_id);' in v_def) = 0
     or position('release_variant_inventory' in v_def) > 0
     or position('set status = ''CANCELLED''' in v_def) > 0 then
    raise exception 'AUD03_transition_global_cancel_guard_verification_failed';
  end if;

  execute v_def;
end;
$migration$;

create or replace function public.cancel_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_order public.orders%rowtype;
  v_item record;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into v_order
  from public.orders
  where id = p_order_id
    and customer_id = v_user
  for update;

  if not found then
    raise exception 'order_not_found';
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
      'reason', 'customer_cancelled_unpaid_order'
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
      'reason', 'customer_cancelled_before_payment'
    )
  );

  return true;
end;
$function$;

revoke all on function public.cancel_unpaid_order(uuid) from public, anon;
grant execute on function public.cancel_unpaid_order(uuid) to authenticated, service_role;

revoke all on function public.transition_order_status(uuid,public.order_status,text) from public, anon;
grant execute on function public.transition_order_status(uuid,public.order_status,text) to authenticated, service_role;

commit;
