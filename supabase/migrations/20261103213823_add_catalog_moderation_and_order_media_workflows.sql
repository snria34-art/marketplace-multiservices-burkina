create table if not exists public.review_media (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.reviews(id) on delete cascade,
  customer_id uuid not null references public.profiles(id) on delete restrict,
  storage_path text not null unique,
  media_type text not null check (media_type in ('IMAGE','VIDEO')),
  duration_seconds numeric(5,2),
  created_at timestamptz not null default now(),
  constraint review_media_video_duration check (
    (media_type = 'IMAGE' and duration_seconds is null) or
    (media_type = 'VIDEO' and duration_seconds > 0 and duration_seconds <= 10)
  )
);
alter table public.review_media enable row level security;
revoke all on public.review_media from public, anon, authenticated;

create table if not exists public.delivery_evidence (
  id uuid primary key default gen_random_uuid(),
  package_id uuid not null references public.order_packages(id) on delete restrict,
  assignment_id uuid not null references public.delivery_assignments(id) on delete restrict,
  courier_id uuid not null references public.profiles(id) on delete restrict,
  evidence_type text not null check (evidence_type in ('PICKUP','DELIVERY')),
  media_type text not null check (media_type in ('IMAGE','VIDEO')),
  storage_path text not null unique,
  duration_seconds numeric(5,2),
  person_visible boolean not null default false,
  person_consent boolean not null default false,
  created_at timestamptz not null default now(),
  constraint delivery_evidence_video_duration check (
    (media_type = 'IMAGE' and duration_seconds is null) or
    (media_type = 'VIDEO' and duration_seconds > 0 and duration_seconds <= 6)
  ),
  constraint delivery_evidence_person_consent check (
    person_visible = false or person_consent = true
  ),
  constraint delivery_evidence_delivery_must_be_image check (
    evidence_type <> 'DELIVERY' or media_type = 'IMAGE'
  )
);
alter table public.delivery_evidence enable row level security;
revoke all on public.delivery_evidence from public, anon, authenticated;
create index if not exists delivery_evidence_package_idx on public.delivery_evidence(package_id, created_at desc);

create table if not exists private.catalog_moderation_audit (
  id uuid primary key default gen_random_uuid(),
  finding_id uuid not null references private.catalog_moderation_findings(id) on delete restrict,
  product_id uuid not null references public.products(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in ('REQUEST_INFO','SELLER_RESPONSE','CLEARED','REJECTED','LISTING_SUPPRESSED','LISTING_RESTORED')),
  note text,
  created_at timestamptz not null default now()
);
alter table private.catalog_moderation_audit enable row level security;
revoke all on private.catalog_moderation_audit from public, anon, authenticated;

create table if not exists private.catalog_moderation_responses (
  id uuid primary key default gen_random_uuid(),
  finding_id uuid not null references private.catalog_moderation_findings(id) on delete restrict,
  seller_user_id uuid not null references public.profiles(id) on delete restrict,
  response_text text not null check (length(trim(response_text)) between 5 and 2000),
  media_storage_path text,
  created_at timestamptz not null default now()
);
alter table private.catalog_moderation_responses enable row level security;
revoke all on private.catalog_moderation_responses from public, anon, authenticated;

create table if not exists private.product_listing_restrictions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  finding_id uuid not null references private.catalog_moderation_findings(id) on delete restrict,
  previous_status text not null,
  reason text not null,
  active boolean not null default true,
  applied_by uuid not null references public.profiles(id) on delete restrict,
  applied_at timestamptz not null default now(),
  restored_by uuid references public.profiles(id) on delete restrict,
  restored_at timestamptz
);
create unique index if not exists product_listing_restrictions_one_active
  on private.product_listing_restrictions(product_id) where active;
alter table private.product_listing_restrictions enable row level security;
revoke all on private.product_listing_restrictions from public, anon, authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'order-feedback-media','order-feedback-media',false,5242880,
  array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime']
)
on conflict (id) do update set
  public=false,
  file_size_limit=5242880,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists order_feedback_media_owner_insert on storage.objects;
create policy order_feedback_media_owner_insert on storage.objects
for insert to authenticated
with check (
  bucket_id='order-feedback-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (select private.is_active_account())
);
drop policy if exists order_feedback_media_owner_read on storage.objects;
create policy order_feedback_media_owner_read on storage.objects
for select to authenticated
using (
  bucket_id='order-feedback-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (select private.is_active_account())
);
drop policy if exists order_feedback_media_owner_delete on storage.objects;
create policy order_feedback_media_owner_delete on storage.objects
for delete to authenticated
using (
  bucket_id='order-feedback-media'
  and (storage.foldername(name))[1]=(select auth.uid())::text
  and (select private.is_active_account())
);

