
do $migration$
declare
  v_def text;
begin
  v_def := pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)'::regprocedure);
  v_def := replace(v_def, 'select oi.product_id, oi.quantity', 'select oi.product_id, oi.variant_id, oi.quantity');
  v_def := replace(
    v_def,
    'perform public.release_inventory(v_item.product_id,v_item.quantity);',
    'if not public.release_variant_inventory(v_item.product_id,v_item.variant_id,v_item.quantity) then raise exception ''reserved_inventory_release_failed''; end if;'
  );
  if v_def not like '%release_variant_inventory%' then
    raise exception 'process_payment_event_variant_release_patch_failed';
  end if;
  execute v_def;

  v_def := pg_get_functiondef('public.transition_order_status(uuid,public.order_status,text)'::regprocedure);
  v_def := replace(v_def, 'begin' || chr(10), 'begin' || chr(10) || '  perform private.require_active_account();' || chr(10));
  v_def := replace(
    v_def,
    'v_is_admin := exists (\n    select 1 from public.admin_users au\n    where au.user_id = v_user and au.active = true\n  );',
    'v_is_admin := private.is_admin();'
  );
  v_def := replace(v_def, 'select oi.product_id, oi.quantity', 'select oi.product_id, oi.variant_id, oi.quantity');
  v_def := replace(
    v_def,
    'perform public.release_inventory(v_item.product_id, v_item.quantity);',
    'if not public.release_variant_inventory(v_item.product_id, v_item.variant_id, v_item.quantity) then raise exception ''reserved_inventory_release_failed''; end if;'
  );
  if v_def not like '%release_variant_inventory%' or v_def not like '%require_active_account%' then
    raise exception 'transition_order_status_variant_release_patch_failed';
  end if;
  execute v_def;
end;
$migration$;
