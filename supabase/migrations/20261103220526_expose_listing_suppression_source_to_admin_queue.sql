create or replace function private.admin_get_catalog_moderation_queue(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.detected_at desc),'[]'::jsonb) into v_result
  from (
    select f.id as finding_id,f.product_id,f.rule_code,f.severity,f.matched_terms,f.explanation,
      f.status,f.detected_at,f.review_notes,f.ai_model,f.ai_confidence,f.ai_analysis,f.ai_analyzed_at,
      jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'status',p.status,'price',p.price) as product,
      jsonb_build_object('id',sh.id,'name',sh.name,'seller_id',sh.seller_id,'seller_name',pr.display_name) as shop,
      coalesce((select jsonb_agg(jsonb_build_object(
        'storage_path',pi.storage_path,'alt_text',pi.alt_text,'image_role',pi.image_role
      ) order by pi.sort_order) from public.product_images pi where pi.product_id=p.id),'[]'::jsonb) as images,
      (select to_jsonb(resp) from private.catalog_moderation_responses resp where resp.finding_id=f.id order by resp.created_at desc limit 1) as latest_seller_response,
      (select to_jsonb(scan) from private.catalog_ai_product_scans scan where scan.product_id=p.id order by scan.scanned_at desc limit 1) as latest_ai_scan,
      (select to_jsonb(r) from private.product_listing_restrictions r where r.product_id=p.id and r.active=true order by r.applied_at desc limit 1) as active_listing_restriction
    from private.catalog_moderation_findings f
    join public.products p on p.id=f.product_id
    join public.shops sh on sh.id=p.shop_id
    join public.profiles pr on pr.id=(select s.user_id from public.sellers s where s.id=sh.seller_id)
    where f.status in ('OPEN','UNDER_REVIEW')
    order by f.detected_at desc
    limit greatest(1,least(coalesce(p_limit,50),100))
  ) q;
  return v_result;
end;
$$;