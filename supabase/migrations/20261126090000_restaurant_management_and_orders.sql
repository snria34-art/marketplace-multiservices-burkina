-- Restaurant partner management: profile settings, menu ownership and safe order workflow.
-- Additive migration; it does not modify the shared seller/cart/checkout state machines.

alter table public.restaurant_profiles
  add column if not exists accepting_orders boolean not null default true,
  add column if not exists pickup_available boolean not null default true,
  add column if not exists minimum_order_amount numeric(14,2) not null default 0,
  add column if not exists opening_hours text not null default '';

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.restaurant_profiles'::regclass
      and conname = 'restaurant_minimum_order_nonnegative'
  ) then
    alter table public.restaurant_profiles
      add constraint restaurant_minimum_order_nonnegative
      check (minimum_order_amount >= 0);
  end if;
end;
$migration$;

create index if not exists idx_restaurant_profiles_shop
  on public.restaurant_profiles(shop_id);

create index if not exists idx_restaurant_menus_restaurant_active_sort
  on public.restaurant_menus(restaurant_id, active, sort_order);

create index if not exists idx_restaurant_menu_items_menu_active_sort
  on public.restaurant_menu_items(menu_id, active, sort_order);

grant select on public.restaurant_profiles,
                public.restaurant_menus,
                public.restaurant_menu_items
to anon, authenticated;

grant insert, update, delete on public.restaurant_profiles,
                                  public.restaurant_menus,
                                  public.restaurant_menu_items
to authenticated;

grant select on public.restaurant_order_events to authenticated;

-- A restaurant partner can manage only restaurants attached to their own shop.
-- A restaurant account must have the RESTAURANT role; existing SELLER accounts
-- can also operate a restaurant attached to their own seller/shop record.
drop policy if exists restaurant_profiles_owner_manage
  on public.restaurant_profiles;
create policy restaurant_profiles_owner_manage
on public.restaurant_profiles
for all
to authenticated
using (
  exists (
    select 1
    from public.shops sh
    join public.sellers s on s.id = sh.seller_id
    where sh.id = restaurant_profiles.shop_id
      and s.user_id = (select auth.uid())
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role::text in ('SELLER', 'RESTAURANT')
      )
  )
)
with check (
  exists (
    select 1
    from public.shops sh
    join public.sellers s on s.id = sh.seller_id
    where sh.id = restaurant_profiles.shop_id
      and s.user_id = (select auth.uid())
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role::text in ('SELLER', 'RESTAURANT')
      )
  )
);

-- Public clients see menus and dishes only for approved, active restaurants.
drop policy if exists restaurant_public_menu on public.restaurant_menus;
create policy restaurant_public_menu
on public.restaurant_menus
for select
to anon, authenticated
using (
  active = true
  and exists (
    select 1
    from public.restaurant_profiles rp
    join public.shops sh on sh.id = rp.shop_id
    where rp.id = restaurant_menus.restaurant_id
      and sh.status = 'ACTIVE'::public.shop_status
      and sh.verification_status = 'VERIFIED'::public.verification_status
  )
);

drop policy if exists restaurant_public_items on public.restaurant_menu_items;
create policy restaurant_public_items
on public.restaurant_menu_items
for select
to anon, authenticated
using (
  active = true
  and exists (
    select 1
    from public.restaurant_menus rm
    join public.restaurant_profiles rp on rp.id = rm.restaurant_id
    join public.shops sh on sh.id = rp.shop_id
    where rm.id = restaurant_menu_items.menu_id
      and rm.active = true
      and sh.status = 'ACTIVE'::public.shop_status
      and sh.verification_status = 'VERIFIED'::public.verification_status
  )
);

drop policy if exists restaurant_menus_owner_manage
  on public.restaurant_menus;
create policy restaurant_menus_owner_manage
on public.restaurant_menus
for all
to authenticated
using (
  exists (
    select 1
    from public.restaurant_profiles rp
    join public.shops sh on sh.id = rp.shop_id
    join public.sellers s on s.id = sh.seller_id
    where rp.id = restaurant_menus.restaurant_id
      and s.user_id = (select auth.uid())
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role::text in ('SELLER', 'RESTAURANT')
      )
  )
)
with check (
  exists (
    select 1
    from public.restaurant_profiles rp
    join public.shops sh on sh.id = rp.shop_id
    join public.sellers s on s.id = sh.seller_id
    where rp.id = restaurant_menus.restaurant_id
      and s.user_id = (select auth.uid())
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role::text in ('SELLER', 'RESTAURANT')
      )
  )
);

drop policy if exists restaurant_menu_items_owner_manage
  on public.restaurant_menu_items;
