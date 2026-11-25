-- Restaurant ordering: customer delivery/pickup choice, seller instructions and status flow.
begin;

alter table public.restaurant_profiles
  add column if not exists pickup_available boolean not null default true;

alter table public.carts
  add column if not exists restaurant_fulfillment_method text not null default 'DELIVERY'
    check (restaurant_fulfillment_method in ('DELIVERY', 'PICKUP')),
  add column if not exists restaurant_customer_instructions text;

alter table public.order_groups
  add column if not exists fulfillment_method text not null default 'DELIVERY'
    check (fulfillment_method in ('DELIVERY', 'PICKUP')),
  add column if not exists fulfillment_instructions text,
  add column if not exists pickup_location jsonb;

alter table public.order_packages
  add column if not exists fulfillment_method text not null default 'DELIVERY'
    check (fulfillment_method in ('DELIVERY', 'PICKUP'));

comment on column public.carts.restaurant_fulfillment_method is
  'Customer choice for a single-restaurant cart: delivery or pickup.';
comment on column public.order_groups.fulfillment_method is
  'Fulfilment choice captured when checkout creates the restaurant order group.';
comment on column public.order_groups.pickup_location is
  'Immutable restaurant pickup location snapshot for pickup orders.';

create or replace function public.get_restaurant_cart_context(
  p_cart_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_total_items integer := 0;
  v_valid_items integer := 0;
  v_restaurant_count integer := 0;
  v_context jsonb;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  perform 1
  from public.carts c
  where c.id = p_cart_id
    and c.customer_id = v_user
    and c.status = 'ACTIVE';
  if not found then
    raise exception 'cart_not_active_or_not_owned' using errcode = '42501';
  end if;

  select count(*) into v_total_items
  from public.cart_items ci
  where ci.cart_id = p_cart_id;

  select count(*), count(distinct rp.id)
    into v_valid_items, v_restaurant_count
  from public.cart_items ci
  join public.restaurant_menu_items mi
    on mi.id = ci.restaurant_menu_item_id
   and mi.product_id = ci.product_id
  join public.restaurant_menus rm on rm.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = rm.restaurant_id
  join public.shops sh on sh.id = rp.shop_id
  where ci.cart_id = p_cart_id
    and mi.active = true
    and rm.active = true
    and sh.status = 'ACTIVE'
    and sh.verification_status = 'VERIFIED';

  if v_total_items = 0
     or v_valid_items <> v_total_items
     or v_restaurant_count <> 1 then
    return jsonb_build_object('is_restaurant_cart', false);
  end if;

  select jsonb_build_object(
    'is_restaurant_cart', true,
    'restaurant_id', rp.id,
    'shop_id', sh.id,
    'restaurant_name', sh.name,
    'pickup_address', sh.address,
    'restaurant_phone', sh.phone,
    'preparation_time_min', rp.preparation_time_min,
    'delivery_available', rp.delivery_available,
    'pickup_available', rp.pickup_available,
    'fulfillment_method', c.restaurant_fulfillment_method,
    'customer_instructions', c.restaurant_customer_instructions
  )
  into v_context
  from public.carts c
  join public.cart_items ci on ci.cart_id = c.id
  join public.restaurant_menu_items mi
    on mi.id = ci.restaurant_menu_item_id
   and mi.product_id = ci.product_id
  join public.restaurant_menus rm on rm.id = mi.menu_id
  join public.restaurant_profiles rp on rp.id = rm.restaurant_id
  join public.shops sh on sh.id = rp.shop_id
  where c.id = p_cart_id
  limit 1;

  return coalesce(v_context, jsonb_build_object('is_restaurant_cart', false));
end;
$$;

revoke all on function public.get_restaurant_cart_context(uuid)
  from public, anon, authenticated;
grant execute on function public.get_restaurant_cart_context(uuid)
  to authenticated;

create or replace function public.set_restaurant_cart_fulfillment(
  p_cart_id uuid,
  p_fulfillment_method text,
  p_customer_instructions text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_method text := upper(trim(coalesce(p_fulfillment_method, '')));
  v_instructions text := nullif(trim(coalesce(p_customer_instructions, '')), '');
  v_context jsonb;
begin
  perform private.require_active_account();

  if v_method not in ('DELIVERY', 'PICKUP') then
    raise exception 'invalid_restaurant_fulfillment_method'
      using errcode = '22023';
  end if;
  if length(coalesce(v_instructions, '')) > 500 then
    raise exception 'restaurant_instructions_too_long'
      using errcode = '22023';
  end if;

  v_context := public.get_restaurant_cart_context(p_cart_id);
  if coalesce((v_context ->> 'is_restaurant_cart')::boolean, false) is not true then
    if v_method = 'PICKUP' then
      raise exception 'cart_must_contain_one_restaurant_only'
        using errcode = '22023';
    end if;

    update public.carts
    set restaurant_fulfillment_method = 'DELIVERY',
        restaurant_customer_instructions = null,
        updated_at = now()
    where id = p_cart_id
      and customer_id = auth.uid()
      and status = 'ACTIVE';

    return jsonb_build_object(
      'is_restaurant_cart', false,
      'fulfillment_method', 'DELIVERY'
    );
  end if;

  if v_method = 'PICKUP'
     and coalesce((v_context ->> 'pickup_available')::boolean, false) is not true then
    raise exception 'restaurant_pickup_unavailable'
      using errcode = '22023';
  end if;
  if v_method = 'DELIVERY'
     and coalesce((v_context ->> 'delivery_available')::boolean, false) is not true then
    raise exception 'restaurant_delivery_unavailable'
      using errcode = '22023';
  end if;

  update public.carts
  set restaurant_fulfillment_method = v_method,
      restaurant_customer_instructions = v_instructions,
      updated_at = now()
  where id = p_cart_id
    and customer_id = auth.uid()
    and status = 'ACTIVE';

  return v_context || jsonb_build_object(
    'fulfillment_method', v_method,
    'customer_instructions', v_instructions
  );
end;
$$;

revoke all on function public.set_restaurant_cart_fulfillment(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.set_restaurant_cart_fulfillment(uuid, text, text)
  to authenticated;

-- Extend the existing, hardened checkout without replacing its stock,
-- coupon, idempotency, address-ownership or server-side delivery-fee guards.
do $migration$
declare
  v_def text;
  v_anchor text;
  v_address_start text;
  v_address_end text;
  v_fee_block text;
  v_group_block text;
  v_package_block text;
begin
  v_def := pg_get_functiondef(
    'public.checkout_cart(uuid,jsonb,numeric,text,text)'::regprocedure
  );

  v_anchor := '  v_delivery_address jsonb;';
  if position(v_anchor in v_def) = 0 then
    raise exception 'restaurant_checkout_declaration_anchor_missing';
  end if;
  v_def := replace(v_def, v_anchor, v_anchor || E'\n'
    || '  v_fulfillment_method text := ''DELIVERY'';' || E'\n'
    || '  v_fulfillment_instructions text;' || E'\n'
    || '  v_pickup_location jsonb;' || E'\n'
    || '  v_total_cart_items integer := 0;' || E'\n'
    || '  v_restaurant_cart_items integer := 0;' || E'\n'
    || '  v_restaurant_count integer := 0;');

  v_anchor := E'  if not found then\n    raise exception ''cart_not_active_or_not_owned'';\n  end if;\n\n  select nullif(trim(p_delivery_address ->> ''id''), '''')::uuid\n    into v_address_id;';
  if position(v_anchor in v_def) = 0 then
    raise exception 'restaurant_checkout_cart_lock_anchor_missing';
  end if;
  v_def := replace(v_def, v_anchor,
    E'  if not found then\n    raise exception ''cart_not_active_or_not_owned'';\n  end if;\n\n'
    || E'  select coalesce(c.restaurant_fulfillment_method, ''DELIVERY''),\n'
    || E'         c.restaurant_customer_instructions\n'
    || E'    into v_fulfillment_method, v_fulfillment_instructions\n'
    || E'  from public.carts c\n'
    || E'  where c.id = p_cart_id and c.customer_id = v_user and c.status = ''ACTIVE'';\n'
    || E'  if v_fulfillment_method not in (''DELIVERY'', ''PICKUP'') then\n'
    || E'    raise exception ''invalid_restaurant_fulfillment_method'';\n'
    || E'  end if;\n\n'
    || E'  if v_fulfillment_method = ''PICKUP'' then\n'
    || E'    select count(*) into v_total_cart_items\n'
    || E'    from public.cart_items ci where ci.cart_id = p_cart_id;\n'
    || E'    select count(*), count(distinct rp.id)\n'
    || E'      into v_restaurant_cart_items, v_restaurant_count\n'
    || E'    from public.cart_items ci\n'
    || E'    join public.restaurant_menu_items mi\n'
    || E'      on mi.id = ci.restaurant_menu_item_id and mi.product_id = ci.product_id\n'
    || E'    join public.restaurant_menus rm on rm.id = mi.menu_id\n'
    || E'    join public.restaurant_profiles rp on rp.id = rm.restaurant_id\n'
    || E'    join public.shops sh on sh.id = rp.shop_id\n'
    || E'    where ci.cart_id = p_cart_id and mi.active = true and rm.active = true\n'
    || E'      and rp.pickup_available = true and sh.status = ''ACTIVE''\n'
    || E'      and sh.verification_status = ''VERIFIED'';\n'
    || E'    if v_total_cart_items = 0 or v_restaurant_cart_items <> v_total_cart_items\n'
    || E'       or v_restaurant_count <> 1 then\n'
    || E'      raise exception ''pickup_requires_one_restaurant_cart'';\n'
    || E'    end if;\n'
    || E'    select jsonb_build_object(\n'
    || E'      ''restaurant_id'', rp.id, ''shop_id'', sh.id,\n'
    || E'      ''restaurant_name'', sh.name, ''address'', sh.address,\n'
    || E'      ''phone'', sh.phone, ''preparation_time_min'', rp.preparation_time_min\n'
    || E'    ) into v_pickup_location\n'
    || E'    from public.cart_items ci\n'
    || E'    join public.restaurant_menu_items mi on mi.id = ci.restaurant_menu_item_id\n'
    || E'    join public.restaurant_menus rm on rm.id = mi.menu_id\n'
    || E'    join public.restaurant_profiles rp on rp.id = rm.restaurant_id\n'
    || E'    join public.shops sh on sh.id = rp.shop_id\n'
    || E'    where ci.cart_id = p_cart_id limit 1;\n'
    || E'    v_delivery_address := v_pickup_location || jsonb_build_object(\n'
    || E'      ''fulfillment_method'', ''PICKUP'',\n'
    || E'      ''instructions'', v_fulfillment_instructions\n'
    || E'    );\n'
    || E'  else\n'
    || E'    if exists (\n'
    || E'      select 1 from public.cart_items ci\n'
    || E'      join public.restaurant_menu_items mi on mi.id = ci.restaurant_menu_item_id\n'
    || E'      join public.restaurant_menus rm on rm.id = mi.menu_id\n'
    || E'      join public.restaurant_profiles rp on rp.id = rm.restaurant_id\n'
    || E'      where ci.cart_id = p_cart_id and rp.delivery_available = false\n'
    || E'    ) then\n'
    || E'      raise exception ''restaurant_delivery_unavailable'';\n'
    || E'    end if;\n'
    || E'    select nullif(trim(p_delivery_address ->> ''id''), '''')::uuid\n'
    || E'      into v_address_id;');

  v_anchor := E'  if v_delivery_address is null then\n    raise exception ''delivery_address_not_owned'';\n  end if;';
  if position(v_anchor in v_def) = 0 then
    raise exception 'restaurant_checkout_address_ownership_anchor_missing';
  end if;
  v_def := replace(v_def, v_anchor,
    v_anchor || E'\n'
    || E'    v_delivery_address := v_delivery_address || jsonb_build_object(\n'
    || E'      ''fulfillment_method'', ''DELIVERY'',\n'
    || E'      ''instructions'', v_fulfillment_instructions\n'
    || E'    );\n'
    || E'  end if;');

  v_fee_block := E'  select (public.calculate_delivery_fee(\n'
    || E'    p_cart_id,\n'
    || E'    jsonb_build_object(\n'
    || E'      ''latitude'', v_delivery_address ->> ''latitude'',\n'
    || E'      ''longitude'', v_delivery_address ->> ''longitude''\n'
    || E'    )\n'
    || E'  ) ->> ''customer_fee'')::numeric\n'
    || E'    into v_delivery_fee_server;';
  if position(v_fee_block in v_def) = 0 then
    raise exception 'restaurant_checkout_server_delivery_fee_anchor_missing';
  end if;
  v_def := replace(v_def, v_fee_block,
    E'  if v_fulfillment_method = ''PICKUP'' then\n'
    || E'    v_delivery_fee_server := 0;\n'
    || E'  else\n'
    || v_fee_block || E'\n'
    || E'  end if;');

  v_group_block := E'      insert into public.order_groups(\n'
    || E'        order_id,\n'
    || E'        shop_id,\n'
    || E'        status,\n'
    || E'        subtotal\n'
    || E'      )\n'
    || E'      values(\n'
    || E'        v_order,\n'
    || E'        v_item.shop_id,\n'
    || E'        ''PENDING_PAYMENT'',\n'
    || E'        0\n'
    || E'      )';
  if position(v_group_block in v_def) = 0 then
    raise exception 'restaurant_checkout_order_group_anchor_missing';
  end if;
  v_def := replace(v_def, v_group_block,
    E'      insert into public.order_groups(\n'
    || E'        order_id, shop_id, status, subtotal,\n'
    || E'        fulfillment_method, fulfillment_instructions, pickup_location\n'
    || E'      )\n'
    || E'      values(\n'
    || E'        v_order, v_item.shop_id, ''PENDING_PAYMENT'', 0,\n'
    || E'        v_fulfillment_method, v_fulfillment_instructions,\n'
    || E'        case when v_fulfillment_method = ''PICKUP'' then v_pickup_location else null end\n'
    || E'      )');

  v_package_block := E'      insert into public.order_packages(\n'
    || E'        order_group_id,\n'
    || E'        status\n'
    || E'      )\n'
    || E'      values(\n'
    || E'        v_group_id,\n'
    || E'        ''CREATED''\n'
    || E'      )\n'
    || E'      returning id into v_package_id;';
  if position(v_package_block in v_def) = 0 then
    raise exception 'restaurant_checkout_package_anchor_missing';
  end if;
  v_def := replace(v_def, v_package_block,
    E'      insert into public.order_packages(\n'
    || E'        order_group_id, status, fulfillment_method\n'
    || E'      )\n'
    || E'      values(\n'
    || E'        v_group_id, ''CREATED'', v_fulfillment_method\n'
    || E'      )\n'
    || E'      returning id into v_package_id;');

  if position('v_fulfillment_method' in v_def) = 0
     or position('reserve_variant_inventory' in v_def) = 0
     or position('calculate_delivery_fee' in v_def) = 0
     or position('delivery_address_not_owned' in v_def) = 0 then
    raise exception 'restaurant_checkout_guard_verification_failed';
  end if;

  execute v_def;
end;
$migration$;

create or replace function public.capture_restaurant_order_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event_status text;
  v_seller_user uuid;
  v_order_id uuid;
begin
  select se.user_id, og.order_id
    into v_seller_user, v_order_id
  from public.shops sh
  join public.sellers se on se.id = sh.seller_id
  join public.order_groups og on og.shop_id = sh.id
  where sh.id = new.shop_id
    and og.id = new.id;

  if v_seller_user is null then
    return new;
  end if;
  if not exists (
    select 1 from public.restaurant_profiles rp
    where rp.shop_id = new.shop_id
  ) then
    return new;
  end if;

  v_event_status := case new.status::text
    when 'PAID' then 'RECEIVED'
    when 'CONFIRMED' then 'CONFIRMED'
    when 'PREPARING' then 'PREPARING'
    when 'READY_FOR_PICKUP' then 'READY'
    when 'IN_TRANSIT' then 'IN_DELIVERY'
    when 'DELIVERED' then 'DELIVERED'
    when 'CANCELLED' then 'CANCELLED'
    else null
  end;

  if v_event_status is not null then
    insert into public.restaurant_order_events(order_group_id, status)
    values (new.id, v_event_status);
  end if;

  if new.status::text = 'PAID' then
    insert into public.notifications(user_id, type, title, body, data)
    values (
      v_seller_user,
      'restaurant_order_received',
      'Nouvelle commande restaurant',
      'Une nouvelle commande payée attend votre confirmation.',
      jsonb_build_object(
        'order_id', v_order_id::text,
        'order_group_id', new.id::text,
        'fulfillment_method', new.fulfillment_method,
        'type', 'restaurant_order_received'
      )
    );
  end if;

  return new;
end;
$$;

revoke all on function public.capture_restaurant_order_event()
  from public, anon, authenticated;

drop trigger if exists trg_capture_restaurant_order_event
  on public.order_groups;
create trigger trg_capture_restaurant_order_event
after update of status on public.order_groups
for each row
when (old.status is distinct from new.status)
execute function public.capture_restaurant_order_event();

create or replace function public.get_seller_restaurant_order_fulfillment_details()
returns table (
  order_group_id uuid,
  delivery_address jsonb
)
language sql
stable
security definer
set search_path = ''
as $
  select og.id, o.delivery_address
  from public.order_groups og
  join public.orders o on o.id = og.order_id
  join public.shops sh on sh.id = og.shop_id
  join public.sellers se on se.id = sh.seller_id
  join public.restaurant_profiles rp on rp.shop_id = sh.id
  where se.user_id = auth.uid()
  order by og.created_at desc;
$;

revoke all on function public.get_seller_restaurant_order_fulfillment_details()
  from public, anon, authenticated;
grant execute on function public.get_seller_restaurant_order_fulfillment_details()
  to authenticated;

create or replace function public.transition_restaurant_order_group_status(
  p_order_group_id uuid,
  p_next_status public.order_status,
  p_note text default null
) returns public.order_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_current_status text;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_next_status is null
     or p_next_status::text not in ('CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP') then
    raise exception 'unsupported_restaurant_transition' using errcode = '22023';
  end if;
  if length(coalesce(p_note, '')) > 500 then
    raise exception 'restaurant_order_note_too_long' using errcode = '22023';
  end if;

  select og.order_id, og.status::text
    into v_order_id, v_current_status
  from public.order_groups og
  join public.shops sh on sh.id = og.shop_id
  join public.sellers se on se.id = sh.seller_id
  join public.restaurant_profiles rp on rp.shop_id = sh.id
  where og.id = p_order_group_id
    and se.user_id = v_user
  for update of og;

  if not found then
    raise exception 'restaurant_order_not_found_or_not_owned'
      using errcode = '42501';
  end if;

  if (v_current_status = 'PAID' and p_next_status::text <> 'CONFIRMED')
     or (v_current_status = 'CONFIRMED' and p_next_status::text <> 'PREPARING')
     or (v_current_status = 'PREPARING' and p_next_status::text <> 'READY_FOR_PICKUP')
     or v_current_status not in ('PAID', 'CONFIRMED', 'PREPARING') then
    raise exception 'invalid_restaurant_order_transition'
      using errcode = '22023';
  end if;

  update public.order_groups
  set status = p_next_status
  where id = p_order_group_id;

  -- Keep the parent order and its customer notifications in sync with the restaurant.
  perform public.sync_parent_order_status(v_order_id);

  insert into public.order_events(order_id, actor_id, status, metadata)
  values (
    v_order_id,
    v_user,
    p_next_status,
    jsonb_build_object(
      'scope', 'restaurant_order_group',
      'order_group_id', p_order_group_id,
      'note', nullif(trim(coalesce(p_note, '')), '')
    )
  );

  return p_next_status;
end;
$$;

revoke all on function public.transition_restaurant_order_group_status(uuid, public.order_status, text)
  from public, anon, authenticated;
grant execute on function public.transition_restaurant_order_group_status(uuid, public.order_status, text)
  to authenticated;


create or replace function public.confirm_restaurant_customer_pickup(
  p_order_group_id uuid
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_order_id uuid;
  v_group_status text;
  v_fulfillment_method text;
  v_package_id uuid;
begin
  perform private.require_active_account();
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  select og.order_id, og.status::text, og.fulfillment_method
    into v_order_id, v_group_status, v_fulfillment_method
  from public.order_groups og
  join public.shops sh on sh.id = og.shop_id
  join public.sellers se on se.id = sh.seller_id
  join public.restaurant_profiles rp on rp.shop_id = sh.id
  where og.id = p_order_group_id
    and se.user_id = v_user
  for update of og;

  if not found then
    raise exception 'restaurant_order_not_found_or_not_owned'
      using errcode = '42501';
  end if;
  if v_fulfillment_method <> 'PICKUP' then
    raise exception 'customer_pickup_not_applicable'
      using errcode = '22023';
  end if;
  if v_group_status <> 'READY_FOR_PICKUP' then
    raise exception 'restaurant_order_not_ready_for_pickup'
      using errcode = '22023';
  end if;

  select op.id into v_package_id
  from public.order_packages op
  where op.order_group_id = p_order_group_id
    and op.fulfillment_method = 'PICKUP'
    and op.status = 'CREATED'
  for update;

  if v_package_id is null then
    raise exception 'restaurant_pickup_record_not_found'
      using errcode = 'P0002';
  end if;

  update public.order_packages
  set status = 'DELIVERED',
      delivered_at = coalesce(delivered_at, now()),
      updated_at = now()
  where id = v_package_id;

  insert into public.order_events(order_id, actor_id, status, metadata)
  values (
    v_order_id,
    v_user,
    'DELIVERED',
    jsonb_build_object(
      'scope', 'restaurant_customer_pickup',
      'order_group_id', p_order_group_id,
      'package_id', v_package_id
    )
  );

  return true;
end;
$$;

revoke all on function public.confirm_restaurant_customer_pickup(uuid)
  from public, anon, authenticated;
grant execute on function public.confirm_restaurant_customer_pickup(uuid)
  to authenticated;

create or replace function public.guard_restaurant_pickup_assignment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1
    from public.order_packages op
    where op.id = new.package_id
      and op.fulfillment_method = 'PICKUP'
  ) then
    raise exception 'restaurant_pickup_cannot_be_courier_assigned'
      using errcode = '22023';
  end if;
  return new;
end;
$$;

revoke all on function public.guard_restaurant_pickup_assignment()
  from public, anon, authenticated;

drop trigger if exists trg_guard_restaurant_pickup_assignment
  on public.delivery_assignments;
create trigger trg_guard_restaurant_pickup_assignment
before insert or update of package_id on public.delivery_assignments
for each row
execute function public.guard_restaurant_pickup_assignment();

commit;
