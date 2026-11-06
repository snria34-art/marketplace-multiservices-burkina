create or replace function public.release_variant_inventory(
  p_product_id uuid, p_variant_id uuid, p_quantity integer
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_variant_product uuid; v_has_variant_stock boolean; v_rows integer;
begin
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'quantity_must_be_positive' using errcode = '22023';
  end if;
  if p_variant_id is null then return public.release_inventory(p_product_id,p_quantity); end if;
  select pv.product_id into v_variant_product from public.product_variants pv where pv.id=p_variant_id;
  if v_variant_product is null or v_variant_product <> p_product_id then
    raise exception 'invalid_variant' using errcode = '22023';
  end if;
  select exists(select 1 from public.product_variant_inventory vi where vi.variant_id=p_variant_id)
    into v_has_variant_stock;
  if not v_has_variant_stock then return public.release_inventory(p_product_id,p_quantity); end if;
  update public.product_variant_inventory vi
  set reserved_quantity=vi.reserved_quantity-p_quantity,updated_at=now()
  where vi.variant_id=p_variant_id and vi.product_id=p_product_id and vi.reserved_quantity>=p_quantity;
  get diagnostics v_rows=row_count;
  return v_rows=1;
end;
$$;
revoke all on function public.release_variant_inventory(uuid,uuid,integer) from public, anon, authenticated;

do $migration$
declare v_def text;
begin
  v_def:=pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure);
  v_def:=replace(v_def,'begin'||chr(10),'begin'||chr(10)||'  perform private.require_active_account();'||chr(10));
  v_def:=replace(v_def,'select oi.product_id, sum(oi.quantity)::integer as qty','select oi.product_id, oi.variant_id, sum(oi.quantity)::integer as qty');
  v_def:=replace(v_def,'group by oi.product_id','group by oi.product_id, oi.variant_id');
  v_def:=replace(v_def,
    'perform public.release_inventory(v_item.product_id,v_item.qty);',
    'if not public.release_variant_inventory(v_item.product_id,v_item.variant_id,v_item.qty) then raise exception ''reserved_inventory_release_failed''; end if;');
  if v_def not like '%release_variant_inventory%' or v_def not like '%require_active_account%' then
    raise exception 'cancel_unpaid_order_variant_release_patch_failed';
  end if;
  execute v_def;
end;
$migration$;