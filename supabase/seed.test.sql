-- LOCAL DEVELOPMENT ONLY. Never execute against hosted Supabase.
-- Demo password for every account: DemoOnly-2026!
-- No real personal, payment, or merchant data is included.

begin;
set local search_path = public, extensions, auth;

with demo_users(id,email,display_name,role_name) as (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid,'demo.customer@marketplace.test','Client Démo','CUSTOMER'),
    ('10000000-0000-4000-8000-000000000002'::uuid,'demo.seller@marketplace.test','Vendeur Démo','SELLER'),
    ('10000000-0000-4000-8000-000000000003'::uuid,'demo.courier@marketplace.test','Livreur Démo','COURIER'),
    ('10000000-0000-4000-8000-000000000004'::uuid,'demo.restaurant@marketplace.test','Restaurant Démo','RESTAURANT'),
    ('10000000-0000-4000-8000-000000000005'::uuid,'demo.mechanic@marketplace.test','Mécanicien Démo','MECHANIC'),
    ('10000000-0000-4000-8000-000000000006'::uuid,'demo.transport@marketplace.test','Transport Démo','TRANSPORT_COMPANY'),
    ('10000000-0000-4000-8000-000000000007'::uuid,'demo.support@marketplace.test','Support Démo','SUPPORT'),
    ('10000000-0000-4000-8000-000000000008'::uuid,'demo.moderator@marketplace.test','Modérateur Démo','MODERATOR'),
    ('10000000-0000-4000-8000-000000000009'::uuid,'demo.admin@marketplace.test','Administrateur Démo','SUPER_ADMIN')
)
insert into auth.users (
  id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous
)
select id, 'authenticated', 'authenticated', email,
  crypt('DemoOnly-2026!', gen_salt('bf')), now(),
  jsonb_build_object('provider','email','providers',jsonb_build_array('email'),'is_test_account',true,'environment','local'),
  jsonb_build_object('display_name',display_name,'test_account',true),
  now(), now(), false, false
from demo_users
on conflict (id) do nothing;

with demo_users(id,email) as (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid,'demo.customer@marketplace.test'),
    ('10000000-0000-4000-8000-000000000002'::uuid,'demo.seller@marketplace.test'),
    ('10000000-0000-4000-8000-000000000003'::uuid,'demo.courier@marketplace.test'),
    ('10000000-0000-4000-8000-000000000004'::uuid,'demo.restaurant@marketplace.test'),
    ('10000000-0000-4000-8000-000000000005'::uuid,'demo.mechanic@marketplace.test'),
    ('10000000-0000-4000-8000-000000000006'::uuid,'demo.transport@marketplace.test'),
    ('10000000-0000-4000-8000-000000000007'::uuid,'demo.support@marketplace.test'),
    ('10000000-0000-4000-8000-000000000008'::uuid,'demo.moderator@marketplace.test'),
    ('10000000-0000-4000-8000-000000000009'::uuid,'demo.admin@marketplace.test')
)
insert into auth.identities(provider_id,user_id,identity_data,provider,email)
select id::text,id,jsonb_build_object('sub',id::text,'email',email,'email_verified',true),'email',email
from demo_users
where exists (select 1 from auth.users u where u.id=demo_users.id)
and not exists (select 1 from auth.identities i where i.user_id=demo_users.id and i.provider='email');

with demo_users(id,role_name) as (
  values
    ('10000000-0000-4000-8000-000000000001'::uuid,'CUSTOMER'),
    ('10000000-0000-4000-8000-000000000002'::uuid,'SELLER'),
    ('10000000-0000-4000-8000-000000000003'::uuid,'COURIER'),
    ('10000000-0000-4000-8000-000000000004'::uuid,'RESTAURANT'),
    ('10000000-0000-4000-8000-000000000005'::uuid,'MECHANIC'),
    ('10000000-0000-4000-8000-000000000006'::uuid,'TRANSPORT_COMPANY'),
    ('10000000-0000-4000-8000-000000000007'::uuid,'SUPPORT'),
    ('10000000-0000-4000-8000-000000000008'::uuid,'MODERATOR'),
    ('10000000-0000-4000-8000-000000000009'::uuid,'SUPER_ADMIN')
)
insert into public.user_roles(user_id,role)
select id, role_name::public.user_role from demo_users
on conflict (user_id,role) do nothing;

insert into public.sellers(user_id,business_name,verification_status)
values ('10000000-0000-4000-8000-000000000002','Boutique Démo Locale','PENDING'::public.verification_status)
on conflict do nothing;

insert into public.sellers(user_id,business_name,verification_status)
values ('10000000-0000-4000-8000-000000000004','Restaurant Démo','PENDING'::public.verification_status)
on conflict (user_id) do nothing;

insert into public.shops(seller_id,name,normalized_name,description,status,verification_status)
select id,'Boutique Démo Locale','boutique-demo-locale','Boutique de démonstration locale','DRAFT'::public.shop_status,'PENDING'::public.verification_status
from public.sellers where user_id='10000000-0000-4000-8000-000000000002'
on conflict (normalized_name) do nothing;

insert into public.shops(seller_id,name,normalized_name,description,status,verification_status)
select id,'Restaurant Démo','restaurant-demo','Restaurant de démonstration locale','DRAFT'::public.shop_status,'PENDING'::public.verification_status
from public.sellers where user_id='10000000-0000-4000-8000-000000000004'
on conflict (normalized_name) do nothing;

insert into public.restaurant_profiles(shop_id,cuisine_types,preparation_time_min,delivery_available)
select id,array['LOCAL']::text[],25,true
from public.shops where normalized_name='restaurant-demo'
on conflict (shop_id) do nothing;

insert into public.restaurant_menus(restaurant_id,name,description)
select rp.id,'Menu de démonstration','Menu fictif réservé aux tests locaux'
from public.restaurant_profiles rp
join public.shops sh on sh.id=rp.shop_id
where sh.normalized_name='restaurant-demo'
and not exists(select 1 from public.restaurant_menus rm where rm.restaurant_id=rp.id and rm.name='Menu de démonstration');


insert into public.mechanics(user_id,display_name,verification_status,active)
values ('10000000-0000-4000-8000-000000000005','Mécanicien Démo','PENDING'::public.verification_status,true)
on conflict do nothing;

insert into public.service_providers(user_id,provider_type,display_name,description,verification_status,active)
values ('10000000-0000-4000-8000-000000000005','MECHANIC','Mécanicien Démo','Profil de démonstration local','PENDING'::public.verification_status,true)
on conflict do nothing;

insert into public.transport_companies(owner_user_id,name,verification_status,active)
values ('10000000-0000-4000-8000-000000000006','Transport Démo','PENDING'::public.verification_status,true)
on conflict do nothing;

insert into public.admin_roles(name,description)
select 'LOCAL_TEST_ADMIN','Rôle administrateur de démonstration — base locale uniquement'
where not exists (select 1 from public.admin_roles where name='LOCAL_TEST_ADMIN');

insert into public.admin_users(user_id,admin_role_id,active)
select '10000000-0000-4000-8000-000000000009',id,true
from public.admin_roles
where name='LOCAL_TEST_ADMIN'
on conflict (user_id) do nothing;

commit;
