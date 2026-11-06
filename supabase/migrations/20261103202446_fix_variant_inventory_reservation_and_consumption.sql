create table if not exists public.product_variant_inventory (
  variant_id uuid primary key references public.product_variants(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  quantity integer not null default 0,
  reserved_quantity integer not null default 0,
  updated_at timestamptz not null default now(),
  constraint product_variant_inventory_quantity_nonnegative check (quantity >= 0),
  constraint product_variant_inventory_reserved_nonnegative check (reserved_quantity >= 0),
  constraint product_variant_inventory_reserved_lte_quantity check (reserved_quantity <= quantity)
);

create index if not exists product_variant_inventory_product_id_idx
  on public.product_variant_inventory(product_id);

alter table public.product_variant_inventory enable row level security;
revoke all on table public.product_variant_inventory from anon, authenticated;

create or replace function public.get_available_variant_stock(
  p_product_id uuid,
  p_variant_id uuid default null
) returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_available integer; v_variant_product uuid;
begin
  if p_variant_id is not null then
    select pv.product_id into v_variant_product
    from public.product_variants pv where pv.id = p_variant_id;
    if v_variant_product is null or v_variant_product <> p_product_id then
      raise exception 'invalid_variant' using errcode = '22023';
    end if;
    select vi.quantity - vi.reserved_quantity into v_available
    from public.product_variant_inventory vi
    where vi.variant_id = p_variant_id and vi.product_id = p_product_id;
    if found then return v_available; end if;
  end if;
  select i.quantity - i.reserved_quantity into v_available
  from public.inventory i where i.product_id = p_product_id;
  return v_available;
end;
$$;

create or replace function public.reserve_variant_inventory(
  p_product_id uuid, p_variant_id uuid, p_quantity integer
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_variant_product uuid; v_has_variant_stock boolean; v_rows integer;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'quantity_must_be_positive' using errcode = '22023';
  end if;
  if p_variant_id is null then
    return public.reserve_inventory(p_product_id, p_quantity);
  end if;
  select pv.product_id into v_variant_product
  from public.product_variants pv where pv.id = p_variant_id for update;
  if v_variant_product is null or v_variant_product <> p_product_id then
    raise exception 'invalid_variant' using errcode = '22023';
  end if;
  select exists (select 1 from public.product_variant_inventory vi where vi.variant_id = p_variant_id)
    into v_has_variant_stock;
  if not v_has_variant_stock then
    return public.reserve_inventory(p_product_id, p_quantity);
  end if;
  update public.product_variant_inventory vi
  set reserved_quantity = vi.reserved_quantity + p_quantity, updated_at = now()
  where vi.variant_id = p_variant_id and vi.product_id = p_product_id
    and vi.quantity - vi.reserved_quantity >= p_quantity;
  get diagnostics v_rows = row_count;
  return v_rows = 1;
end;
$$;

create or replace function public.consume_variant_inventory(
  p_product_id uuid, p_variant_id uuid, p_quantity integer
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_variant_product uuid; v_has_variant_stock boolean; v_rows integer;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'quantity_must_be_positive' using errcode = '22023';
  end if;
  if p_variant_id is null then
    return public.consume_reserved_inventory(p_product_id, p_quantity);
  end if;
  select pv.product_id into v_variant_product
  from public.product_variants pv where pv.id = p_variant_id;
  if v_variant_product is null or v_variant_product <> p_product_id then
    raise exception 'invalid_variant' using errcode = '22023';
  end if;
  select exists (select 1 from public.product_variant_inventory vi where vi.variant_id = p_variant_id)
    into v_has_variant_stock;
  if not v_has_variant_stock then
    return public.consume_reserved_inventory(p_product_id, p_quantity);
  end if;
  update public.product_variant_inventory vi
  set quantity = vi.quantity - p_quantity,
      reserved_quantity = vi.reserved_quantity - p_quantity,
      updated_at = now()
  where vi.variant_id = p_variant_id and vi.product_id = p_product_id
    and vi.reserved_quantity >= p_quantity and vi.quantity >= p_quantity;
  get diagnostics v_rows = row_count;
  return v_rows = 1;
end;
$$;

create or replace function public.set_seller_variant_stock(
  p_variant_id uuid, p_quantity integer
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_user uuid := auth.uid(); v_product_id uuid; v_reserved integer;
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated' using errcode = '42501'; end if;
  if p_variant_id is null or p_quantity is null or p_quantity < 0 or p_quantity > 1000000 then
    raise exception 'stock_invalid' using errcode = '22023';
  end if;
  select pv.product_id into v_product_id
  from public.product_variants pv
  join public.products p on p.id = pv.product_id
  join public.shops sh on sh.id = p.shop_id
  join public.sellers se on se.id = sh.seller_id
  where pv.id = p_variant_id and se.user_id = v_user
  for update of pv;
  if v_product_id is null then raise exception 'variant_not_owned' using errcode = '42501'; end if;
  select vi.reserved_quantity into v_reserved
  from public.product_variant_inventory vi where vi.variant_id = p_variant_id for update;
  if not found then
    insert into public.product_variant_inventory(variant_id,product_id,quantity,reserved_quantity)
    values(p_variant_id,v_product_id,p_quantity,0);
  else
    if p_quantity < v_reserved then raise exception 'stock_below_reserved' using errcode = '22023'; end if;
    update public.product_variant_inventory
    set quantity=p_quantity,updated_at=now()
    where variant_id=p_variant_id and product_id=v_product_id;
  end if;
end;
$$;

revoke all on function public.get_available_variant_stock(uuid,uuid) from public, anon, authenticated;
revoke all on function public.reserve_variant_inventory(uuid,uuid,integer) from public, anon, authenticated;
revoke all on function public.consume_variant_inventory(uuid,uuid,integer) from public, anon, authenticated;
revoke all on function public.set_seller_variant_stock(uuid,integer) from public, anon;
grant execute on function public.set_seller_variant_stock(uuid,integer) to authenticated;

do $migration$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.add_to_cart(uuid,integer,uuid)'::regprocedure);
  v_def := replace(v_def,
    'select (i.quantity - i.reserved_quantity)
    into v_available
  from public.inventory i
  where i.product_id = p_product_id
  for share;',
    'select public.get_available_variant_stock(p_product_id, p_variant_id)
    into v_available;');
  if v_def not like '%get_available_variant_stock(p_product_id, p_variant_id)%' then
    raise exception 'add_to_cart_stock_patch_failed';
  end if;
  execute v_def;

  v_def := pg_get_functiondef('public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure);
  v_def := replace(v_def,
    'select public.reserve_inventory(
      v_item.product_id,
      v_item.quantity
    ) into v_reserved;',
    'select public.reserve_variant_inventory(
      v_item.product_id,
      v_item.variant_id,
      v_item.quantity
    ) into v_reserved;');
  if v_def not like '%reserve_variant_inventory%' then raise exception 'checkout_cart_stock_patch_failed'; end if;
  execute v_def;

  v_def := pg_get_functiondef('public.checkout_active_cart(uuid,numeric,jsonb)'::regprocedure);
  v_def := replace(v_def,
    'if not public.reserve_inventory(v_item.product_id,v_item.quantity) then raise exception ''insufficient_inventory''; end if;',
    'if not public.reserve_variant_inventory(v_item.product_id,v_item.variant_id,v_item.quantity) then raise exception ''insufficient_inventory''; end if;');
  if v_def not like '%reserve_variant_inventory%' then raise exception 'checkout_active_cart_stock_patch_failed'; end if;
  execute v_def;

  v_def := pg_get_functiondef('public.consume_order_inventory(uuid)'::regprocedure);
  v_def := replace(v_def,'select oi.product_id,oi.quantity','select oi.product_id,oi.variant_id,oi.quantity');
  v_def := replace(v_def,
    'perform public.consume_reserved_inventory(v_item.product_id,v_item.quantity);',
    'if not public.consume_variant_inventory(v_item.product_id,v_item.variant_id,v_item.quantity) then raise exception ''reserved_inventory_insufficient''; end if;');
  if v_def not like '%consume_variant_inventory%' then raise exception 'consume_order_inventory_stock_patch_failed'; end if;
  execute v_def;

  v_def := pg_get_functiondef('public.consume_package_inventory(uuid)'::regprocedure);
  v_def := replace(v_def,'select oi.product_id,oi.quantity','select oi.product_id,oi.variant_id,oi.quantity');
  v_def := replace(v_def,
    'if not public.consume_reserved_inventory(v_item.product_id,v_item.quantity) then',
    'if not public.consume_variant_inventory(v_item.product_id,v_item.variant_id,v_item.quantity) then');
  if v_def not like '%consume_variant_inventory%' then raise exception 'consume_package_inventory_stock_patch_failed'; end if;
  execute v_def;
end;
$migration$;
