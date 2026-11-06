create or replace function private.attach_delivery_evidence(
  p_package_id uuid,p_storage_path text,p_media_type text,p_evidence_type text,
  p_duration_seconds numeric default null,p_person_visible boolean default false,p_person_consent boolean default false
) returns uuid
language plpgsql security definer set search_path='' as $$
declare v_uid uuid := (select auth.uid()); v_assignment uuid; v_assignment_status text; v_id uuid;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if split_part(coalesce(p_storage_path,''),'/',1) <> v_uid::text
     or split_part(coalesce(p_storage_path,''),'/',2) <> 'delivery' then raise exception 'invalid_media_path'; end if;
  if upper(p_evidence_type) not in ('PICKUP','DELIVERY') then raise exception 'invalid_evidence_type'; end if;
  if upper(p_evidence_type)='DELIVERY' and upper(p_media_type)<>'IMAGE' then raise exception 'delivery_photo_required'; end if;
  if upper(p_media_type) not in ('IMAGE','VIDEO') then raise exception 'invalid_media_type'; end if;
  if upper(p_media_type)='IMAGE' and p_duration_seconds is not null then raise exception 'image_duration_not_allowed'; end if;
  if upper(p_media_type)='VIDEO' and (p_duration_seconds is null or p_duration_seconds<=0 or p_duration_seconds>6) then
    raise exception 'evidence_video_too_long';
  end if;
  if coalesce(p_person_visible,false) and not coalesce(p_person_consent,false) then raise exception 'person_consent_required'; end if;
  select da.id,da.status::text into v_assignment,v_assignment_status
  from public.delivery_assignments da
  where da.package_id=p_package_id and da.courier_id=v_uid
  order by da.assigned_at desc limit 1;
  if v_assignment is null then raise exception 'courier_not_assigned_to_package'; end if;
  if upper(p_evidence_type)='PICKUP' and v_assignment_status<>'ACCEPTED' then
    raise exception 'pickup_evidence_requires_accepted_assignment';
  end if;
  if upper(p_evidence_type)='DELIVERY' and v_assignment_status<>'IN_TRANSIT' then
    raise exception 'delivery_evidence_requires_in_transit_assignment';
  end if;
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