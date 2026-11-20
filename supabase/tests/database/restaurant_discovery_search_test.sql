begin;
select plan(10);

select ok(
  exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='restaurant_profiles'
      and column_name='restaurant_type'
  ),
  'restaurant profile stores a normalized restaurant format'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid='public.restaurant_profiles'::regclass
      and conname='restaurant_profiles_restaurant_type_check'
  ),
  'restaurant format is constrained to supported values'
);

select ok(
  exists (
    select 1 from pg_indexes
    where schemaname='public' and indexname='idx_restaurant_profiles_cuisines'
      and indexdef ilike '%USING gin%'
  ),
  'cuisine filters have a GIN index'
);

select ok(
  to_regprocedure('public.search_restaurant_catalog(text,text,text,integer)') is not null,
  'restaurant and dish discovery RPC exists'
);

select ok(
  has_function_privilege('anon','public.search_restaurant_catalog(text,text,text,integer)','EXECUTE')
  and has_function_privilege('authenticated','public.search_restaurant_catalog(text,text,text,integer)','EXECUTE'),
  'restaurant search is available to guests and signed-in customers'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='restaurant_profiles'
      and policyname='restaurant_seller_discovery_profile_update'
      and cmd='UPDATE' and 'authenticated' = any(roles::text[])
  ),
  'restaurant sellers have an owner-scoped update policy'
);

select ok(
  has_function_privilege('authenticated','public.save_restaurant_discovery_profile(uuid,text,text[])','EXECUTE')
  and not has_function_privilege('anon','public.save_restaurant_discovery_profile(uuid,text,text[])','EXECUTE'),
  'only authenticated users can request restaurant category changes'
);

select ok(
  position('p.status = ''ACTIVE''' in pg_get_functiondef(
    'public.search_restaurant_catalog(text,text,text,integer)'::regprocedure
  )) > 0
  and position('p.shop_id = rp.shop_id' in pg_get_functiondef(
    'public.search_restaurant_catalog(text,text,text,integer)'::regprocedure
  )) > 0,
  'search only exposes active products belonging to the restaurant shop'
);

select ok(
  position('restaurant_menu_item_options' in pg_get_functiondef(
    'public.search_restaurant_catalog(text,text,text,integer)'::regprocedure
  )) > 0
  and position('option_groups' in pg_get_functiondef(
    'public.search_restaurant_catalog(text,text,text,integer)'::regprocedure
  )) > 0,
  'search results include available dish customizations'
);

select ok(
  public.restaurant_search_normalize('Attiéké') = 'attieke',
  'search normalization ignores common French accents'
);

select * from finish();
rollback;
