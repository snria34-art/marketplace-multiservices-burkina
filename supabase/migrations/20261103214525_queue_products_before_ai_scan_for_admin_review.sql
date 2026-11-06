create or replace function private.submit_seller_product_for_review(p_product_id uuid)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_seller uuid; v_status public.product_status;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  select sh.seller_id,p.status into v_seller,v_status
  from public.products p join public.shops sh on sh.id=p.shop_id where p.id=p_product_id for update of p;
  if v_seller is null or not exists(select 1 from public.sellers s where s.id=v_seller and s.user_id=v_uid) then
    raise exception 'product_not_owned';
  end if;
  if not exists(select 1 from public.product_images pi where pi.product_id=p_product_id and pi.image_role='PRODUCT') then
    raise exception 'product_photo_required';
  end if;
  if v_status='ACTIVE' then raise exception 'product_already_active'; end if;
  update public.products set status='PENDING_REVIEW',updated_at=now() where id=p_product_id;
  insert into private.catalog_moderation_findings(
    product_id,rule_code,severity,matched_terms,explanation,status
  ) values (
    p_product_id,'AI_PRODUCT_REVIEW','REVIEW',array['AWAITING_AI_ANALYSIS'],
    'Annonce soumise. Analyse visuelle IA et validation administrative en attente. Aucune sanction automatique.',
    'OPEN'
  )
  on conflict(product_id,rule_code) do update set
    severity='REVIEW',matched_terms=array['AWAITING_AI_ANALYSIS'],
    explanation='Annonce soumise. Analyse visuelle IA et validation administrative en attente. Aucune sanction automatique.',
    status=case when private.catalog_moderation_findings.status in ('CLEARED','REJECTED') then 'OPEN' else private.catalog_moderation_findings.status end,
    detected_at=now();
  return true;
end;
$$;
