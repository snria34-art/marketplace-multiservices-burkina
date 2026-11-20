-- Restaurant discovery taxonomy and server-side search.
alter table public.restaurant_profiles
  add column if not exists restaurant_type text not null default 'OTHER';

alter table public.restaurant_profiles
  drop constraint if exists restaurant_profiles_restaurant_type_check;
alter table public.restaurant_profiles
  add constraint restaurant_profiles_restaurant_type_check
  check (restaurant_type in (
    'FAST_FOOD','TRADITIONAL','GRILL','PIZZERIA','BAKERY','CAFE',
    'SEAFOOD','VEGETARIAN','INTERNATIONAL','OTHER'
  ));

create index if not exists idx_restaurant_profiles_type
  on public.restaurant_profiles(restaurant_type);
create index if not exists idx_restaurant_profiles_cuisines
  on public.restaurant_profiles using gin(cuisine_types);

create or replace function public.save_restaurant_discovery_profile(
  p_restaurant_id uuid,
  p_restaurant_type text,
  p_cuisine_types text[]
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_type text := upper(trim(coalesce(p_restaurant_type, 'OTHER')));
  v_cuisines text[] := coalesce(p_cuisine_types, '{}'::text[]);
  v_allowed text[] := array[
    'BURKINABE','IVORIAN','TOGOLESE','GHANAIAN','NIGERIAN','SENEGALESE',
    'MALIENNE','BENINESE','CAMEROONIAN','NIGERIEN','LEBANESE','ITALIAN',
    'FRENCH','CHINESE','INDIAN','MOROCCAN','TUNISIAN','OTHER'
  ];
  v_shop_id uuid;
begin
  if v_type not in (
    'FAST_FOOD','TRADITIONAL','GRILL','PIZZERIA','BAKERY','CAFE',
    'SEAFOOD','VEGETARIAN','INTERNATIONAL','OTHER'
  ) then
    raise exception 'invalid_restaurant_type';
  end if;
  if cardinality(v_cuisines) > 10 then
    raise exception 'too_many_cuisine_types';
  end if;
  if exists (select 1 from unnest(v_cuisines) c where upper(trim(c)) <> all(v_allowed)) then
    raise exception 'invalid_cuisine_type';
  end if;

  select rp.shop_id into v_shop_id
  from public.restaurant_profiles rp
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where rp.id = p_restaurant_id and se.user_id = auth.uid();

  if v_shop_id is null then raise exception 'restaurant_profile_not_owned'; end if;

  update public.restaurant_profiles
  set restaurant_type = v_type,
      cuisine_types = array(
        select distinct upper(trim(c))
        from unnest(v_cuisines) c
        where trim(c) <> ''
        order by upper(trim(c))
      )
  where id = p_restaurant_id;
end;
$$;

revoke all on function public.save_restaurant_discovery_profile(uuid,text,text[])
  from public, anon, authenticated;
grant execute on function public.save_restaurant_discovery_profile(uuid,text,text[])
  to authenticated;

-- One row per purchasable dish; filtering and matching happen in PostgreSQL,
-- not only on the first page of client-side results.
create or replace function public.search_restaurant_catalog(
  p_query text default null,
  p_restaurant_type text default null,
  p_cuisine_type text default null,
  p_limit integer default 100
) returns table (
  restaurant_id uuid,
  shop_id uuid,
  restaurant_name text,
  address text,
  restaurant_type text,
  cuisine_types text[],
  preparation_time_min integer,
  delivery_available boolean,
  menu_id uuid,
  menu_name text,
  menu_item_id uuid,
  dish_name text,
  dish_description text,
  price numeric,
  product_id uuid
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    rp.id,
    rp.shop_id,
    s.name::text,
    s.address::text,
    rp.restaurant_type,
    rp.cuisine_types,
    rp.preparation_time_min,
    rp.delivery_available,
    m.id,
    m.name::text,
    mi.id,
    mi.name::text,
    mi.description::text,
    p.price,
    p.id
  from public.restaurant_profiles rp
  join public.shops s on s.id = rp.shop_id
  join public.restaurant_menus m on m.restaurant_id = rp.id and m.active = true
  join public.restaurant_menu_items mi on mi.menu_id = m.id and mi.active = true
  join public.products p on p.id = mi.product_id
    and p.shop_id = rp.shop_id and p.status = 'ACTIVE'
  where
    (p_restaurant_type is null or p_restaurant_type = ''
      or rp.restaurant_type = upper(trim(p_restaurant_type)))
    and (p_cuisine_type is null or p_cuisine_type = ''
      or upper(trim(p_cuisine_type)) = any(rp.cuisine_types))
    and (
      nullif(trim(p_query), '') is null
      or mi.name ilike '%' || trim(p_query) || '%'
      or coalesce(mi.description, '') ilike '%' || trim(p_query) || '%'
      or m.name ilike '%' || trim(p_query) || '%'
      or s.name ilike '%' || trim(p_query) || '%'
      or exists (
        select 1 from unnest(rp.cuisine_types) cuisine
        where cuisine ilike '%' || trim(p_query) || '%'
      )
      or exists (
        select 1 from public.product_tags pt
        where pt.product_id = p.id and pt.tag ilike '%' || trim(p_query) || '%'
      )
    )
  order by
    case when nullif(trim(p_query), '') is not null
      and lower(mi.name) = lower(trim(p_query)) then 0 else 1 end,
    mi.sort_order,
    mi.name
  limit greatest(1, least(coalesce(p_limit, 100), 200));
$$;

revoke all on function public.search_restaurant_catalog(text,text,text,integer)
  from public;
grant execute on function public.search_restaurant_catalog(text,text,text,integer)
  to anon, authenticated;

comment on column public.restaurant_profiles.restaurant_type is
  'Restaurant business format: fast food, traditional, grill, pizzeria, etc.';
comment on column public.restaurant_profiles.cuisine_types is
  'Cuisine origins/tastes selected by the restaurant, e.g. BURKINABE, IVORIAN, TOGOLESE.';
