alter table private.catalog_moderation_responses
  add column if not exists media_type text,
  add column if not exists duration_seconds numeric(5,2);
do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='private.catalog_moderation_responses'::regclass and conname='catalog_moderation_response_media_check') then
    alter table private.catalog_moderation_responses
    add constraint catalog_moderation_response_media_check check (
      (media_storage_path is null and media_type is null and duration_seconds is null)
      or (media_storage_path is not null and media_type='IMAGE' and duration_seconds is null)
      or (media_storage_path is not null and media_type='VIDEO' and duration_seconds > 0 and duration_seconds <= 10)
    );
  end if;
end $$;

drop function if exists public.seller_respond_to_catalog_finding(uuid,text,text);
drop function if exists private.seller_respond_to_catalog_finding(uuid,text,text);

create or replace function private.seller_respond_to_catalog_finding(
  p_finding_id uuid,p_response_text text,p_media_storage_path text default null,
  p_media_type text default null,p_duration_seconds numeric default null
) returns uuid
language plpgsql security definer set search_path='' as $$
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
  if p_media_storage_path is not null then
    if split_part(p_media_storage_path,'/',1)<>v_uid::text
      or split_part(p_media_storage_path,'/',2)<>'moderation'
      or upper(coalesce(p_media_type,'')) not in ('IMAGE','VIDEO')
      or not exists(select 1 from storage.objects o where o.bucket_id='order-feedback-media' and o.name=p_media_storage_path) then
      raise exception 'invalid_response_media';
    end if;
    if upper(p_media_type)='VIDEO' and (p_duration_seconds is null or p_duration_seconds<=0 or p_duration_seconds>10) then
      raise exception 'response_video_too_long';
    end if;
    if upper(p_media_type)='IMAGE' and p_duration_seconds is not null then
      raise exception 'image_duration_not_allowed';
    end if;
  elsif p_media_type is not null or p_duration_seconds is not null then
    raise exception 'media_metadata_without_media';
  end if;
  insert into private.catalog_moderation_responses(
    finding_id,seller_user_id,response_text,media_storage_path,media_type,duration_seconds
  ) values(
    p_finding_id,v_uid,trim(p_response_text),p_media_storage_path,upper(p_media_type),p_duration_seconds
  ) returning id into v_id;
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
revoke all on function private.seller_respond_to_catalog_finding(uuid,text,text,text,numeric) from public,anon;
grant execute on function private.seller_respond_to_catalog_finding(uuid,text,text,text,numeric) to authenticated;

create or replace function public.seller_respond_to_catalog_finding(
  p_finding_id uuid,p_response_text text,p_media_storage_path text default null,
  p_media_type text default null,p_duration_seconds numeric default null
) returns uuid language sql security invoker set search_path='' as $$
  select private.seller_respond_to_catalog_finding(
    p_finding_id,p_response_text,p_media_storage_path,p_media_type,p_duration_seconds
  );
$$;
revoke all on function public.seller_respond_to_catalog_finding(uuid,text,text,text,numeric) from public,anon;
grant execute on function public.seller_respond_to_catalog_finding(uuid,text,text,text,numeric) to authenticated;