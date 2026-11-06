
create or replace function private.has_active_seller_access(
  p_shop_id uuid,
  p_scope text
) returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    auth.uid() is not null
    and private.is_active_account()
    and p_shop_id is not null
    and p_scope is not null
    and exists (
      select 1
      from private.seller_access_requests r
      join public.shops sh on sh.id=r.owner_shop_id
      join public.sellers se on se.id=sh.seller_id
      join public.profiles owner_profile on owner_profile.id=se.user_id
      where r.owner_shop_id=p_shop_id
        and r.target_user_id=auth.uid()
        and r.status='APPROVED'
        and (r.expires_at is null or r.expires_at > now())
        and p_scope = any(r.requested_scopes)
        and owner_profile.status='ACTIVE'::public.account_status
    );
$function$;

revoke all on function private.has_active_seller_access(uuid,text) from public, anon;
grant execute on function private.has_active_seller_access(uuid,text) to authenticated;

create policy "shops_shared_access_read"
on public.shops for select to authenticated
using (private.has_active_seller_access(id,'shop_profile'));

create policy "products_shared_access_read"
on public.products for select to authenticated
using (
  status <> 'ARCHIVED'::public.product_status
  and private.has_active_seller_access(shop_id,'products')
);

create policy "inventory_shared_access_read"
on public.inventory for select to authenticated
using (
  exists (
    select 1 from public.products p
    where p.id=inventory.product_id
      and private.has_active_seller_access(p.shop_id,'inventory_read')
  )
);

create policy "inventory_movements_shared_access_read"
on public.inventory_movements for select to authenticated
using (
  exists (
    select 1 from public.products p
    where p.id=inventory_movements.product_id
      and private.has_active_seller_access(p.shop_id,'inventory_read')
  )
);

create policy "commissions_shared_access_read"
on public.commissions for select to authenticated
using (
  exists (
    select 1 from public.shops sh
    where sh.seller_id=commissions.seller_id
      and private.has_active_seller_access(sh.id,'financial_read')
  )
);

create policy "seller_ledger_shared_access_read"
on public.seller_ledger for select to authenticated
using (
  exists (
    select 1 from public.shops sh
    where sh.seller_id=seller_ledger.seller_id
      and private.has_active_seller_access(sh.id,'financial_read')
  )
);

create policy "seller_payouts_shared_access_read"
on public.seller_payouts for select to authenticated
using (
  exists (
    select 1 from public.shops sh
    where sh.seller_id=seller_payouts.seller_id
      and private.has_active_seller_access(sh.id,'financial_read')
  )
);

create policy "order_groups_shared_access_read"
on public.order_groups for select to authenticated
using (
  private.has_active_seller_access(shop_id,'orders_read')
);

create policy "order_items_shared_access_read"
on public.order_items for select to authenticated
using (
  exists (
    select 1 from public.order_groups og
    where og.id=order_items.order_group_id
      and private.has_active_seller_access(og.shop_id,'orders_read')
  )
);