create or replace function public.attach_review_media(
  p_review_id uuid,
  p_storage_path text,
  p_media_type text,
  p_duration_seconds numeric default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_id uuid;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if p_storage_path is null or split_part(p_storage_path,'/',1) <> v_uid::text
     or split_part(p_storage_path,'/',2) <> 'reviews' then raise exception 'invalid_media_path'; end if;
  if not exists (select 1 from public.reviews r where r.id=p_review_id and r.customer_id=v_uid) then
    raise exception 'review_not_owned';
  end if;
  if not exists (select 1 from storage.objects o where o.bucket_id='order-feedback-media' and o.name=p_storage_path) then
    raise exception 'media_object_missing';
  end if;
  insert into public.review_media(review_id,customer_id,storage_path,media_type,duration_seconds)
  values(p_review_id,v_uid,p_storage_path,upper(p_media_type),p_duration_seconds)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.attach_review_media(uuid,text,text,numeric) from public, anon;
grant execute on function public.attach_review_media(uuid,text,text,numeric) to authenticated;

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
  insert into public.delivery_events(package_id,actor_id,status,metadata)
  select p_package_id,v_uid,op.status_value::public.delivery_status,
    jsonb_build_object('evidence_id',v_id,'evidence_type',upper(p_evidence_type),'media_type',upper(p_media_type))
  from (select case when upper(p_evidence_type)='PICKUP' then 'PICKED_UP' else 'DELIVERED' end as status_value) op;
  return v_id;
end;
$$;
revoke all on function public.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) from public, anon;
grant execute on function public.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) to authenticated;

create or replace function public.seller_respond_to_catalog_finding(
  p_finding_id uuid,
  p_response_text text,
  p_media_storage_path text default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_seller uuid; v_shop uuid; v_id uuid; v_product uuid;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if length(trim(coalesce(p_response_text,''))) < 5 or length(p_response_text)>2000 then raise exception 'invalid_response_text'; end if;
  select p.id,p.shop_id,s.seller_id into v_product,v_shop,v_seller
  from private.catalog_moderation_findings f
  join public.products p on p.id=f.product_id
  join public.sellers s on s.id=(select sh.seller_id from public.shops sh where sh.id=p.shop_id)
  where f.id=p_finding_id;
  if v_seller is null or not exists (select 1 from public.sellers s where s.id=v_seller and s.user_id=v_uid) then
    raise exception 'seller_not_owner';
  end if;
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
  return v_id;
end;
$$;
revoke all on function public.seller_respond_to_catalog_finding(uuid,text,text) from public, anon;
grant execute on function public.seller_respond_to_catalog_finding(uuid,text,text) to authenticated;

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
  select coalesce(jsonb_agg(row_data order by detected_at desc),'[]'::jsonb) into v_result
  from (
    select f.id as finding_id,f.product_id,f.rule_code,f.severity,f.matched_terms,f.explanation,
      f.status,f.detected_at,f.review_notes,
      jsonb_build_object('id',p.id,'name',p.name,'description',p.description,'status',p.status,'price',p.price) as product,
      jsonb_build_object('id',sh.id,'name',sh.name,'seller_id',sh.seller_id,'seller_name',pr.display_name) as shop,
      coalesce((select jsonb_agg(jsonb_build_object('storage_path',pi.storage_path,'alt_text',pi.alt_text) order by pi.sort_order)
        from public.product_images pi where pi.product_id=p.id),'[]'::jsonb) as images,
      (select to_jsonb(resp) from private.catalog_moderation_responses resp where resp.finding_id=f.id order by resp.created_at desc limit 1) as latest_seller_response,
      f.detected_at
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
revoke all on function public.admin_get_catalog_moderation_queue(integer) from public, anon;
grant execute on function public.admin_get_catalog_moderation_queue(integer) to authenticated;

create or replace function public.admin_decide_catalog_finding(
  p_finding_id uuid,
  p_decision text,
  p_note text
) returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_product uuid; v_previous text; v_decision text := upper(trim(p_decision));
begin
  if v_uid is null or not private.is_active_account() or not public.is_admin_actor() then raise exception 'admin_access_required'; end if;
  if length(trim(coalesce(p_note,''))) < 3 or length(p_note)>2000 then raise exception 'decision_note_required'; end if;
  select product_id into v_product from private.catalog_moderation_findings
  where id=p_finding_id for update;
  if v_product is null then raise exception 'finding_not_found'; end if;
  if v_decision='REQUEST_INFO' then
    update private.catalog_moderation_findings set status='UNDER_REVIEW',review_notes=trim(p_note) where id=p_finding_id;
  elsif v_decision='CLEAR' then
    update private.catalog_moderation_findings set status='CLEARED',reviewed_by=v_uid,reviewed_at=now(),review_notes=trim(p_note) where id=p_finding_id;
    update private.product_listing_restrictions set active=false,restored_by=v_uid,restored_at=now()
      where product_id=v_product and active=true returning previous_status into v_previous;
    if v_previous is not null then
      update public.products set status=v_previous::public.product_status,updated_at=now() where id=v_product and status='INACTIVE';
      insert into private.catalog_moderation_audit(finding_id,product_id,actor_id,action,note)
      values(p_finding_id,v_product,v_uid,'LISTING_RESTORED',trim(p_note));
    end if;
  elsif v_decision='REJECT' then
    update private.catalog_moderation_findings set status='REJECTED',reviewed_by=v_uid,reviewed_at=now(),review_notes=trim(p_note) where id=p_finding_id;
    select status::text into v_previous from public.products where id=v_product for update;
    insert into private.product_listing_restrictions(product_id,finding_id,previous_status,reason,applied_by)
    values(v_product,p_finding_id,v_previous,trim(p_note),v_uid)
    on conflict (product_id) where active do nothing;
    update public.products set status='INACTIVE',updated_at=now() where id=v_product and status<>'INACTIVE';
    insert into private.catalog_moderation_audit(finding_id,product_id,actor_id,action,note)
    values(p_finding_id,v_product,v_uid,'LISTING_SUPPRESSED',trim(p_note));
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
revoke all on function public.admin_decide_catalog_finding(uuid,text,text) from public, anon;
grant execute on function public.admin_decide_catalog_finding(uuid,text,text) to authenticated;
