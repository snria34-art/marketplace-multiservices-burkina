create or replace function private.attach_review_media(
  p_review_id uuid,p_storage_path text,p_media_type text,p_duration_seconds numeric default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid := (select auth.uid()); v_id uuid; v_type text := upper(coalesce(p_media_type,''));
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if p_storage_path is null or split_part(p_storage_path,'/',1)<>v_uid::text
    or split_part(p_storage_path,'/',2)<>'reviews' then raise exception 'invalid_media_path'; end if;
  if v_type not in ('IMAGE','VIDEO') then raise exception 'invalid_review_media_type'; end if;
  if v_type='IMAGE' and p_duration_seconds is not null then raise exception 'image_duration_not_allowed'; end if;
  if v_type='VIDEO' and (p_duration_seconds is null or p_duration_seconds<=0 or p_duration_seconds>10)
    then raise exception 'review_video_must_be_ten_seconds_or_less'; end if;
  if not exists(select 1 from public.reviews r where r.id=p_review_id and r.customer_id=v_uid
    and r.status='PENDING'::public.review_status and r.created_at>=now()-interval '7 days')
    then raise exception 'review_not_owned_or_review_window_expired'; end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='order-feedback-media' and o.name=p_storage_path)
    then raise exception 'media_object_missing'; end if;
  insert into public.review_media(review_id,customer_id,storage_path,media_type,duration_seconds)
  values(p_review_id,v_uid,p_storage_path,v_type,p_duration_seconds) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.attach_review_media(uuid,text,text,numeric) from public,anon;
grant execute on function private.attach_review_media(uuid,text,text,numeric) to authenticated;
create or replace function public.attach_review_media(
  p_review_id uuid,p_storage_path text,p_media_type text,p_duration_seconds numeric default null
) returns uuid language sql security invoker set search_path='' as $$
  select private.attach_review_media(p_review_id,p_storage_path,p_media_type,p_duration_seconds);
$$;
revoke all on function public.attach_review_media(uuid,text,text,numeric) from public,anon;
grant execute on function public.attach_review_media(uuid,text,text,numeric) to authenticated;