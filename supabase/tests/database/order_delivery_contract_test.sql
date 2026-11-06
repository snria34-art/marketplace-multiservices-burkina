begin;
select plan(12);

select ok(
  has_function_privilege('authenticated', 'public.cancel_unpaid_order(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.cancel_unpaid_order(uuid)', 'EXECUTE')
  and (
    select prosecdef
    from pg_proc
    where oid = 'public.cancel_unpaid_order(uuid)'::regprocedure
  ),
  'unpaid order cancellation is a SECURITY DEFINER RPC available only to authenticated clients'
);

select ok(
  position('v_order.status <> ''PENDING_PAYMENT''' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('order_payment_already_settled' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('unpaid_order_has_dispatched_package' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('unpaid_order_inventory_already_consumed' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0,
  'unpaid order cancellation refuses paid, dispatched, or inventory-consumed orders'
);

select ok(
  position('release_variant_inventory' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('public.delivery_assignments' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('public.order_packages' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('public.order_groups' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('public.coupon_usage' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('public.order_events' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0,
  'unpaid order cancellation releases reserved inventory/coupon usage and synchronizes packages, assignments, groups, order events'
);

select ok(
  position('return public.cancel_unpaid_order(p_order_id)' in pg_get_functiondef('public.transition_order_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('v_allowed := v_is_admin' in pg_get_functiondef('public.transition_order_status(uuid,public.order_status,text)'::regprocedure)) > 0,
  'global order cancellation delegates to the restricted unpaid-order handler'
);

select ok(
  position('v_shop_owner=v_user' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('group_cancellation_after_dispatch_not_allowed' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('group_inventory_already_consumed' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0,
  'seller order-group transitions require ownership and refuse cancellation after dispatch or inventory consumption'
);

select ok(
  position('CANCELLED_BY_SELLER' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('v_parent_status := ''PARTIALLY_FULFILLED''' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('v_parent_status := ''CANCELLED''' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0,
  'seller group cancellation records assignment events and synchronizes the parent order status'
);

select ok(
  has_function_privilege('authenticated', 'public.checkout_cart(uuid,jsonb,numeric,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.checkout_cart(uuid,jsonb,numeric,text,text)', 'EXECUTE')
  and position('idempotency_key_required' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('cart_not_active_or_not_owned' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0,
  'checkout is authenticated, idempotent, and requires a cart owned by the caller'
);

select ok(
  position('delivery_address_not_owned' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('public.calculate_delivery_fee' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('public.reserve_variant_inventory' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('product_expired' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0,
  'checkout uses a customer-owned delivery address, server-calculated delivery fees, expiry checks and stock reservation'
);

select ok(
  position('private.has_role(''COURIER''::public.user_role)' in pg_get_functiondef('public.accept_delivery_assignment(uuid)'::regprocedure)) > 0
  and position('courier_id=(select auth.uid())' in pg_get_functiondef('public.accept_delivery_assignment(uuid)'::regprocedure)) > 0
  and position('status=''ASSIGNED''' in pg_get_functiondef('public.accept_delivery_assignment(uuid)'::regprocedure)) > 0,
  'a courier can accept only an assignment currently assigned to that same courier'
);

select ok(
  position('pickup_photo_required' in pg_get_functiondef('public.confirm_package_pickup(uuid,text)'::regprocedure)) > 0
  and position('pickup_code_hash' in pg_get_functiondef('public.confirm_package_pickup(uuid,text)'::regprocedure)) > 0
  and position('consume_package_inventory' in pg_get_functiondef('public.confirm_package_pickup(uuid,text)'::regprocedure)) > 0
  and position('status=''ACCEPTED''' in pg_get_functiondef('public.confirm_package_pickup(uuid,text)'::regprocedure)) > 0,
  'pickup requires the assigned courier, pickup proof, hashed pickup code and inventory consumption'
);

select ok(
  position('package_not_in_courier_possession' in pg_get_functiondef('public.start_package_delivery(uuid)'::regprocedure)) > 0
  and position('status=''PICKED_UP''' in pg_get_functiondef('public.start_package_delivery(uuid)'::regprocedure)) > 0
  and position('courier_id=v_user' in pg_get_functiondef('public.start_package_delivery(uuid)'::regprocedure)) > 0,
  'delivery can start only for a package picked up by the authenticated courier'
);

select ok(
  position('delivery_photo_required' in pg_get_functiondef('public.confirm_package_delivery(uuid,text)'::regprocedure)) > 0
  and position('delivery_code_hash' in pg_get_functiondef('public.confirm_package_delivery(uuid,text)'::regprocedure)) > 0
  and position('sync_after_package_delivery' in pg_get_functiondef('public.confirm_package_delivery(uuid,text)'::regprocedure)) > 0
  and not has_function_privilege('anon', 'public.confirm_package_delivery(uuid,text)', 'EXECUTE'),
  'delivery confirmation requires delivery evidence, the hashed customer code and downstream order synchronization'
);

select ok(
  has_function_privilege('service_role', 'public.complete_refund(uuid,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.complete_refund(uuid,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.complete_refund(uuid,text)', 'EXECUTE')
  and position('if v_refund.status=''COMPLETED'' then' in pg_get_functiondef('public.complete_refund(uuid,text)'::regprocedure)) > 0
  and position('for update' in pg_get_functiondef('public.complete_refund(uuid,text)'::regprocedure)) > 0,
  'refund completion remains service-role-only, idempotent and row-locked'
);

select * from finish();
rollback;
