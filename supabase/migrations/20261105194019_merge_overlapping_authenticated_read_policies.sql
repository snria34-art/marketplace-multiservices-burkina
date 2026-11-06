alter policy inventory_owner_read on public.inventory
using (
  exists (
    select 1
    from public.products p
    join public.shops sh on sh.id=p.shop_id
    join public.sellers s on s.id=sh.seller_id
    where p.id=inventory.product_id
      and s.user_id=(select auth.uid())
  )
  or exists (
    select 1
    from public.products p
    where p.id=inventory.product_id
      and private.has_active_seller_access(p.shop_id,'inventory_read'::text)
  )
);
drop policy if exists inventory_shared_access_read on public.inventory;

alter policy inventory_movements_owner_read on public.inventory_movements
using (
  exists (
    select 1
    from public.products p
    join public.shops sh on sh.id=p.shop_id
    join public.sellers s on s.id=sh.seller_id
    where p.id=inventory_movements.product_id
      and s.user_id=(select auth.uid())
  )
  or exists (
    select 1
    from public.products p
    where p.id=inventory_movements.product_id
      and private.has_active_seller_access(p.shop_id,'inventory_read'::text)
  )
);
drop policy if exists inventory_movements_shared_access_read on public.inventory_movements;

alter policy order_groups_read on public.order_groups
using (
  (order_id in (
    select o.id from public.orders o
    where o.customer_id=(select auth.uid())
  ))
  or (shop_id in (
    select sh.id
    from public.shops sh
    join public.sellers se on se.id=sh.seller_id
    where se.user_id=(select auth.uid())
  ))
  or private.has_active_seller_access(shop_id,'orders_read'::text)
);
drop policy if exists order_groups_shared_access_read on public.order_groups;

alter policy order_items_read on public.order_items
using (
  (order_group_id in (
    select og.id
    from public.order_groups og
    join public.orders o on o.id=og.order_id
    where o.customer_id=(select auth.uid())
  ))
  or (order_group_id in (
    select og.id
    from public.order_groups og
    join public.shops sh on sh.id=og.shop_id
    join public.sellers se on se.id=sh.seller_id
    where se.user_id=(select auth.uid())
  ))
  or exists (
    select 1
    from public.order_groups og
    where og.id=order_items.order_group_id
      and private.has_active_seller_access(og.shop_id,'orders_read'::text)
  )
);
drop policy if exists order_items_shared_access_read on public.order_items;

alter policy products_read on public.products to anon;
create policy products_authenticated_read on public.products
for select to authenticated
using (
  private.is_admin()
  or (
    status='ACTIVE'::public.product_status
    and (not is_expirable or expiry_date is null or expiry_date>=current_date)
    and exists (
      select 1 from public.shops sh
      where sh.id=products.shop_id
        and sh.status='ACTIVE'::public.shop_status
        and sh.verification_status='VERIFIED'::public.verification_status
    )
  )
  or shop_id in (
    select sh.id
    from public.shops sh
    join public.sellers se on se.id=sh.seller_id
    where se.user_id=(select auth.uid())
  )
  or (
    status<>'ARCHIVED'::public.product_status
    and private.has_active_seller_access(shop_id,'products'::text)
  )
);
drop policy if exists products_shared_access_read on public.products;

alter policy shops_read on public.shops to anon;
create policy shops_authenticated_read on public.shops
for select to authenticated
using (
  (
    (status='ACTIVE'::public.shop_status and verification_status='VERIFIED'::public.verification_status)
    or seller_id in (
      select s.id from public.sellers s
      where s.user_id=(select auth.uid())
    )
  )
  or private.has_active_seller_access(id,'shop_profile'::text)
);
drop policy if exists shops_shared_access_read on public.shops;