create policy restaurant_menu_items_owner_manage
on public.restaurant_menu_items
for all
to authenticated
using (
  exists (
    select 1
    from public.restaurant_menus rm
    join public.restaurant_profiles rp on rp.id = rm.restaurant_id
    join public.shops sh on sh.id = rp.shop_id
    join public.sellers s on s.id = sh.seller_id
    where rm.id = restaurant_menu_items.menu_id
      and s.user_id = (select auth.uid())
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role::text in ('SELLER', 'RESTAURANT')
      )
  )
)
with check (
  exists (
    select 1
    from public.restaurant_menus rm
    join public.restaurant_profiles rp on rp.id = rm.restaurant_id
    join public.shops sh on sh.id = rp.shop_id
    join public.sellers s on s.id = sh.seller_id
    where rm.id = restaurant_menu_items.menu_id
      and s.user_id = (select auth.uid())
      and exists (
        select 1
        from public.user_roles ur
        where ur.user_id = (select auth.uid())
          and ur.role::text in ('SELLER', 'RESTAURANT')
      )
      and (
        restaurant_menu_items.product_id is null
        or exists (
          select 1
          from public.products p
          where p.id = restaurant_menu_items.product_id
            and p.shop_id = sh.id
            and p.status = 'ACTIVE'::public.product_status
        )
      )
  )
);

drop policy if exists restaurant_order_events_owner_read
  on public.restaurant_order_events;
create policy restaurant_order_events_owner_read
on public.restaurant_order_events
for select
to authenticated
using (
  exists (
    select 1
    from public.order_groups og
    join public.shops sh on sh.id = og.shop_id
    join public.sellers s on s.id = sh.seller_id
    where og.id = restaurant_order_events.order_group_id
      and s.user_id = (select auth.uid())
  )
);

-- Narrow, owner-checked RPC for the restaurant's forward preparation workflow.
-- The underlying state machine remains authoritative for ownership, stock,
-- cancellation rules, package coordination and order event creation.
create or replace function public.restaurant_transition_order_group_status(
  p_order_group_id uuid,
  p_next_status public.order_status,
  p_note text default null
)
returns public.order_status
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_user uuid := (select auth.uid());
  v_owner uuid;
  v_result public.order_status;
  v_event_status text;
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_order_group_id is null
     or p_next_status is null
     or p_next_status not in ('CONFIRMED', 'PREPARING', 'READY_FOR_PICKUP') then
    raise exception 'restaurant_order_transition_invalid';
  end if;

  if not exists (
    select 1
    from public.user_roles ur
    where ur.user_id = v_user
      and ur.role::text in ('SELLER', 'RESTAURANT')
  ) then
    raise exception 'restaurant_role_required' using errcode = '42501';
  end if;

  select s.user_id
    into v_owner
  from public.order_groups og
  join public.restaurant_profiles rp on rp.shop_id = og.shop_id
  join public.shops sh on sh.id = rp.shop_id
  join public.sellers s on s.id = sh.seller_id
  where og.id = p_order_group_id;

  if v_owner is null or v_owner <> v_user then
    raise exception 'restaurant_order_not_owned' using errcode = '42501';
  end if;

  v_result := public.transition_order_group_status(
    p_order_group_id,
    p_next_status,
    left(coalesce(p_note, 'Mise à jour depuis l’espace restaurant'), 500)
  );

  v_event_status := case p_next_status
    when 'CONFIRMED' then 'CONFIRMED'
    when 'PREPARING' then 'PREPARING'
    when 'READY_FOR_PICKUP' then 'READY'
  end;

  insert into public.restaurant_order_events(order_group_id, status)
  values (p_order_group_id, v_event_status);

  return v_result;
end;
$function$;

revoke all on function public.restaurant_transition_order_group_status(
  uuid, public.order_status, text
) from public, anon;
grant execute on function public.restaurant_transition_order_group_status(
  uuid, public.order_status, text
) to authenticated;


-- Enforce restaurant ordering rules at transaction commit, not only in the UI.
-- The checkout RPC creates order_groups before order_items, so a deferred
-- constraint trigger can validate the final group subtotal after all items
-- have been written in the same transaction.
create or replace function public.enforce_restaurant_order_group_rules()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_accepting_orders boolean;
  v_delivery_available boolean;
  v_minimum_order_amount numeric(14,2);
  v_subtotal numeric(14,2);
begin
  select
    rp.accepting_orders,
    rp.delivery_available,
    rp.minimum_order_amount
  into
    v_accepting_orders,
    v_delivery_available,
    v_minimum_order_amount
  from public.restaurant_profiles rp
  where rp.shop_id = new.shop_id;

  if not found then
    return null;
  end if;

  if not v_accepting_orders then
    raise exception 'restaurant_not_accepting_orders';
  end if;

  -- The current checkout journey is delivery-address based. Do not accept a
  -- restaurant order when that restaurant has disabled delivery; pickup is
  -- not advertised as an order mode until its dedicated checkout flow exists.
  if not v_delivery_available then
    raise exception 'restaurant_delivery_unavailable';
  end if;

  select coalesce(sum(oi.total_price), 0)
    into v_subtotal
  from public.order_items oi
  where oi.order_group_id = new.id;

  if v_subtotal < v_minimum_order_amount then
    raise exception 'restaurant_minimum_order_not_reached';
  end if;

  return null;
end;
$function$;

revoke all on function public.enforce_restaurant_order_group_rules()
  from public, anon, authenticated;

drop trigger if exists restaurant_order_group_rules
  on public.order_groups;
create constraint trigger restaurant_order_group_rules
after insert on public.order_groups
deferrable initially deferred
for each row
execute function public.enforce_restaurant_order_group_rules();
