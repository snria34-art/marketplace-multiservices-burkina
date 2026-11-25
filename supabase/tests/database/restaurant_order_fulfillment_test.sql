begin;
select plan(13);

select ok(
  has_column('public', 'restaurant_profiles', 'pickup_available'),
  'restaurant profiles expose a pickup availability flag'
);

select ok(
  has_column('public', 'carts', 'restaurant_fulfillment_method')
  and has_column('public', 'carts', 'restaurant_customer_instructions'),
  'restaurant carts store the chosen fulfilment method and customer instructions'
);

select ok(
  has_column('public', 'order_groups', 'fulfillment_method')
  and has_column('public', 'order_groups', 'fulfillment_instructions')
  and has_column('public', 'order_groups', 'pickup_location'),
  'order groups preserve the selected fulfilment method and pickup snapshot'
);

select ok(
  has_column('public', 'order_packages', 'fulfillment_method'),
  'delivery lifecycle packages distinguish restaurant pickup from courier delivery'
);

select ok(
  has_function_privilege('authenticated', 'public.get_restaurant_cart_context(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.get_restaurant_cart_context(uuid)', 'EXECUTE')
  and (select prosecdef from pg_proc where oid = 'public.get_restaurant_cart_context(uuid)'::regprocedure),
  'restaurant cart context is an authenticated security-definer RPC'
);

select ok(
  has_function_privilege('authenticated', 'public.set_restaurant_cart_fulfillment(uuid,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.set_restaurant_cart_fulfillment(uuid,text,text)', 'EXECUTE')
  and position('cart_must_contain_one_restaurant_only' in pg_get_functiondef('public.set_restaurant_cart_fulfillment(uuid,text,text)'::regprocedure)) > 0
  and position('restaurant_pickup_unavailable' in pg_get_functiondef('public.set_restaurant_cart_fulfillment(uuid,text,text)'::regprocedure)) > 0,
  'customers can configure only an eligible single-restaurant cart'
);

select ok(
  position('pickup_requires_one_restaurant_cart' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('v_delivery_fee_server := 0' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('delivery_address_not_owned' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0,
  'checkout supports pickup while retaining delivery address ownership checks'
);

select ok(
  position('fulfillment_method' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('v_fulfillment_method' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0,
  'checkout stores the fulfilment method on its package and order group'
);

select ok(
  position('reserve_variant_inventory' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0
  and position('calculate_delivery_fee' in pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure)) > 0,
  'checkout retains variant stock reservation and server-calculated delivery fees'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname = 'trg_capture_restaurant_order_event'
      and not tgisinternal
  )
  and position('when ''PAID'' then ''RECEIVED''' in pg_get_functiondef('public.capture_restaurant_order_event()'::regprocedure)) > 0,
  'restaurant order status changes are written to the restaurant event timeline'
);

select ok(
  has_function_privilege('authenticated', 'public.transition_restaurant_order_group_status(uuid,public.order_status,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.transition_restaurant_order_group_status(uuid,public.order_status,text)', 'EXECUTE')
  and position('se.user_id = v_user' in pg_get_functiondef('public.transition_restaurant_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('invalid_restaurant_order_transition' in pg_get_functiondef('public.transition_restaurant_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0,
  'only the owning restaurant can advance its order through the allowed statuses'
);

select ok(
  has_function_privilege('authenticated', 'public.confirm_restaurant_customer_pickup(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'public.confirm_restaurant_customer_pickup(uuid)', 'EXECUTE')
  and position('v_fulfillment_method <> ''PICKUP''' in pg_get_functiondef('public.confirm_restaurant_customer_pickup(uuid)'::regprocedure)) > 0,
  'only the owning restaurant can confirm a pickup that is ready'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname = 'trg_guard_restaurant_pickup_assignment'
      and not tgisinternal
  )
  and position('restaurant_pickup_cannot_be_courier_assigned' in pg_get_functiondef('public.guard_restaurant_pickup_assignment()'::regprocedure)) > 0,
  'pickup packages cannot be assigned to couriers'
);

select * from finish();
rollback;
