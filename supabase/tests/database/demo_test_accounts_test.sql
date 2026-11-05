begin;
select plan(13);

select is(
  (select count(*)::integer from auth.users where email like 'demo.%@marketplace.test'),
  9,
  'nine local demo auth users are seeded'
);

select is(
  (select count(*)::integer from auth.users where raw_app_meta_data->>'is_test_account'='true' and raw_app_meta_data->>'environment'='local'),
  9,
  'every demo user is marked as local test data in protected app metadata'
);

select ok(
  exists (
    select 1 from public.user_roles ur
    join auth.users u on u.id=ur.user_id
    where u.email='demo.admin@marketplace.test' and ur.role='SUPER_ADMIN'::public.user_role
  ),
  'the local demo admin role is seeded'
);

select ok(
  exists (
    select 1 from public.admin_users au
    join auth.users u on u.id=au.user_id
    where u.email='demo.admin@marketplace.test' and au.active=true
  ),
  'the local demo admin registry row is seeded'
);

select ok(
  exists (
    select 1 from public.sellers s
    join auth.users u on u.id=s.user_id
    where u.email='demo.seller@marketplace.test'
  ),
  'the demo seller profile is seeded'
);

select is(
  (select count(*)::integer from public.profiles where id in (select id from auth.users where email like 'demo.%@marketplace.test')),
  9,
  'all demo auth users receive profile rows through the auth trigger'
);

select ok(
  exists (
    select 1 from public.shops sh
    join public.sellers s on s.id=sh.seller_id
    join auth.users u on u.id=s.user_id
    where u.email='demo.seller@marketplace.test' and sh.normalized_name='boutique démo locale'
  ),
  'the demo seller has a local draft shop'
);

select ok(
  exists (
    select 1 from public.restaurant_profiles rp
    join public.shops sh on sh.id=rp.shop_id
    join public.sellers s on s.id=sh.seller_id
    join auth.users u on u.id=s.user_id
    where u.email='demo.restaurant@marketplace.test' and sh.normalized_name='restaurant démo'
  ),
  'the demo restaurant has a restaurant profile and draft shop'
);


select ok(
  exists (
    select 1 from public.mechanics m
    join auth.users u on u.id=m.user_id
    where u.email='demo.mechanic@marketplace.test'
  ),
  'the demo mechanic profile is seeded'
);

select ok(
  exists (
    select 1 from public.transport_companies tc
    join auth.users u on u.id=tc.owner_user_id
    where u.email='demo.transport@marketplace.test'
  ),
  'the demo transport company is seeded'
);


select is(
  (with expected(email, role) as (
    values
      ('demo.customer@marketplace.test','CUSTOMER'::public.user_role),
      ('demo.seller@marketplace.test','SELLER'::public.user_role),
      ('demo.courier@marketplace.test','COURIER'::public.user_role),
      ('demo.restaurant@marketplace.test','RESTAURANT'::public.user_role),
      ('demo.mechanic@marketplace.test','MECHANIC'::public.user_role),
      ('demo.transport@marketplace.test','TRANSPORT_COMPANY'::public.user_role),
      ('demo.support@marketplace.test','SUPPORT'::public.user_role),
      ('demo.moderator@marketplace.test','MODERATOR'::public.user_role),
      ('demo.admin@marketplace.test','SUPER_ADMIN'::public.user_role)
  )
  select count(*)::integer
  from expected e
  join auth.users u on u.email=e.email
  join public.user_roles ur on ur.user_id=u.id and ur.role=e.role
  ),
  9,
  'every demo account has its intended role; default CUSTOMER roles may coexist'
);

select ok(
  exists (
    select 1 from public.restaurant_menus rm
    join public.restaurant_profiles rp on rp.id=rm.restaurant_id
    join public.shops sh on sh.id=rp.shop_id
    where sh.normalized_name='restaurant démo'
      and rm.name='Menu de démonstration'
  ),
  'the demo restaurant has a local sample menu'
);

select ok(
  exists (
    select 1 from public.service_providers sp
    join auth.users u on u.id=sp.user_id
    where u.email='demo.mechanic@marketplace.test'
      and sp.provider_type='MECHANIC'
  ),
  'the demo mechanic is registered in the service provider directory'
);

select * from finish();
rollback;
