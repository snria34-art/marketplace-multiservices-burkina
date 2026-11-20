-- Real product-linked components for restaurant meal formulas.
-- Component choices reuse the existing server-quoted option-group and order snapshot flow.
alter table public.restaurant_menu_item_option_groups
  add column if not exists component_type text not null default 'CUSTOM'
  check (component_type in ('CUSTOM', 'MAIN', 'DRINK', 'DESSERT', 'SIDE'));

alter table public.restaurant_menu_item_options
  add column if not exists linked_product_id uuid
  references public.products(id) on delete set null;

create index if not exists idx_restaurant_options_linked_product
  on public.restaurant_menu_item_options(linked_product_id)
  where linked_product_id is not null;

-- Formula component choices must be real active products from the same restaurant shop.
-- The existing save RPC validates seller ownership and atomically creates option rows.
create or replace function public.save_restaurant_formula_component(
  p_menu_item_id uuid,
  p_name text,
  p_component_type text,
  p_options jsonb,
  p_group_id uuid default null
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_type text := upper(trim(coalesce(p_component_type, '')));
  v_options jsonb := '[]'::jsonb;
  v_row jsonb;
  v_product_id uuid;
  v_group_id uuid;
  v_index integer := 0;
  v_shop_id uuid;
begin
  if v_type not in ('MAIN', 'DRINK', 'DESSERT', 'SIDE') then
    raise exception 'invalid_formula_component_type';
  end if;
  if p_options is null or jsonb_typeof(p_options) <> 'array'
     or jsonb_array_length(p_options) < 1
     or jsonb_array_length(p_options) > 30 then
    raise exception 'invalid_formula_component_options';
  end if;

  select rp.shop_id into v_shop_id
  from public.restaurant_menu_items mi
  join public.restaurant_menus m on m.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = m.restaurant_id
  join public.shops s on s.id = rp.shop_id
  join public.sellers se on se.id = s.seller_id
  where mi.id = p_menu_item_id and se.user_id = auth.uid();
  if v_shop_id is null then raise exception 'menu_item_not_owned'; end if;

  for v_row in select value from jsonb_array_elements(p_options)
  loop
    v_index := v_index + 1;
    begin
      v_product_id := (v_row->>'product_id')::uuid;
    exception when others then
      raise exception 'formula_component_product_required';
    end;
    if not exists (
      select 1 from public.products p
      where p.id = v_product_id and p.shop_id = v_shop_id and p.status = 'ACTIVE'
    ) then
      raise exception 'formula_component_product_unavailable';
    end if;
    v_options := v_options || jsonb_build_array(jsonb_build_object(
      'name', coalesce(nullif(trim(v_row->>'name'), ''), 'Produit'),
      'price_delta', coalesce(nullif(v_row->>'price_delta', '')::numeric, 0)
    ));
  end loop;

  v_group_id := public.save_restaurant_item_option_group(
    p_menu_item_id,
    p_name,
    'SINGLE',
    1,
    1,
    v_options,
    p_group_id
  );

  update public.restaurant_menu_item_option_groups
  set component_type = v_type
  where id = v_group_id and menu_item_id = p_menu_item_id;

  v_index := 0;
  for v_row in select value from jsonb_array_elements(p_options)
  loop
    v_index := v_index + 1;
    update public.restaurant_menu_item_options
    set linked_product_id = (v_row->>'product_id')::uuid
    where option_group_id = v_group_id and sort_order = v_index;
  end loop;

  return v_group_id;
end;
$$;

revoke all on function public.save_restaurant_formula_component(uuid,text,text,jsonb,uuid)
  from public, anon, authenticated;
grant execute on function public.save_restaurant_formula_component(uuid,text,text,jsonb,uuid)
  to authenticated;

comment on column public.restaurant_menu_item_option_groups.component_type is
  'CUSTOM or a real formula component slot: MAIN, DRINK, DESSERT, SIDE.';
comment on column public.restaurant_menu_item_options.linked_product_id is
  'Optional active product from the same shop; required for formula component choices.';
