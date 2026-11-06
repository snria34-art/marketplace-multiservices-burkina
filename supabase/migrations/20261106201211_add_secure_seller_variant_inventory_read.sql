create or replace function public.get_seller_product_variant_inventory(
  p_product_id uuid
)
returns table (
  variant_id uuid,
  product_id uuid,
  name text,
  sku text,
  price numeric,
  quantity integer,
  reserved_quantity integer
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  perform private.require_active_account();

  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if p_product_id is null or not exists (
    select 1
    from public.products p
    join public.shops sh on sh.id = p.shop_id
    join public.sellers se on se.id = sh.seller_id
    where p.id = p_product_id
      and se.user_id = v_user
  ) then
    raise exception 'product_not_owned' using errcode = '42501';
  end if;

  return query
  select
    pv.id,
    pv.product_id,
    pv.name,
    pv.sku,
    pv.price,
    coalesce(vi.quantity, 0),
    coalesce(vi.reserved_quantity, 0)
  from public.product_variants pv
  left join public.product_variant_inventory vi
    on vi.variant_id = pv.id
   and vi.product_id = pv.product_id
  where pv.product_id = p_product_id
  order by pv.created_at, pv.id;
end;
$$;

revoke all on function public.get_seller_product_variant_inventory(uuid)
  from public, anon;
grant execute on function public.get_seller_product_variant_inventory(uuid)
  to authenticated;
