drop policy if exists product_media_admin_read on storage.objects;
create policy product_media_admin_read on storage.objects
for select to authenticated
using (bucket_id='product-media' and (select public.is_admin_actor()));

drop policy if exists order_feedback_media_admin_read on storage.objects;
create policy order_feedback_media_admin_read on storage.objects
for select to authenticated
using (bucket_id='order-feedback-media' and (select public.is_admin_actor()));

create or replace function private.admin_decide_catalog_finding(
  p_finding_id uuid,
  p_decision text,
  p_note text
) returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_product uuid; v_previous text; v_decision text := upper(trim(p_decision)); v_seller_user uuid;
begin
  if v_uid is null or not private.is_active_account() or not public.is_admin_actor() then raise exception 'admin_access_required'; end if;
  if length(trim(coalesce(p_note,''))) < 3 or length(p_note)>2000 then raise exception 'decision_note_required'; end if;
  select f.product_id,s.user_id into v_product,v_seller_user
  from private.catalog_moderation_findings f
  join public.products p on p.id=f.product_id
  join public.shops sh on sh.id=p.shop_id
  join public.sellers s on s.id=sh.seller_id
  where f.id=p_finding_id for update of f;
  if v_product is null then raise exception 'finding_not_found'; end if;

  if v_decision='REQUEST_INFO' then
    update private.catalog_moderation_findings set status='UNDER_REVIEW',reviewed_by=v_uid,reviewed_at=now(),review_notes=trim(p_note) where id=p_finding_id;
    insert into public.notifications(user_id,type,title,body,data)
    values(v_seller_user,'CATALOG_MODERATION','Explication demandée pour votre annonce',trim(p_note),
      jsonb_build_object('finding_id',p_finding_id,'product_id',v_product,'action','SELLER_RESPONSE'));
  elsif v_decision='CLEAR' then
    update private.catalog_moderation_findings set status='CLEARED',reviewed_by=v_uid,reviewed_at=now(),review_notes=trim(p_note) where id=p_finding_id;
    update private.product_listing_restrictions set active=false,restored_by=v_uid,restored_at=now()
      where product_id=v_product and active=true returning previous_status into v_previous;
    if v_previous is not null then
      update public.products set status=v_previous::public.product_status,updated_at=now() where id=v_product and status='INACTIVE';
      insert into private.catalog_moderation_audit(finding_id,product_id,actor_id,action,note)
      values(p_finding_id,v_product,v_uid,'LISTING_RESTORED',trim(p_note));
    end if;
    insert into public.notifications(user_id,type,title,body,data)
    values(v_seller_user,'CATALOG_MODERATION','Votre annonce a été validée',trim(p_note),
      jsonb_build_object('finding_id',p_finding_id,'product_id',v_product,'action','CLEARED'));
  elsif v_decision='REJECT' then
    update private.catalog_moderation_findings set status='REJECTED',reviewed_by=v_uid,reviewed_at=now(),review_notes=trim(p_note) where id=p_finding_id;
    select status::text into v_previous from public.products where id=v_product for update;
    insert into private.product_listing_restrictions(product_id,finding_id,previous_status,reason,applied_by)
    values(v_product,p_finding_id,v_previous,trim(p_note),v_uid)
    on conflict (product_id) where active do nothing;
    update public.products set status='INACTIVE',updated_at=now() where id=v_product and status<>'INACTIVE';
    insert into private.catalog_moderation_audit(finding_id,product_id,actor_id,action,note)
    values(p_finding_id,v_product,v_uid,'LISTING_SUPPRESSED',trim(p_note));
    insert into public.notifications(user_id,type,title,body,data)
    values(v_seller_user,'CATALOG_MODERATION','Votre annonce a été retirée temporairement des listings',trim(p_note),
      jsonb_build_object('finding_id',p_finding_id,'product_id',v_product,'action','REJECTED'));
  else
    raise exception 'invalid_decision';
  end if;
  insert into private.catalog_moderation_audit(finding_id,product_id,actor_id,action,note)
  values(p_finding_id,v_product,v_uid,
    case v_decision when 'REQUEST_INFO' then 'REQUEST_INFO' when 'CLEAR' then 'CLEARED' else 'REJECTED' end,
    trim(p_note));
  return true;
end;
$$;
