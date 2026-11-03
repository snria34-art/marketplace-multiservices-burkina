do $migration$
declare v_def text; v_old text; v_new text;
begin
  v_def:=pg_get_functiondef('public.set_seller_stock(uuid,integer)'::regprocedure);
  v_old:='  select reserved_quantity into v_reserved';
  v_new:='  if exists ('||chr(10)||
    '    select 1 from public.product_variant_inventory vi'||chr(10)||
    '    where vi.product_id = p_product_id'||chr(10)||
    '  ) then'||chr(10)||
    '    raise exception ''use_variant_stock_editor'' using errcode = ''22023'';'||chr(10)||
    '  end if;'||chr(10)||chr(10)||v_old;
  if position(v_old in v_def)=0 then raise exception 'set_seller_stock_variant_guard_patch_failed'; end if;
  execute replace(v_def,v_old,v_new);
end;
$migration$;