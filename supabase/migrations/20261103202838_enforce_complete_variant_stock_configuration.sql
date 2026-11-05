do $migration$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  -- Stock reader: accept both the compact source form from the first
  -- inventory migration and PostgreSQL's expanded pg_get_functiondef form.
  v_def := pg_get_functiondef('public.get_available_variant_stock(uuid,uuid)'::regprocedure);
  if position('variant_stock_not_configured' in v_def) = 0 then
    v_old := '    if found then' || chr(10) ||
             '      return v_available;' || chr(10) ||
             '    end if;';
    v_new := v_old || chr(10) ||
             '    if exists (select 1 from public.product_variant_inventory vi where vi.product_id = p_product_id) then' || chr(10) ||
             '      raise exception ''variant_stock_not_configured'' using errcode = ''P0001'';' || chr(10) ||
             '    end if;';
    if position(v_old in v_def) > 0 then
      v_def := replace(v_def, v_old, v_new);
    else
      v_old := '    if found then return v_available; end if;';
      v_new := v_old || chr(10) ||
               '    if exists (select 1 from public.product_variant_inventory vi where vi.product_id = p_product_id) then' || chr(10) ||
               '      raise exception ''variant_stock_not_configured'' using errcode = ''P0001'';' || chr(10) ||
               '    end if;';
      if position(v_old in v_def) = 0 then
        raise exception 'variant_stock_read_patch_not_found';
      end if;
      v_def := replace(v_def, v_old, v_new);
    end if;
    execute v_def;
  end if;

  -- Reservation: refuse fallback to aggregate product stock when variant
  -- stock rows exist but the selected variant has not been configured.
  v_def := pg_get_functiondef('public.reserve_variant_inventory(uuid,uuid,integer)'::regprocedure);
  if position('variant_stock_not_configured' in v_def) = 0 then
    v_old := '  if not v_has_variant_stock then' || chr(10) ||
             '    return public.reserve_inventory(p_product_id, p_quantity);' || chr(10) ||
             '  end if;';
    v_new := '  if not v_has_variant_stock then' || chr(10) ||
             '    if exists (select 1 from public.product_variant_inventory vi where vi.product_id = p_product_id) then' || chr(10) ||
             '      raise exception ''variant_stock_not_configured'' using errcode = ''P0001'';' || chr(10) ||
             '    end if;' || chr(10) ||
             '    return public.reserve_inventory(p_product_id, p_quantity);' || chr(10) ||
             '  end if;';
    if position(v_old in v_def) = 0 then
      raise exception 'variant_stock_reserve_patch_not_found';
    end if;
    execute replace(v_def, v_old, v_new);
  end if;

  -- Consumption: apply the same consistency rule before consuming a reserve.
  v_def := pg_get_functiondef('public.consume_variant_inventory(uuid,uuid,integer)'::regprocedure);
  if position('variant_stock_not_configured' in v_def) = 0 then
    v_old := '  if not v_has_variant_stock then' || chr(10) ||
             '    return public.consume_reserved_inventory(p_product_id, p_quantity);' || chr(10) ||
             '  end if;';
    v_new := '  if not v_has_variant_stock then' || chr(10) ||
             '    if exists (select 1 from public.product_variant_inventory vi where vi.product_id = p_product_id) then' || chr(10) ||
             '      raise exception ''variant_stock_not_configured'' using errcode = ''P0001'';' || chr(10) ||
             '    end if;' || chr(10) ||
             '    return public.consume_reserved_inventory(p_product_id, p_quantity);' || chr(10) ||
             '  end if;';
    if position(v_old in v_def) = 0 then
      raise exception 'variant_stock_consume_patch_not_found';
    end if;
    execute replace(v_def, v_old, v_new);
  end if;

  -- Release: support the compact function body introduced by the preceding
  -- cancellation migration as well as an expanded function body.
  v_def := pg_get_functiondef('public.release_variant_inventory(uuid,uuid,integer)'::regprocedure);
  if position('variant_stock_not_configured' in v_def) = 0 then
    v_old := '  if not v_has_variant_stock then' || chr(10) ||
             '    return public.release_inventory(p_product_id, p_quantity);' || chr(10) ||
             '  end if;';
    v_new := '  if not v_has_variant_stock then' || chr(10) ||
             '    if exists (select 1 from public.product_variant_inventory vi where vi.product_id = p_product_id) then' || chr(10) ||
             '      raise exception ''variant_stock_not_configured'' using errcode = ''P0001'';' || chr(10) ||
             '    end if;' || chr(10) ||
             '    return public.release_inventory(p_product_id, p_quantity);' || chr(10) ||
             '  end if;';
    if position(v_old in v_def) > 0 then
      v_def := replace(v_def, v_old, v_new);
    else
      v_old := '  if not v_has_variant_stock then return public.release_inventory(p_product_id,p_quantity); end if;';
      v_new := '  if not v_has_variant_stock then' || chr(10) ||
               '    if exists (select 1 from public.product_variant_inventory vi where vi.product_id = p_product_id) then' || chr(10) ||
               '      raise exception ''variant_stock_not_configured'' using errcode = ''P0001'';' || chr(10) ||
               '    end if;' || chr(10) ||
               '    return public.release_inventory(p_product_id,p_quantity);' || chr(10) ||
               '  end if;';
      if position(v_old in v_def) = 0 then
        raise exception 'variant_stock_release_patch_not_found';
      end if;
      v_def := replace(v_def, v_old, v_new);
    end if;
    execute v_def;
  end if;
end;
$migration$;
