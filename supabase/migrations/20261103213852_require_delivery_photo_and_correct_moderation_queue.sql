create or replace function public.attach_delivery_evidence(
  p_package_id uuid,
  p_storage_path text,
  p_media_type text,
  p_evidence_type text,
  p_duration_seconds numeric default null,
  p_person_visible boolean default false,
  p_person_consent boolean default false
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_assignment uuid; v_id uuid;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if split_part(coalesce(p_storage_path,''),'/',1) <> v_uid::text
     or split_part(coalesce(p_storage_path,''),'/',2) <> 'delivery' then raise exception 'invalid_media_path'; end if;
  if upper(p_evidence_type) not in ('PICKUP','DELIVERY') then raise exception 'invalid_evidence_type'; end if;
  if upper(p_evidence_type)='DELIVERY' and upper(p_media_type)<>'IMAGE' then raise exception 'delivery_photo_required'; end if;
  if coalesce(p_person_visible,false) and not coalesce(p_person_consent,false) then raise exception 'person_consent_required'; end if;
  select da.id into v_assignment
  from public.delivery_assignments da
  where da.package_id=p_package_id and da.courier_id=v_uid
  order by da.assigned_at desc limit 1;
  if v_assignment is null then raise exception 'courier_not_assigned_to_package'; end if;
  if not exists (select 1 from storage.objects o where o.bucket_id='order-feedback-media' and o.name=p_storage_path) then
    raise exception 'media_object_missing';
  end if;
  insert into public.delivery_evidence(
    package_id,assignment_id,courier_id,evidence_type,media_type,storage_path,
    duration_seconds,person_visible,person_consent
  ) values (
    p_package_id,v_assignment,v_uid,upper(p_evidence_type),upper(p_media_type),
    p_storage_path,p_duration_seconds,coalesce(p_person_visible,false),coalesce(p_person_consent,false)
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.confirm_package_pickup(p_package_id uuid, p_pickup_code text)
returns uuid
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
 v_assignment public.delivery_assignments%rowtype;
 v_package public.order_packages%rowtype;
begin
 perform private.require_active_account();
 if not exists(select 1 from public.user_roles where user_id=(select auth.uid()) and role='COURIER') then
   raise exception 'courier_role_required';
 end if;
 if p_pickup_code is null or length(trim(p_pickup_code)) < 4 then raise exception 'pickup_code_required'; end if;

 select * into v_assignment from public.delivery_assignments
 where package_id=p_package_id and courier_id=(select auth.uid()) and status='ASSIGNED' for update;
 if not found then raise exception 'assignment_not_found'; end if;

 select * into v_package from public.order_packages where id=p_package_id for update;
 if not found then raise exception 'package_not_found'; end if;
 if v_package.status <> 'READY_FOR_PICKUP' then raise exception 'package_not_ready'; end if;
 if v_package.pickup_code_hash is null or encode(digest(trim(p_pickup_code),'sha256'),'hex') <> v_package.pickup_code_hash then
   raise exception 'pickup_code_invalid';
 end if;
 if not exists (
   select 1 from public.delivery_evidence de
   where de.package_id=p_package_id and de.assignment_id=v_assignment.id
     and de.courier_id=(select auth.uid()) and de.evidence_type='PICKUP'
 ) then raise exception 'pickup_photo_required'; end if;

 perform public.consume_package_inventory(p_package_id);
 update public.order_packages set status='PICKED_UP',picked_up_at=now(),updated_at=now()
 where id=p_package_id;
 update public.delivery_assignments set status='PICKED_UP',accepted_at=coalesce(accepted_at,now())
 where id=v_assignment.id;
 insert into public.delivery_assignment_events(assignment_id,actor_id,event_type,metadata)
 values(v_assignment.id,(select auth.uid()),'PACKAGE_PICKED_UP',jsonb_build_object('package_id',p_package_id));
 return v_assignment.id;
end;
$$;

create or replace function public.confirm_package_delivery(p_package_id uuid, p_delivery_code text)
returns uuid
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare v_id uuid;
begin
 perform private.require_active_account();
 if not private.has_role('COURIER'::public.user_role) then raise exception 'courier_role_required' using errcode = '42501'; end if;
 if p_delivery_code is null or p_delivery_code !~ '^[0-9]{6}$' then raise exception 'delivery_code_invalid'; end if;
 if not exists (
   select 1 from public.delivery_evidence de
   join public.delivery_assignments da on da.id=de.assignment_id
   where de.package_id=p_package_id and de.courier_id=(select auth.uid())
     and de.evidence_type='DELIVERY' and de.media_type='IMAGE'
     and da.courier_id=(select auth.uid()) and da.status='IN_TRANSIT'
 ) then raise exception 'delivery_photo_required'; end if;
 update public.order_packages p
 set status='DELIVERED',delivered_at=now(),updated_at=now()
 where p.id=p_package_id
 and p.status='IN_TRANSIT'
 and p.delivery_code_hash=encode(digest(p_delivery_code,'sha256'),'hex')
 and exists(
   select 1 from public.delivery_assignments da
   where da.package_id=p.id and da.courier_id=(select auth.uid()) and da.status='IN_TRANSIT'
 )
 returning p.id into v_id;
 if v_id is null then raise exception 'delivery_not_authorized_or_code_invalid'; end if;
 insert into public.delivery_events(package_id,actor_id,status,metadata)
 values(p_package_id,(select auth.uid()),'DELIVERED','{"delivery_photo_required":true}'::jsonb);
 perform public.sync_after_package_delivery(p_package_id);
 return v_id;
end;
$$;

create or replace function public.admin_get_catalog_moderation_queue(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.detected_at desc),'[]'::jsonb) into v_result
  from (
    select f.id as finding_id,f.product_id,f.rule_code,f.severity,f.matched_terms,f.explanation,
      f.status,f.detected_at,f.review_notes,
      jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'status',p.status,'price',p.price) as product,
      jsonb_build_object('id',sh.id,'name',sh.name,'seller_id',sh.seller_id,'seller_name',pr.display_name) as shop,
      coalesce((select jsonb_agg(jsonb_build_object('storage_path',pi.storage_path,'alt_text',pi.alt_text) order by pi.sort_order)
        from public.product_images pi where pi.product_id=p.id),'[]'::jsonb) as images,
      (select to_jsonb(resp) from private.catalog_moderation_responses resp where resp.finding_id=f.id order by resp.created_at desc limit 1) as latest_seller_response
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
