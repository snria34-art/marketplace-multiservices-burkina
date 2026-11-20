-- Restaurant menu customization: seller-managed option groups and server-side price quotes.
create table if not exists public.restaurant_menu_item_option_groups (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references public.restaurant_menu_items(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  selection_type text not null default 'SINGLE'
    check (selection_type in ('SINGLE', 'MULTIPLE')),
  min_selections integer not null default 0 check (min_selections >= 0),
  max_selections integer not null default 1 check (max_selections between 1 and 20),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (min_selections <= max_selections),
  check (selection_type <> 'SINGLE' or max_selections = 1)
);

create table if not exists public.restaurant_menu_item_options (
  id uuid primary key default gen_random_uuid(),
  option_group_id uuid not null references public.restaurant_menu_item_option_groups(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 80),
  price_delta numeric(14,2) not null default 0 check (price_delta >= 0),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_restaurant_option_groups_item
  on public.restaurant_menu_item_option_groups(menu_item_id, active, sort_order);
create index if not exists idx_restaurant_options_group
  on public.restaurant_menu_item_options(option_group_id, active, sort_order);

alter table public.restaurant_menu_item_option_groups enable row level security;
alter table public.restaurant_menu_item_options enable row level security;

drop policy if exists restaurant_active_option_groups_read
  on public.restaurant_menu_item_option_groups;
create policy restaurant_active_option_groups_read
  on public.restaurant_menu_item_option_groups
  for select to anon, authenticated
  using (
    active = true
    and exists (
      select 1
      from public.restaurant_menu_items mi
      join public.restaurant_menus m on m.id = mi.menu_id
      where mi.id = menu_item_id and mi.active = true and m.active = true
    )
  );

drop policy if exists restaurant_active_options_read
  on public.restaurant_menu_item_options;
create policy restaurant_active_options_read
  on public.restaurant_menu_item_options
  for select to anon, authenticated
  using (
    active = true
    and exists (
      select 1
      from public.restaurant_menu_item_option_groups g
      join public.restaurant_menu_items mi on mi.id = g.menu_item_id
      join public.restaurant_menus m on m.id = mi.menu_id
      where g.id = option_group_id and g.active = true
        and mi.active = true and m.active = true
    )
  );




-- Permit a restaurant owner to link each menu item to a product in the same shop.
grant update(product_id) on public.restaurant_menu_items to authenticated;

drop policy if exists restaurant_seller_item_link_update on public.restaurant_menu_items;
create policy restaurant_seller_item_link_update on public.restaurant_menu_items
for update to authenticated
using (exists (
  select 1
  from public.restaurant_menus m
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where m.id = menu_id and se.user_id = (select auth.uid())
))
with check (
  exists (
    select 1
    from public.restaurant_menus m
    join public.restaurant_profiles rp on rp.id = m.restaurant_id
    join public.shops s on s.id = rp.shop_id
    join public.sellers se on se.id = s.seller_id
    where m.id = menu_id and se.user_id = (select auth.uid())
  )
  and (
    product_id is null
    or exists (
      select 1
      from public.restaurant_menus m
      join public.restaurant_profiles rp on rp.id = m.restaurant_id
      join public.shops s on s.id = rp.shop_id
      join public.sellers se on se.id = s.seller_id
      join public.products p on p.shop_id = s.id
      where m.id = menu_id and p.id = product_id
        and se.user_id = (select auth.uid())
    )
  )
);

-- Seller catalog visibility and ownership policies allow SECURITY INVOKER writes.
drop policy if exists restaurant_seller_profile_read on public.restaurant_profiles;
create policy restaurant_seller_profile_read on public.restaurant_profiles
for select to authenticated
using (exists (
  select 1 from public.shops s
  join public.sellers se on se.id = s.seller_id
  where s.id = shop_id and se.user_id = (select auth.uid())
));

drop policy if exists restaurant_seller_menu_read on public.restaurant_menus;
create policy restaurant_seller_menu_read on public.restaurant_menus
for select to authenticated
using (exists (
  select 1 from public.restaurant_profiles rp
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where rp.id = restaurant_id and se.user_id = (select auth.uid())
));

drop policy if exists restaurant_seller_item_read on public.restaurant_menu_items;
create policy restaurant_seller_item_read on public.restaurant_menu_items
for select to authenticated
using (exists (
  select 1 from public.restaurant_menus m
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where m.id = menu_id and se.user_id = (select auth.uid())
));

drop policy if exists restaurant_seller_option_groups_manage on public.restaurant_menu_item_option_groups;
create policy restaurant_seller_option_groups_manage on public.restaurant_menu_item_option_groups
for all to authenticated
using (exists (
  select 1 from public.restaurant_menu_items mi
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where mi.id = menu_item_id and se.user_id = (select auth.uid())
))
with check (exists (
  select 1 from public.restaurant_menu_items mi
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where mi.id = menu_item_id and se.user_id = (select auth.uid())
));

drop policy if exists restaurant_seller_options_manage on public.restaurant_menu_item_options;
create policy restaurant_seller_options_manage on public.restaurant_menu_item_options
for all to authenticated
using (exists (
  select 1 from public.restaurant_menu_item_option_groups g
  join public.restaurant_menu_items mi on mi.id = g.menu_item_id
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where g.id = option_group_id and se.user_id = (select auth.uid())
))
with check (exists (
  select 1 from public.restaurant_menu_item_option_groups g
  join public.restaurant_menu_items mi on mi.id = g.menu_item_id
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where g.id = option_group_id and se.user_id = (select auth.uid())
));

grant select on public.restaurant_menu_item_option_groups,
  public.restaurant_menu_item_options to anon, authenticated;
grant insert, update, delete on public.restaurant_menu_item_option_groups,
  public.restaurant_menu_item_options to authenticated;

-- Sellers configure a whole option group atomically. Client roles cannot write
-- the option tables directly; ownership is checked against the authenticated seller.
create or replace function public.save_restaurant_item_option_group(
  p_menu_item_id uuid,
  p_name text,
  p_selection_type text,
  p_min_selections integer,
  p_max_selections integer,
  p_options jsonb,
  p_group_id uuid default null
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_group_id uuid;
  v_type text := upper(trim(coalesce(p_selection_type, '')));
  v_option jsonb;
  v_name text;
  v_delta numeric;
  v_count integer := 0;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_menu_item_id is null then raise exception 'menu_item_required'; end if;
  if length(trim(coalesce(p_name, ''))) not between 1 and 80 then
    raise exception 'invalid_option_group_name';
  end if;
  if v_type not in ('SINGLE', 'MULTIPLE') then raise exception 'invalid_selection_type'; end if;
  if p_min_selections is null or p_max_selections is null
     or p_min_selections < 0 or p_max_selections < 1
     or p_max_selections > 20 or p_min_selections > p_max_selections
     or (v_type = 'SINGLE' and p_max_selections <> 1) then
    raise exception 'invalid_selection_limits';
  end if;
  if p_options is null or jsonb_typeof(p_options) is distinct from 'array'
     or jsonb_array_length(p_options) < 1
     or jsonb_array_length(p_options) > 30 then
    raise exception 'invalid_options';
  end if;

  perform 1
  from public.restaurant_menu_items mi
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where mi.id = p_menu_item_id and se.user_id = v_user_id
  ;
  if not found then raise exception 'menu_item_not_owned'; end if;

  if p_group_id is not null then
    select id into v_group_id
    from public.restaurant_menu_item_option_groups
    where id = p_group_id and menu_item_id = p_menu_item_id
    for update;
    if v_group_id is null then raise exception 'option_group_not_found'; end if;
    update public.restaurant_menu_item_option_groups
      set name = trim(p_name), selection_type = v_type,
          min_selections = p_min_selections, max_selections = p_max_selections,
          updated_at = now()
      where id = v_group_id;
    delete from public.restaurant_menu_item_options where option_group_id = v_group_id;
  else
    insert into public.restaurant_menu_item_option_groups(
      menu_item_id, name, selection_type, min_selections, max_selections
    ) values (
      p_menu_item_id, trim(p_name), v_type, p_min_selections, p_max_selections
    ) returning id into v_group_id;
  end if;

  for v_option in select value from jsonb_array_elements(p_options)
  loop
    v_count := v_count + 1;
    v_name := trim(coalesce(v_option->>'name', ''));
    if length(v_name) not between 1 and 80 then raise exception 'invalid_option_name'; end if;
    begin
      v_delta := coalesce((v_option->>'price_delta')::numeric, 0);
    exception when others then
      raise exception 'invalid_option_price';
    end;
    if v_delta < 0 or v_delta > 100000000 then raise exception 'invalid_option_price'; end if;
    insert into public.restaurant_menu_item_options(
      option_group_id, name, price_delta, sort_order
    ) values (v_group_id, v_name, v_delta, v_count);
  end loop;

  if p_min_selections > v_count then raise exception 'minimum_exceeds_option_count'; end if;
  return v_group_id;
end;
$$;

revoke all on function public.save_restaurant_item_option_group(uuid,text,text,integer,integer,jsonb,uuid)
  from public, anon, authenticated;
grant execute on function public.save_restaurant_item_option_group(uuid,text,text,integer,integer,jsonb,uuid)
  to authenticated;

-- Price quote is authoritative for display; all option IDs and selection limits
-- are checked against active catalog rows on the database.
create or replace function public.quote_restaurant_menu_item(
  p_menu_item_id uuid,
  p_selections jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_item public.restaurant_menu_items%rowtype;
  v_group record;
  v_ids uuid[];
  v_selected_count integer;
  v_surcharge numeric := 0;
  v_base numeric;
begin
  if p_menu_item_id is null then raise exception 'menu_item_required'; end if;
  if p_selections is null or jsonb_typeof(p_selections) <> 'object' then
    raise exception 'invalid_selections';
  end if;

  select mi.* into v_item
  from public.restaurant_menu_items mi
  join public.restaurant_menus m on m.id = mi.menu_id
  where mi.id = p_menu_item_id and mi.active = true and m.active = true;
  if not found then raise exception 'menu_item_unavailable'; end if;

  select p.price into v_base
  from public.products p
  join public.restaurant_menu_items mi on mi.product_id = p.id
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  where mi.id = p_menu_item_id
    and p.id = v_item.product_id
    and p.shop_id = rp.shop_id
    and p.status = 'ACTIVE';
  if v_base is null then raise exception 'restaurant_item_product_unavailable'; end if;

  for v_group in
    select g.id, g.name, g.selection_type, g.min_selections, g.max_selections
    from public.restaurant_menu_item_option_groups g
    where g.menu_item_id = p_menu_item_id and g.active = true
  loop
    if not (p_selections ? v_group.id::text) then
      v_ids := array[]::uuid[];
    else
      if jsonb_typeof(p_selections->v_group.id::text) <> 'array' then
        raise exception 'invalid_group_selection';
      end if;
      select coalesce(array_agg(distinct value::uuid), array[]::uuid[])
        into v_ids
      from jsonb_array_elements_text(p_selections->v_group.id::text);
    end if;

    v_selected_count := coalesce(cardinality(v_ids), 0);
    if v_selected_count < v_group.min_selections
       or v_selected_count > v_group.max_selections then
      raise exception 'selection_limit_violation';
    end if;

    if v_selected_count > 0 then
      if exists (
        select 1
        from unnest(v_ids) selected(id)
        left join public.restaurant_menu_item_options o
          on o.id = selected.id
         and o.option_group_id = v_group.id
         and o.active = true
        where o.id is null
      ) then raise exception 'invalid_option_selection'; end if;

      select v_surcharge + coalesce(sum(o.price_delta), 0)
        into v_surcharge
      from public.restaurant_menu_item_options o
      where o.id = any(v_ids) and o.option_group_id = v_group.id and o.active = true;
    end if;
  end loop;

  if exists (
    select 1 from jsonb_object_keys(p_selections) as keys(group_id)
    where not exists (
      select 1 from public.restaurant_menu_item_option_groups g
      where g.id::text = keys.group_id and g.menu_item_id = p_menu_item_id and g.active = true
    )
  ) then raise exception 'unknown_option_group'; end if;

  return jsonb_build_object(
    'menu_item_id', p_menu_item_id,
    'currency', 'XOF',
    'base_price', v_base,
    'options_total', v_surcharge,
    'unit_total', v_base + v_surcharge
  );
end;
$$;

revoke all on function public.quote_restaurant_menu_item(uuid,jsonb) from public, anon, authenticated;
grant execute on function public.quote_restaurant_menu_item(uuid,jsonb) to anon, authenticated;




-- Prevent the generic product add RPC from silently merging an uncustomized
-- purchase into a restaurant line that already has selected options.
create or replace function public.guard_restaurant_cart_line_quantity()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.restaurant_menu_item_id is not null
     and new.quantity > old.quantity
     and coalesce(pg_catalog.current_setting('app.restaurant_menu_rpc', true), '') <> 'true'
     and coalesce(pg_catalog.current_setting('app.cart_quantity_rpc', true), '') <> 'true' then
    raise exception 'restaurant_item_requires_customization';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_restaurant_cart_line_quantity
  on public.cart_items;
create trigger trg_guard_restaurant_cart_line_quantity
before update of quantity on public.cart_items
for each row execute function public.guard_restaurant_cart_line_quantity();

-- The ordinary quantity editor may increase an already-customized line because
-- it preserves the same selections; mark that trusted RPC for this transaction.
do $patch$
declare
  v_definition text;
begin
  v_definition := pg_catalog.pg_get_functiondef(
    'public.set_cart_item_quantity(uuid,integer)'::regprocedure
  );
  if v_definition not like '%app.cart_quantity_rpc%' then
    v_definition := replace(
      v_definition,
      '  update public.cart_items' || chr(10) || '     set quantity = p_quantity',
      '  perform pg_catalog.set_config(''app.cart_quantity_rpc'', ''true'', true);'
        || chr(10) || '  update public.cart_items' || chr(10) || '     set quantity = p_quantity'
    );
    if v_definition not like '%app.cart_quantity_rpc%' then
      raise exception 'cart_quantity_rpc_guard_patch_failed';
    end if;
    execute v_definition;
  end if;
end;
$patch$;

-- Keep customization selections in the cart and immutable price/name snapshots on orders.
alter table public.cart_items
  add column if not exists restaurant_menu_item_id uuid
    references public.restaurant_menu_items(id) on delete set null,
  add column if not exists restaurant_selections jsonb not null default '{}'::jsonb;

alter table public.order_items
  add column if not exists restaurant_menu_item_id uuid
    references public.restaurant_menu_items(id) on delete set null,
  add column if not exists restaurant_customizations jsonb not null default '[]'::jsonb;

create or replace function public.add_restaurant_menu_item_to_cart(
  p_menu_item_id uuid,
  p_quantity integer,
  p_selections jsonb default '{}'::jsonb
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_product_id uuid;
  v_item_id uuid;
  v_existing_menu_item_id uuid;
  v_existing_selections jsonb;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 1000 then
    raise exception 'invalid_quantity';
  end if;
  if p_selections is null or jsonb_typeof(p_selections) <> 'object' then
    raise exception 'invalid_selections';
  end if;

  select mi.product_id into v_product_id
  from public.restaurant_menu_items mi
  join public.restaurant_menus m on m.id = mi.menu_id
  where mi.id = p_menu_item_id and mi.active = true and m.active = true
  for share;
  if v_product_id is null then
    raise exception 'restaurant_item_not_linked_to_product';
  end if;

  perform public.quote_restaurant_menu_item(p_menu_item_id, p_selections);

  select ci.id, ci.restaurant_menu_item_id, ci.restaurant_selections
    into v_item_id, v_existing_menu_item_id, v_existing_selections
  from public.carts c
  join public.cart_items ci on ci.cart_id = c.id
  where c.customer_id = v_user_id and c.status = 'ACTIVE'
    and ci.product_id = v_product_id and ci.variant_id is null
  for update of c, ci;

  if v_item_id is not null and (
    v_existing_menu_item_id is distinct from p_menu_item_id
    or v_existing_selections is distinct from p_selections
  ) then
    raise exception 'cart_item_customization_conflict';
  end if;

  perform pg_catalog.set_config('app.restaurant_menu_rpc', 'true', true);
  v_item_id := public.add_to_cart(v_product_id, p_quantity, null);

  update public.cart_items
  set restaurant_menu_item_id = p_menu_item_id,
      restaurant_selections = p_selections
  where id = v_item_id;

  return v_item_id;
end;
$$;

revoke all on function public.add_restaurant_menu_item_to_cart(uuid,integer,jsonb)
  from public, anon, authenticated;
grant execute on function public.add_restaurant_menu_item_to_cart(uuid,integer,jsonb)
  to authenticated;

create or replace function public.snapshot_restaurant_item_customizations()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_menu_item_id uuid;
  v_selections jsonb;
  v_quote jsonb;
  v_surcharge numeric := 0;
begin
  select o.customer_id into v_customer_id
  from public.order_groups og
  join public.orders o on o.id = og.order_id
  where og.id = new.order_group_id;

  select ci.restaurant_menu_item_id, ci.restaurant_selections
    into v_menu_item_id, v_selections
  from public.carts c
  join public.cart_items ci on ci.cart_id = c.id
  where c.customer_id = v_customer_id
    and c.status = 'ACTIVE'
    and ci.product_id = new.product_id
    and coalesce(ci.variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = coalesce(new.variant_id, '00000000-0000-0000-0000-000000000000'::uuid)
  limit 1;

  if v_menu_item_id is null then
    if coalesce(v_selections, '{}'::jsonb) <> '{}'::jsonb then
      raise exception 'restaurant_customization_unavailable';
    end if;
    new.restaurant_customizations := '[]'::jsonb;
    return new;
  end if;

  if not exists (
    select 1 from public.restaurant_menu_items mi
    where mi.id = v_menu_item_id and mi.product_id = new.product_id
  ) then
    raise exception 'restaurant_item_product_mismatch';
  end if;

  v_quote := public.quote_restaurant_menu_item(v_menu_item_id, v_selections);
  v_surcharge := coalesce((v_quote->>'options_total')::numeric, 0);
  new.restaurant_menu_item_id := v_menu_item_id;
  new.unit_price := new.unit_price + v_surcharge;
  new.total_price := new.unit_price * new.quantity;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'group_id', g.id,
        'group_name', g.name,
        'option_id', op.id,
        'option_name', op.name,
        'price_delta', op.price_delta
      ) order by g.sort_order, op.sort_order, op.id
    ),
    '[]'::jsonb
  ) into new.restaurant_customizations
  from jsonb_each(v_selections) as selected(group_id, option_ids)
  join public.restaurant_menu_item_option_groups g
    on g.id = selected.group_id::uuid and g.menu_item_id = v_menu_item_id
  cross join lateral jsonb_array_elements_text(selected.option_ids) as chosen(option_id)
  join public.restaurant_menu_item_options op
    on op.id = chosen.option_id::uuid and op.option_group_id = g.id
  where g.active = true and op.active = true;

  return new;
end;
$$;

drop trigger if exists trg_snapshot_restaurant_item_customizations
  on public.order_items;
create trigger trg_snapshot_restaurant_item_customizations
before insert on public.order_items
for each row execute function public.snapshot_restaurant_item_customizations();

create or replace function public.apply_restaurant_customization_totals()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_surcharge numeric := 0;
  v_order_id uuid;
begin
  select coalesce(sum((choice->>'price_delta')::numeric), 0) * new.quantity
    into v_surcharge
  from jsonb_array_elements(coalesce(new.restaurant_customizations, '[]'::jsonb)) as choices(choice);

  if v_surcharge <= 0 then return new; end if;

  update public.order_groups
  set subtotal = subtotal + v_surcharge
  where id = new.order_group_id
  returning order_id into v_order_id;

  update public.orders
  set subtotal = subtotal + v_surcharge,
      total = total + v_surcharge
  where id = v_order_id;

  return new;
end;
$$;

drop trigger if exists trg_apply_restaurant_customization_totals
  on public.order_items;
create trigger trg_apply_restaurant_customization_totals
after insert on public.order_items
for each row execute function public.apply_restaurant_customization_totals();

