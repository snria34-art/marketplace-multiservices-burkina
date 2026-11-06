create or replace function private.seller_respond_to_catalog_finding(
  p_finding_id uuid,
  p_response_text text,
  p_media_storage_path text default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_seller uuid; v_id uuid; v_product uuid; v_status text;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if length(trim(coalesce(p_response_text,''))) < 5 or length(p_response_text)>2000 then raise exception 'invalid_response_text'; end if;
  select p.id,s.id,f.status into v_product,v_seller,v_status
  from private.catalog_moderation_findings f
  join public.products p on p.id=f.product_id
  join public.shops sh on sh.id=p.shop_id
  join public.sellers s on s.id=sh.seller_id
  where f.id=p_finding_id;
  if v_seller is null or not exists (select 1 from public.sellers s where s.id=v_seller and s.user_id=v_uid) then
    raise exception 'seller_not_owner';
  end if;
  if v_status <> 'UNDER_REVIEW' then raise exception 'seller_response_not_requested'; end if;
  if p_media_storage_path is not null and (
    split_part(p_media_storage_path,'/',1)<>v_uid::text
    or split_part(p_media_storage_path,'/',2)<>'moderation'
    or not exists(select 1 from storage.objects o where o.bucket_id='order-feedback-media' and o.name=p_media_storage_path)
  ) then raise exception 'invalid_response_media'; end if;
  insert into private.catalog_moderation_responses(finding_id,seller_user_id,response_text,media_storage_path)
  values(p_finding_id,v_uid,trim(p_response_text),p_media_storage_path) returning id into v_id;
  update private.catalog_moderation_findings set status='OPEN' where id=p_finding_id and status='UNDER_REVIEW';
  insert into private.catalog_moderation_audit(finding_id,product_id,actor_id,action,note)
  values(p_finding_id,v_product,v_uid,'SELLER_RESPONSE',left(trim(p_response_text),500));
  insert into public.notifications(user_id,type,title,body,data)
  select ur.user_id,'CATALOG_MODERATION','Réponse reçue d’un vendeur',left(trim(p_response_text),300),
    jsonb_build_object('finding_id',p_finding_id,'product_id',v_product,'action','SELLER_RESPONSE')
  from public.user_roles ur
  join public.profiles pr on pr.id=ur.user_id
  where ur.role in ('ADMIN'::public.user_role,'SUPER_ADMIN'::public.user_role,'MODERATOR'::public.user_role)
    and pr.status='ACTIVE'::public.account_status;
  return v_id;
end;
$$;

create or replace function private.get_seller_catalog_findings()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_result jsonb;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.detected_at desc),'[]'::jsonb) into v_result
  from (
    select f.id as finding_id,f.rule_code,f.severity,f.matched_terms,f.explanation,f.status,
      f.detected_at,f.review_notes,p.id as product_id,p.name as product_name,p.description as product_description,
      sh.name as shop_name,
      (select jsonb_agg(jsonb_build_object('response_text',r.response_text,'created_at',r.created_at) order by r.created_at desc)
       from private.catalog_moderation_responses r where r.finding_id=f.id and r.seller_user_id=v_uid) as seller_responses
    from private.catalog_moderation_findings f
    join public.products p on p.id=f.product_id
    join public.shops sh on sh.id=p.shop_id
    join public.sellers s on s.id=sh.seller_id
    where s.user_id=v_uid and f.status in ('OPEN','UNDER_REVIEW')
    order by f.detected_at desc
    limit 100
  ) q;
  return v_result;
end;
$$;
revoke all on function private.get_seller_catalog_findings() from public,anon;
grant execute on function private.get_seller_catalog_findings() to authenticated;

create or replace function public.get_seller_catalog_findings()
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.get_seller_catalog_findings();
$$;
revoke all on function public.get_seller_catalog_findings() from public,anon;
grant execute on function public.get_seller_catalog_findings() to authenticated;

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
    else
      update public.products set status='ACTIVE',updated_at=now() where id=v_product and status='PENDING_REVIEW';
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
