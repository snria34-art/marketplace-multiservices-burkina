do $migration$
declare v_def text;
begin
  v_def := pg_get_functiondef('public.set_cart_item_quantity(uuid,integer)'::regprocedure);
  v_def := replace(v_def, '  v_product_id uuid;', '  v_product_id uuid;' || chr(10) || '  v_variant_id uuid;');
  v_def := replace(v_def, 'select ci.cart_id, ci.product_id', 'select ci.cart_id, ci.product_id, ci.variant_id');
  v_def := replace(v_def, 'into v_cart_id, v_product_id', 'into v_cart_id, v_product_id, v_variant_id');
  v_def := replace(v_def,
    'select i.quantity - i.reserved_quantity
    into v_available
  from public.inventory i
  where i.product_id = v_product_id
  for share;',
    'select public.get_available_variant_stock(v_product_id, v_variant_id)
    into v_available;');
  if v_def not like '%v_variant_id%' or v_def not like '%get_available_variant_stock%' then
    raise exception 'set_cart_item_quantity_stock_patch_failed';
  end if;
  execute v_def;
end;
$migration$;