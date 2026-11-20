-- REVIEW PATCH ONLY.
-- Do not run this file directly in production. Convert it to a numbered migration,
-- run isolated PostgreSQL/pgTAP tests, inspect the diff, then deploy via the approved
-- Supabase migration workflow.

begin;

-- ---------------------------------------------------------------------------
-- A. Any food item can have seller-defined option groups, ingredients and levels.
-- No ingredient catalogue is hard-coded. A restaurant can add its own labels.
-- All money is computed again by PostgreSQL; clients send only selected level IDs.
-- ---------------------------------------------------------------------------

create table if not exists public.product_option_groups (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  selection_mode text not null default 'MULTIPLE'
    check (selection_mode in ('SINGLE','MULTIPLE')),
  min_select integer not null default 0 check (min_select between 0 and 100),
  max_select integer not null default 100 check (max_select between 1 and 100),
  required boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (min_select <= max_select),
  check (not required or min_select >= 1)
);

create table if not exists public.product_options (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.product_option_groups(id) on delete cascade,
  label text not null check (length(trim(label)) between 1 and 80),
  option_kind text not null default 'ADD'
    check (option_kind in ('ADD','REMOVE','CHOICE')),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.product_option_levels (
  id uuid primary key default gen_random_uuid(),
  option_id uuid not null references public.product_options(id) on delete cascade,
  label text not null check (length(trim(label)) between 1 and 80),
  quantity_value numeric(10,2) not null default 1 check (quantity_value >= 0),
  price_delta numeric(14,2) not null default 0 check (price_delta >= 0),
  is_default boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_product_option_groups_product_active
  on public.product_option_groups(product_id, active, sort_order);
create index if not exists idx_product_options_group_active
  on public.product_options(group_id, active, sort_order);
create index if not exists idx_product_option_levels_option_active
  on public.product_option_levels(option_id, active, sort_order);

alter table public.cart_items
  add column if not exists configuration_key text not null default 'DEFAULT',
  add column if not exists selected_option_level_ids uuid[] not null default '{}'::uuid[];

alter table public.order_items
  add column if not exists customizations jsonb not null default '[]'::jsonb;

alter table public.order_items
  drop constraint if exists order_items_customizations_array;
alter table public.order_items
  add constraint order_items_customizations_array
  check (jsonb_typeof(customizations) = 'array');

-- Different ingredient combinations must remain separate cart lines.
drop index if exists public.uq_cart_product_variant;
create unique index if not exists uq_cart_product_variant_configuration
  on public.cart_items(
    cart_id,
    product_id,
    coalesce(variant_id, '00000000-0000-0000-0000-000000000000'::uuid),
    configuration_key
  );

alter table public.product_option_groups enable row level security;
alter table public.product_options enable row level security;
alter table public.product_option_levels enable row level security;

revoke all on public.product_option_groups from anon, authenticated;
revoke all on public.product_options from anon, authenticated;
revoke all on public.product_option_levels from anon, authenticated;
grant select on public.product_option_groups to anon, authenticated;
grant select on public.product_options to anon, authenticated;
grant select on public.product_option_levels to anon, authenticated;

drop policy if exists product_option_groups_public_read on public.product_option_groups;
create policy product_option_groups_public_read
  on public.product_option_groups for select to anon, authenticated
  using (
    active = true and exists (
      select 1 from public.products p
      where p.id = product_id and p.status = 'ACTIVE'
    )
  );

drop policy if exists product_options_public_read on public.product_options;
create policy product_options_public_read
  on public.product_options for select to anon, authenticated
  using (
    active = true and exists (
      select 1
      from public.product_option_groups g
      join public.products p on p.id = g.product_id
      where g.id = group_id and g.active = true and p.status = 'ACTIVE'
    )
  );

drop policy if exists product_option_levels_public_read on public.product_option_levels;
create policy product_option_levels_public_read
  on public.product_option_levels for select to anon, authenticated
  using (
    active = true and exists (
      select 1
      from public.product_options o
      join public.product_option_groups g on g.id = o.group_id
      join public.products p on p.id = g.product_id
      where o.id = option_id and o.active = true
        and g.active = true and p.status = 'ACTIVE'
    )
  );

-- Seller-side writes are intentionally routed through ownership-checked RPCs,
-- rather than granting direct UPDATE/INSERT privileges on the option tables.
create or replace function public.save_product_option_group(
  p_product_id uuid,
  p_group_id uuid,
  p_name text,
  p_selection_mode text,
  p_min_select integer,
  p_max_select integer,
  p_required boolean default false,
  p_sort_order integer default 0
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
  v_mode text := upper(trim(coalesce(p_selection_mode,'')));
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_product_id is null
     or nullif(trim(coalesce(p_name,'')), '') is null
     or length(trim(p_name)) > 80
     or v_mode not in ('SINGLE','MULTIPLE')
     or p_min_select is null or p_min_select < 0 or p_min_select > 100
     or p_max_select is null or p_max_select < 1 or p_max_select > 100
     or p_min_select > p_max_select
     or (coalesce(p_required,false) and p_min_select < 1) then
    raise exception 'product_option_group_invalid';
  end if;

  if not exists (
    select 1
    from public.products p
    join public.restaurant_profiles rp on rp.shop_id=p.shop_id
    join public.shops sh on sh.id = p.shop_id
    join public.sellers s on s.id = sh.seller_id
    where p.id = p_product_id and s.user_id = v_user
  ) then
    raise exception 'product_not_owned';
  end if;

  if p_group_id is null then
    insert into public.product_option_groups(
      product_id,name,selection_mode,min_select,max_select,required,sort_order
    ) values (
      p_product_id,trim(p_name),v_mode,p_min_select,p_max_select,
      coalesce(p_required,false),coalesce(p_sort_order,0)
    ) returning id into v_id;
  else
    update public.product_option_groups g
    set name=trim(p_name),selection_mode=v_mode,min_select=p_min_select,
        max_select=p_max_select,required=coalesce(p_required,false),
        sort_order=coalesce(p_sort_order,0),updated_at=now()
    where g.id=p_group_id and g.product_id=p_product_id;
    if not found then raise exception 'product_option_group_not_owned'; end if;
    v_id := p_group_id;
  end if;

  return v_id;
end;
$function$;

create or replace function public.save_product_option(
  p_group_id uuid,
  p_option_id uuid,
  p_label text,
  p_option_kind text default 'ADD',
  p_sort_order integer default 0
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
  v_kind text := upper(trim(coalesce(p_option_kind,'')));
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_group_id is null
     or nullif(trim(coalesce(p_label,'')), '') is null
     or length(trim(p_label)) > 80
     or v_kind not in ('ADD','REMOVE','CHOICE') then
    raise exception 'product_option_invalid';
  end if;

  if not exists (
    select 1 from public.product_option_groups g
    join public.products p on p.id=g.product_id
    join public.shops sh on sh.id=p.shop_id
    join public.sellers s on s.id=sh.seller_id
    where g.id=p_group_id and s.user_id=v_user
  ) then
    raise exception 'product_option_group_not_owned';
  end if;

  if p_option_id is null then
    insert into public.product_options(group_id,label,option_kind,sort_order)
    values(p_group_id,trim(p_label),v_kind,coalesce(p_sort_order,0))
    returning id into v_id;
  else
    update public.product_options
    set label=trim(p_label),option_kind=v_kind,
        sort_order=coalesce(p_sort_order,0),updated_at=now()
    where id=p_option_id and group_id=p_group_id;
    if not found then raise exception 'product_option_not_owned'; end if;
    v_id := p_option_id;
  end if;
  return v_id;
end;
$function$;

create or replace function public.save_product_option_level(
  p_option_id uuid,
  p_level_id uuid,
  p_label text,
  p_price_delta numeric,
  p_quantity_value numeric default 1,
  p_is_default boolean default false,
  p_sort_order integer default 0
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_id uuid;
  v_option_group uuid;
  v_option_kind text;
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_option_id is null
     or nullif(trim(coalesce(p_label,'')), '') is null
     or length(trim(p_label)) > 80
     or p_price_delta is null or p_price_delta < 0 or p_price_delta > 100000000
     or p_quantity_value is null or p_quantity_value < 0 or p_quantity_value > 100000 then
    raise exception 'product_option_level_invalid';
  end if;

  select g.id,o.option_kind into v_option_group,v_option_kind
  from public.product_options o
  join public.product_option_groups g on g.id=o.group_id
  join public.products p on p.id=g.product_id
  join public.shops sh on sh.id=p.shop_id
  join public.sellers s on s.id=sh.seller_id
  where o.id=p_option_id and s.user_id=v_user;

  if v_option_group is null then raise exception 'product_option_not_owned'; end if;
  if v_option_kind='REMOVE' and p_price_delta<>0 then
    raise exception 'removal_option_cannot_cost_extra';
  end if;

  if p_level_id is null then
    insert into public.product_option_levels(
      option_id,label,price_delta,quantity_value,is_default,sort_order
    ) values (
      p_option_id,trim(p_label),p_price_delta,p_quantity_value,
      coalesce(p_is_default,false),coalesce(p_sort_order,0)
    ) returning id into v_id;
  else
    update public.product_option_levels
    set label=trim(p_label),price_delta=p_price_delta,
        quantity_value=p_quantity_value,is_default=coalesce(p_is_default,false),
        sort_order=coalesce(p_sort_order,0),updated_at=now()
    where id=p_level_id and option_id=p_option_id;
    if not found then raise exception 'product_option_level_not_owned'; end if;
    v_id := p_level_id;
  end if;
  return v_id;
end;
$function$;

revoke all on function public.save_product_option_group(uuid,uuid,text,text,integer,integer,boolean,integer) from public, anon;
revoke all on function public.save_product_option(uuid,uuid,text,text,integer) from public, anon;
revoke all on function public.save_product_option_level(uuid,uuid,text,numeric,numeric,boolean,integer) from public, anon;
grant execute on function public.save_product_option_group(uuid,uuid,text,text,integer,integer,boolean,integer) to authenticated;
grant execute on function public.save_product_option(uuid,uuid,text,text,integer) to authenticated;
grant execute on function public.save_product_option_level(uuid,uuid,text,numeric,numeric,boolean,integer) to authenticated;

-- Always calculate the price from the catalogue, never from a value supplied
-- by the customer or from cart_items.unit_price.
create or replace function public.get_product_configured_unit_price(
  p_product_id uuid,
  p_variant_id uuid,
  p_selected_level_ids uuid[]
) returns numeric
language plpgsql stable security definer
set search_path = pg_catalog, public
as $function$
declare
  v_base numeric;
  v_variant_product uuid;
  v_total_delta numeric := 0;
  v_selected uuid[] := coalesce(p_selected_level_ids,'{}'::uuid[]);
  v_count integer;
begin
  if p_product_id is null or cardinality(v_selected) > 100 then
    raise exception 'product_configuration_invalid';
  end if;

  if cardinality(v_selected) <> (
    select count(distinct x) from unnest(v_selected) x
  ) then
    raise exception 'duplicate_product_option';
  end if;

  select p.price into v_base
  from public.products p
  where p.id=p_product_id and p.status='ACTIVE'
    and not (p.is_expirable and (p.expiry_date is null or p.expiry_date < current_date));

  if v_base is null then raise exception 'product_unavailable'; end if;

  if p_variant_id is not null then
    select pv.product_id,coalesce(pv.price,v_base)
      into v_variant_product,v_base
    from public.product_variants pv
    where pv.id=p_variant_id;
    if v_variant_product is distinct from p_product_id then
      raise exception 'invalid_variant';
    end if;
  end if;

  select count(*) into v_count
  from unnest(v_selected) x
  join public.product_option_levels l on l.id=x
  join public.product_options o on o.id=l.option_id
  join public.product_option_groups g on g.id=o.group_id
  where g.product_id=p_product_id and g.active and o.active and l.active;

  if v_count <> cardinality(v_selected) then
    raise exception 'product_option_unavailable';
  end if;

  if exists (
    select 1
    from public.product_option_groups g
    left join (
      select o.group_id,count(*)::integer as selected_count
      from unnest(v_selected) x
      join public.product_option_levels l on l.id=x
      join public.product_options o on o.id=l.option_id
      group by o.group_id
    ) chosen on chosen.group_id=g.id
    where g.product_id=p_product_id and g.active
      and coalesce(chosen.selected_count,0) < g.min_select
  ) then
    raise exception 'product_option_required';
  end if;

  if exists (
    select 1
    from public.product_option_groups g
    left join (
      select o.group_id,count(*)::integer as selected_count
      from unnest(v_selected) x
      join public.product_option_levels l on l.id=x
      join public.product_options o on o.id=l.option_id
      group by o.group_id
    ) chosen on chosen.group_id=g.id
    where g.product_id=p_product_id and g.active
      and coalesce(chosen.selected_count,0) > g.max_select
  ) then
    raise exception 'product_option_limit_exceeded';
  end if;

  if exists (
    select 1
    from unnest(v_selected) x
    join public.product_option_levels l on l.id=x
    join public.product_options o on o.id=l.option_id
    join public.product_option_groups g on g.id=o.group_id
    where g.product_id=p_product_id
    group by o.id
    having count(*) > 1
  ) then
    raise exception 'product_option_level_duplicate';
  end if;

  if exists (
    select 1
    from unnest(v_selected) x
    join public.product_option_levels l on l.id=x
    join public.product_options o on o.id=l.option_id
    join public.product_option_groups g on g.id=o.group_id
    where g.product_id=p_product_id and g.selection_mode='SINGLE'
    group by g.id
    having count(*) > 1
  ) then
    raise exception 'product_option_single_choice';
  end if;

  select coalesce(sum(l.price_delta),0) into v_total_delta
  from unnest(v_selected) x
  join public.product_option_levels l on l.id=x;

  return v_base + v_total_delta;
end;
$function$;

create or replace function public.get_product_customization_snapshot(
  p_product_id uuid,
  p_selected_level_ids uuid[]
) returns jsonb
language sql stable security definer
set search_path = pg_catalog, public
as $function$
  select coalesce(jsonb_agg(jsonb_build_object(
    'group_id',g.id,
    'group_name',g.name,
    'option_id',o.id,
    'option_name',o.label,
    'option_kind',o.option_kind,
    'level_id',l.id,
    'level_name',l.label,
    'quantity_value',l.quantity_value,
    'price_delta',l.price_delta
  ) order by g.sort_order,o.sort_order,l.sort_order),'[]'::jsonb)
  from unnest(coalesce(p_selected_level_ids,'{}'::uuid[])) x
  join public.product_option_levels l on l.id=x
  join public.product_options o on o.id=l.option_id and o.active
  join public.product_option_groups g on g.id=o.group_id
  where g.product_id=p_product_id and g.active and l.active;
$function$;

create or replace function public.add_configured_restaurant_item_to_cart(
  p_product_id uuid,
  p_variant_id uuid default null,
  p_quantity integer default 1,
  p_selected_level_ids uuid[] default '{}'::uuid[]
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_cart uuid;
  v_item uuid;
  v_price numeric;
  v_key text;
  v_snapshot jsonb;
  v_available integer;
  v_existing_quantity integer;
  v_stock_rows integer;
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 1000 then
    raise exception 'invalid_quantity';
  end if;

  if not exists (
    select 1 from public.products p
    join public.restaurant_profiles rp on rp.shop_id=p.shop_id
    where p.id=p_product_id and p.status='ACTIVE'
  ) then
    raise exception 'restaurant_product_unavailable';
  end if;

  v_price := public.get_product_configured_unit_price(
    p_product_id,p_variant_id,coalesce(p_selected_level_ids,'{}'::uuid[])
  );
  v_snapshot := public.get_product_customization_snapshot(
    p_product_id,coalesce(p_selected_level_ids,'{}'::uuid[])
  );

  v_key := case
    when cardinality(coalesce(p_selected_level_ids,'{}'::uuid[]))=0 then 'DEFAULT'
    else md5(array_to_string(
      array(select x::text from unnest(p_selected_level_ids) x order by x::text),
      ','
    ))
  end;

  -- Lock the relevant stock row and include all configurations of the same
  -- product/variant already present in this customer's cart.
  if p_variant_id is null then
    select i.quantity-i.reserved_quantity into v_available
    from public.inventory i
    where i.product_id=p_product_id
    for update;
  else
    select vi.quantity-vi.reserved_quantity into v_available
    from public.product_variant_inventory vi
    where vi.variant_id=p_variant_id and vi.product_id=p_product_id
    for update;
    if not found then
      select i.quantity-i.reserved_quantity into v_available
      from public.inventory i where i.product_id=p_product_id for update;
    end if;
  end if;

  perform 1 from public.profiles where id=v_user for update;
  select id into v_cart from public.carts
  where customer_id=v_user and status='ACTIVE' for update;

  if v_cart is null then
    insert into public.carts(customer_id,status)
    values(v_user,'ACTIVE') returning id into v_cart;
  end if;

  select coalesce(sum(ci.quantity),0)::integer into v_existing_quantity
  from public.cart_items ci
  where ci.cart_id=v_cart and ci.product_id=p_product_id
    and ci.variant_id is not distinct from p_variant_id;

  if v_available is not null and v_existing_quantity+p_quantity>v_available then
    raise exception 'insufficient_stock';
  end if;

  insert into public.cart_items(
    cart_id,product_id,variant_id,quantity,unit_price,
    configuration_key,selected_option_level_ids
  ) values (
    v_cart,p_product_id,p_variant_id,p_quantity,v_price,v_key,
    coalesce(p_selected_level_ids,'{}'::uuid[])
  )
  on conflict (
    cart_id,product_id,
    (coalesce(variant_id,'00000000-0000-0000-0000-000000000000'::uuid)),
    configuration_key
  ) do update set
    quantity=public.cart_items.quantity+excluded.quantity,
    unit_price=excluded.unit_price,
    selected_option_level_ids=excluded.selected_option_level_ids
  returning id into v_item;

  update public.carts set updated_at=now() where id=v_cart;
  return v_item;
end;
$function$;

revoke all on function public.get_product_configured_unit_price(uuid,uuid,uuid[]) from public, anon, authenticated;
revoke all on function public.get_product_customization_snapshot(uuid,uuid[]) from public, anon, authenticated;
revoke all on function public.add_configured_restaurant_item_to_cart(uuid,uuid,integer,uuid[]) from public, anon;
grant execute on function public.add_configured_restaurant_item_to_cart(uuid,uuid,integer,uuid[]) to authenticated;

-- Keep ordinary (non-customized) add_to_cart calls compatible with the new
-- configuration-aware unique key.
do $patch$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.add_to_cart(uuid,integer,uuid)'::regprocedure);
  v_def := replace(
    v_def,
    'insert into public.cart_items(cart_id, product_id, variant_id, quantity, unit_price)',
    'insert into public.cart_items(cart_id, product_id, variant_id, quantity, unit_price, configuration_key)'
  );
  v_def := replace(
    v_def,
    'values (v_cart_id, p_product_id, p_variant_id, p_quantity, v_unit_price)',
    'values (v_cart_id, p_product_id, p_variant_id, p_quantity, v_unit_price, ''DEFAULT'')'
  );
  v_def := replace(
    v_def,
    'on conflict (cart_id, product_id, coalesce(variant_id, ''00000000-0000-0000-0000-000000000000''::uuid))',
    'on conflict (cart_id, product_id, (coalesce(variant_id, ''00000000-0000-0000-0000-000000000000''::uuid)), configuration_key)'
  );
  if v_def not like '%configuration_key%' then
    raise exception 'add_to_cart_configuration_patch_failed';
  end if;
  execute v_def;
end;
$patch$;

-- Checkout validates every selected level again, computes the current seller
-- price from the server catalogue, and preserves a snapshot for the seller.
do $patch$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef(
    'public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure
  );

  v_old := '      ci.quantity,' || chr(10) ||
           '      p.name,' || chr(10) ||
           '      p.price,' || chr(10) ||
           '      p.shop_id,' || chr(10) ||
           '      p.status,';
  v_new := '      ci.quantity,' || chr(10) ||
           '      ci.selected_option_level_ids,' || chr(10) ||
           '      p.name,' || chr(10) ||
           '      p.price,' || chr(10) ||
           '      p.shop_id,' || chr(10) ||
           '      p.status,';
  if position(v_old in v_def)=0 then
    raise exception 'checkout_selected_levels_select_not_found';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '      pv.price as variant_price,' || chr(10) ||
           '      pv.product_id as variant_product_id';
  v_new := '      pv.price as variant_price,' || chr(10) ||
           '      pv.product_id as variant_product_id,' || chr(10) ||
           '      public.get_product_configured_unit_price(ci.product_id,ci.variant_id,ci.selected_option_level_ids) as final_unit_price,' || chr(10) ||
           '      public.get_product_customization_snapshot(ci.product_id,ci.selected_option_level_ids) as customization_snapshot';
  if position(v_old in v_def)=0 then
    raise exception 'checkout_option_price_snapshot_select_not_found';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '      ci.quantity,' || chr(10) ||
           '      p.name,' || chr(10) ||
           '      p.shop_id,' || chr(10) ||
           '      p.price,';
  v_new := '      ci.quantity,' || chr(10) ||
           '      p.name,' || chr(10) ||
           '      p.shop_id,' || chr(10) ||
           '      p.price,';
  if position(v_old in v_def)>0 then
    v_def := replace(v_def,v_old,v_new);
  end if;

  v_old := '      pv.price as variant_price' || chr(10) ||
           '    from public.cart_items ci';
  v_new := '      pv.price as variant_price,' || chr(10) ||
           '      public.get_product_configured_unit_price(ci.product_id,ci.variant_id,ci.selected_option_level_ids) as final_unit_price,' || chr(10) ||
           '      public.get_product_customization_snapshot(ci.product_id,ci.selected_option_level_ids) as customization_snapshot' || chr(10) ||
           '    from public.cart_items ci';
  if position(v_old in v_def)=0 then
    raise exception 'checkout_order_item_snapshot_select_not_found';
  end if;
  v_def := replace(v_def,v_old,v_new);

  v_def := replace(
    v_def,
    'coalesce(v_item.variant_price, v_item.price)',
    'v_item.final_unit_price'
  );

  v_old := '    insert into public.order_items(' || chr(10) ||
           '      order_group_id,' || chr(10) ||
           '      product_id,' || chr(10) ||
           '      variant_id,' || chr(10) ||
           '      product_name,' || chr(10) ||
           '      quantity,' || chr(10) ||
           '      unit_price,' || chr(10) ||
           '      total_price' || chr(10) ||
           '    )' || chr(10) ||
           '    values(' || chr(10) ||
           '      v_group_id,' || chr(10) ||
           '      v_item.product_id,' || chr(10) ||
           '      v_item.variant_id,' || chr(10) ||
           '      v_item.name,' || chr(10) ||
           '      v_item.quantity,' || chr(10) ||
           '      v_item.final_unit_price,' || chr(10) ||
           '      v_item.final_unit_price * v_item.quantity' || chr(10) ||
           '    );';
  v_new := '    insert into public.order_items(' || chr(10) ||
           '      order_group_id,' || chr(10) ||
           '      product_id,' || chr(10) ||
           '      variant_id,' || chr(10) ||
           '      product_name,' || chr(10) ||
           '      quantity,' || chr(10) ||
           '      unit_price,' || chr(10) ||
           '      total_price,' || chr(10) ||
           '      customizations' || chr(10) ||
           '    )' || chr(10) ||
           '    values(' || chr(10) ||
           '      v_group_id,' || chr(10) ||
           '      v_item.product_id,' || chr(10) ||
           '      v_item.variant_id,' || chr(10) ||
           '      v_item.name,' || chr(10) ||
           '      v_item.quantity,' || chr(10) ||
           '      v_item.final_unit_price,' || chr(10) ||
           '      v_item.final_unit_price * v_item.quantity,' || chr(10) ||
           '      v_item.customization_snapshot' || chr(10) ||
           '    );';
  if position(v_old in v_def)=0 then
    raise exception 'checkout_order_items_insert_not_found';
  end if;
  v_def := replace(v_def,v_old,v_new);

  if v_def not like '%get_product_configured_unit_price%' or
     v_def not like '%customizations%' or
     v_def not like '%selected_option_level_ids%' then
    raise exception 'checkout_customization_patch_failed';
  end if;

  execute v_def;
end;
$patch$;

-- Customer can view only the option labels for their own active cart item.
create or replace function public.get_my_cart_item_customizations(
  p_cart_item_id uuid
) returns jsonb
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_snapshot jsonb;
begin
  if v_user is null then raise exception 'not_authenticated'; end if;

  select public.get_product_customization_snapshot(
    ci.product_id,ci.selected_option_level_ids
  )
  into v_snapshot
  from public.cart_items ci
  join public.carts c on c.id=ci.cart_id
  where ci.id=p_cart_item_id
    and c.customer_id=v_user
    and c.status='ACTIVE';

  if not found then raise exception 'cart_item_not_owned_or_inactive'; end if;
  return coalesce(v_snapshot,'[]'::jsonb);
end;
$function$;

revoke all on function public.get_my_cart_item_customizations(uuid) from public,anon;
grant execute on function public.get_my_cart_item_customizations(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Exact office delivery times; the client selects a time, but the server
-- validates and persists it. Seller order groups receive a safe snapshot.
-- ---------------------------------------------------------------------------

alter table public.order_groups
  add column if not exists delivery_place_type text not null default 'HOME',
  add column if not exists scheduled_delivery_at timestamptz,
  add column if not exists delivery_instructions text;

alter table public.order_groups
  drop constraint if exists order_groups_delivery_place_type_valid;
alter table public.order_groups
  add constraint order_groups_delivery_place_type_valid
  check (delivery_place_type in ('HOME','OFFICE'));

create or replace function public.copy_order_delivery_schedule_to_group()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
declare
  v_address jsonb;
begin
  select o.delivery_address into v_address
  from public.orders o where o.id=NEW.order_id;

  if v_address is not null then
    NEW.delivery_place_type := coalesce(
      nullif(v_address->>'delivery_place_type',''),
      'HOME'
    );
    NEW.scheduled_delivery_at := nullif(
      v_address->>'scheduled_delivery_at',''
    )::timestamptz;
    NEW.delivery_instructions := nullif(
      trim(coalesce(v_address->>'delivery_instructions','')),''
    );
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_copy_order_delivery_schedule_to_group on public.order_groups;
create trigger trg_copy_order_delivery_schedule_to_group
before insert on public.order_groups
for each row execute function public.copy_order_delivery_schedule_to_group();

-- Carry only whitelisted schedule fields through checkout's address ownership
-- lookup. The delivery address itself continues to be loaded from the user's
-- saved delivery_addresses row, not trusted from the client.
do $patch$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure);

  v_old := '  v_delivery_address jsonb;' ;
  v_new := '  v_delivery_address jsonb;' || chr(10) ||
           '  v_requested_delivery_at timestamptz;' || chr(10) ||
           '  v_delivery_place_type text := upper(trim(coalesce(p_delivery_address->>''delivery_place_type'',''HOME'')));';
  if position(v_old in v_def)=0 then raise exception 'checkout_delivery_declaration_patch_not_found'; end if;
  v_def := replace(v_def,v_old,v_new);

  v_old := '  if v_delivery_address is null then' || chr(10) ||
           '    raise exception ''delivery_address_not_owned'';' || chr(10) ||
           '  end if;';
  v_new := v_old || chr(10) ||
           chr(10) || '  if v_delivery_place_type not in (''HOME'',''OFFICE'') then' || chr(10) ||
           '    raise exception ''delivery_place_type_invalid'';' || chr(10) ||
           '  end if;' || chr(10) ||
           '  if nullif(trim(coalesce(p_delivery_address->>''scheduled_delivery_at'','''')) , '''') is not null then' || chr(10) ||
           '    begin' || chr(10) ||
           '      v_requested_delivery_at := (p_delivery_address->>''scheduled_delivery_at'')::timestamptz;' || chr(10) ||
           '    exception when others then' || chr(10) ||
           '      raise exception ''delivery_schedule_invalid'';' || chr(10) ||
           '    end;' || chr(10) ||
           '    if v_requested_delivery_at <= now() or date_trunc(''minute'',v_requested_delivery_at) <> v_requested_delivery_at or extract(minute from v_requested_delivery_at) <> 0 then' || chr(10) ||
           '      raise exception ''delivery_schedule_must_be_future_hour'';' || chr(10) ||
           '    end if;' || chr(10) ||
           '  elsif v_delivery_place_type = ''OFFICE'' then' || chr(10) ||
           '    raise exception ''office_delivery_time_required'';' || chr(10) ||
           '  end if;' || chr(10) ||
           '  v_delivery_address := v_delivery_address || jsonb_strip_nulls(jsonb_build_object(' || chr(10) ||
           '    ''delivery_place_type'',v_delivery_place_type,' || chr(10) ||
           '    ''scheduled_delivery_at'',v_requested_delivery_at,' || chr(10) ||
           '    ''delivery_instructions'',nullif(trim(coalesce(p_delivery_address->>''delivery_instructions'','''')) , '''')' || chr(10) ||
           '  ));';
  if position(v_old in v_def)=0 then raise exception 'checkout_delivery_validation_patch_not_found'; end if;
  v_def := replace(v_def,v_old,v_new);
  execute v_def;
end;
$patch$;

-- Notify the shop owner after successful payment only. The unique lookup in
-- data->>order_group_id makes retries/webhook repetitions idempotent.
create or replace function public.notify_sellers_after_paid_order()
returns trigger
language plpgsql security definer
set search_path = pg_catalog, public
as $function$
begin
  if NEW.status='PAID' and OLD.status is distinct from NEW.status then
    insert into public.notifications(user_id,type,title,body,data)
    select
      s.user_id,
      'ORDER_RECEIVED',
      case when og.scheduled_delivery_at is null
        then 'Nouvelle commande payée'
        else 'Commande payée — livraison programmée'
      end,
      case when og.scheduled_delivery_at is null
        then 'Une nouvelle commande payée attend votre confirmation.'
        else 'Livraison demandée le ' ||
             to_char(og.scheduled_delivery_at at time zone 'Africa/Ouagadougou','DD/MM/YYYY à HH24:MI') ||
             ' pile (' || case when og.delivery_place_type='OFFICE' then 'bureau' else 'domicile' end || ').'
      end,
      jsonb_build_object(
        'order_id',NEW.id,
        'order_group_id',og.id,
        'shop_id',og.shop_id,
        'delivery_place_type',og.delivery_place_type,
        'scheduled_delivery_at',og.scheduled_delivery_at,
        'delivery_instructions',og.delivery_instructions
      )
    from public.order_groups og
    join public.shops sh on sh.id=og.shop_id
    join public.sellers s on s.id=sh.seller_id
    where og.order_id=NEW.id
      and not exists (
        select 1 from public.notifications n
        where n.user_id=s.user_id
          and n.type='ORDER_RECEIVED'
          and n.data->>'order_group_id'=og.id::text
      );
  end if;
  return NEW;
end;
$function$;

drop trigger if exists trg_notify_sellers_after_paid_order on public.orders;
create trigger trg_notify_sellers_after_paid_order
after update of status on public.orders
for each row execute function public.notify_sellers_after_paid_order();

commit;
