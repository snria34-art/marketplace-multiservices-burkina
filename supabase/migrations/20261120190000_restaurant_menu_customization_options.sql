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
security definer
set search_path = pg_catalog, public
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
  if jsonb_typeof(p_options) <> 'array'
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
  for update of mi;
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
security definer
set search_path = pg_catalog, public
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

  v_base := v_item.price;

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
