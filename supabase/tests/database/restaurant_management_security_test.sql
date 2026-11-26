begin;
select plan(9);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='restaurant_profiles'
      and column_name='accepting_orders'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='restaurant_profiles'
      and column_name='delivery_available'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='restaurant_profiles'
      and column_name='minimum_order_amount'
  )
  and exists (
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='restaurant_profiles'
      and column_name='opening_hours'
  ),
  'restaurant profile exposes order acceptance, delivery, minimum basket and opening hours'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='restaurant_profiles'
      and policyname='restaurant_profiles_owner_manage'
      and cmd='ALL'
  )
  and exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='restaurant_menus'
      and policyname='restaurant_menus_owner_manage'
      and cmd='ALL'
  )
  and exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='restaurant_menu_items'
      and policyname='restaurant_menu_items_owner_manage'
      and cmd='ALL'
  ),
  'restaurant owners can manage only their own profiles, menus and dishes'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='restaurant_menus'
      and policyname='restaurant_public_menu'
      and cmd='SELECT'
  )
  and exists (
    select 1 from pg_policies
    where schemaname='public'
      and tablename='restaurant_menu_items'
      and policyname='restaurant_public_items'
      and cmd='SELECT'
  ),
  'public restaurant discovery remains read-only and active-item scoped'
);

select ok(
  (
    select prosecdef
    from pg_proc
    where oid='public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )
  and has_function_privilege(
    'authenticated',
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)',
    'EXECUTE'
  ),
  'restaurant order progression is a signed-in SECURITY DEFINER RPC, never anonymous'
);

select ok(
  position('restaurant_order_not_owned' in pg_get_functiondef(
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )) > 0
  and position('restaurant_role_required' in pg_get_functiondef(
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )) > 0,
  'restaurant order progression checks both business ownership and restaurant/seller role'
);

select ok(
  position('CONFIRMED' in pg_get_functiondef(
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )) > 0
  and position('PREPARING' in pg_get_functiondef(
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )) > 0
  and position('READY_FOR_PICKUP' in pg_get_functiondef(
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )) > 0
  and position('CANCELLED' in pg_get_functiondef(
    'public.restaurant_transition_order_group_status(uuid,public.order_status,text)'::regprocedure
  )) = 0,
  'restaurant RPC permits forward preparation states only and cannot cancel paid orders'
);

select ok(
  exists (
    select 1 from pg_trigger
    where tgname='restaurant_order_group_rules'
      and tgrelid='public.order_groups'::regclass
      and tgconstraint <> 0
      and tgdeferrable
      and tginitdeferred
  )
  and position('restaurant_not_accepting_orders' in pg_get_functiondef(
    'public.enforce_restaurant_order_group_rules()'::regprocedure
  )) > 0
  and position('restaurant_delivery_unavailable' in pg_get_functiondef(
    'public.enforce_restaurant_order_group_rules()'::regprocedure
  )) > 0,
  'checkout enforces restaurant order acceptance and delivery availability server-side'
);

select ok(
  position('restaurant_minimum_order_not_reached' in pg_get_functiondef(
    'public.enforce_restaurant_order_group_rules()'::regprocedure
  )) > 0,
  'checkout enforces restaurant minimum basket after all order lines are inserted'
);

select ok(
  not has_function_privilege(
    'authenticated',
    'public.enforce_restaurant_order_group_rules()',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.enforce_restaurant_order_group_rules()',
    'EXECUTE'
  ),
  'restaurant checkout trigger helper cannot be executed directly by API clients'
);

select * from finish();
rollback;
