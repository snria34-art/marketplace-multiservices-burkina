alter table public.inventory_movements add column if not exists variant_id uuid;

do $constraint$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='inventory_movements_variant_id_fkey'
      and conrelid='public.inventory_movements'::regclass
  ) then
    alter table public.inventory_movements
      add constraint inventory_movements_variant_id_fkey
      foreign key (variant_id) references public.product_variants(id) on delete set null;
  end if;
end;
$constraint$;

create index if not exists idx_inventory_movements_variant
  on public.inventory_movements(variant_id) where variant_id is not null;

create or replace function public.set_seller_variant_stock(
  p_variant_id uuid, p_quantity integer
) returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_product_id uuid;
  v_reserved integer;
  v_old_quantity integer;
  v_delta integer;
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
  select vi.reserved_quantity, vi.quantity into v_reserved, v_old_quantity
  from public.product_variant_inventory vi where vi.variant_id = p_variant_id for update;
  if not found then
    insert into public.product_variant_inventory(variant_id,product_id,quantity,reserved_quantity)
    values(p_variant_id,v_product_id,p_quantity,0);
    v_delta := p_quantity;
  else
    if p_quantity < v_reserved then raise exception 'stock_below_reserved' using errcode = '22023'; end if;
    v_delta := p_quantity - v_old_quantity;
    update public.product_variant_inventory
    set quantity=p_quantity,updated_at=now()
    where variant_id=p_variant_id and product_id=v_product_id;
  end if;
  if v_delta <> 0 then
    insert into public.inventory_movements(product_id,variant_id,quantity_delta,reason,reference_id,created_by)
    values(v_product_id,p_variant_id,v_delta,'SELLER_VARIANT_STOCK_ADJUSTMENT',p_variant_id,v_user);
  end if;
end;
$$;
revoke all on function public.set_seller_variant_stock(uuid,integer) from public, anon;
grant execute on function public.set_seller_variant_stock(uuid,integer) to authenticated;