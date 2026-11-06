alter table public.product_images
  add column if not exists image_role text not null default 'PRODUCT';
do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.product_images'::regclass and conname='product_images_image_role_check') then
    alter table public.product_images add constraint product_images_image_role_check
      check (image_role in ('PRODUCT','PACKAGING','LABEL'));
  end if;
end $$;
create index if not exists product_images_product_role_idx on public.product_images(product_id,image_role,sort_order);

alter table private.catalog_moderation_findings
  add column if not exists ai_model text,
  add column if not exists ai_confidence numeric(4,3),
  add column if not exists ai_analysis jsonb,
  add column if not exists ai_analyzed_at timestamptz;

create table if not exists private.catalog_ai_product_scans (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  model text not null,
  decision text not null check (decision in ('CLEAR','REVIEW','HIGH_RISK')),
  confidence numeric(4,3) not null check (confidence between 0 and 1),
  result jsonb not null,
  image_count integer not null default 0 check (image_count >= 0 and image_count <= 10),
  scanned_at timestamptz not null default now()
);
create index if not exists catalog_ai_scans_product_time_idx on private.catalog_ai_product_scans(product_id,scanned_at desc);
alter table private.catalog_ai_product_scans enable row level security;
revoke all on private.catalog_ai_product_scans from public,anon,authenticated;

create or replace function private.add_seller_product_image(
  p_product_id uuid,
  p_storage_path text,
  p_image_role text,
  p_alt_text text default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_id uuid; v_seller uuid; v_shop uuid; v_sort integer;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if upper(p_image_role) not in ('PRODUCT','PACKAGING','LABEL') then raise exception 'invalid_image_role'; end if;
  if split_part(coalesce(p_storage_path,''),'/',1)<>'products'
     or split_part(coalesce(p_storage_path,''),'/',2)<>p_product_id::text then raise exception 'invalid_product_media_path'; end if;
  select p.shop_id,sh.seller_id into v_shop,v_seller
  from public.products p join public.shops sh on sh.id=p.shop_id where p.id=p_product_id;
  if v_shop is null or not exists(select 1 from public.sellers s where s.id=v_seller and s.user_id=v_uid) then
    raise exception 'product_not_owned';
  end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='product-media' and o.name=p_storage_path) then
    raise exception 'media_object_missing';
  end if;
  select coalesce(max(sort_order),0)+1 into v_sort from public.product_images where product_id=p_product_id;
  insert into public.product_images(product_id,storage_path,sort_order,alt_text,image_role)
  values(p_product_id,p_storage_path,v_sort,left(p_alt_text,300),upper(p_image_role))
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function private.add_seller_product_image(uuid,text,text,text) from public,anon;
grant execute on function private.add_seller_product_image(uuid,text,text,text) to authenticated;

create or replace function public.add_seller_product_image(p_product_id uuid,p_storage_path text,p_image_role text,p_alt_text text default null)
returns uuid language sql security invoker set search_path='' as $$
  select private.add_seller_product_image(p_product_id,p_storage_path,p_image_role,p_alt_text);
$$;
revoke all on function public.add_seller_product_image(uuid,text,text,text) from public,anon;
grant execute on function public.add_seller_product_image(uuid,text,text,text) to authenticated;

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
  return true;
end;
$$;
revoke all on function private.submit_seller_product_for_review(uuid) from public,anon;
grant execute on function private.submit_seller_product_for_review(uuid) to authenticated;

create or replace function public.submit_seller_product_for_review(p_product_id uuid)
returns boolean language sql security invoker set search_path='' as $$
  select private.submit_seller_product_for_review(p_product_id);
$$;
revoke all on function public.submit_seller_product_for_review(uuid) from public,anon;
grant execute on function public.submit_seller_product_for_review(uuid) to authenticated;

create or replace function private.record_ai_product_analysis(
  p_product_id uuid,
  p_model text,
  p_result jsonb,
  p_image_count integer
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_scan uuid; v_decision text; v_severity text; v_confidence numeric; v_terms text[]; v_explanation text;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role_required'; end if;
  if not exists(select 1 from public.products where id=p_product_id) then raise exception 'product_not_found'; end if;
  v_decision := upper(coalesce(p_result->>'decision','REVIEW'));
  if v_decision not in ('CLEAR','REVIEW','HIGH_RISK') then v_decision := 'REVIEW'; end if;
  v_confidence := greatest(0,least(1,coalesce((p_result->>'confidence')::numeric,0.5)));
  v_severity := case
    when v_decision='HIGH_RISK' and coalesce((p_result->>'critical')::boolean,false) then 'CRITICAL'
    when v_decision='HIGH_RISK' then 'HIGH'
    else 'REVIEW'
  end;
  select coalesce(array_agg(value),'{}'::text[]) into v_terms
  from jsonb_array_elements_text(coalesce(p_result->'categories','[]'::jsonb) || coalesce(p_result->'mismatches','[]'::jsonb)) as t(value);
  v_explanation := left(coalesce(p_result->>'summary','Analyse IA terminée; validation administrative requise.'),4000);
  insert into private.catalog_ai_product_scans(product_id,model,decision,confidence,result,image_count)
  values(p_product_id,left(coalesce(p_model,'unknown'),100),v_decision,v_confidence,p_result,greatest(0,least(10,coalesce(p_image_count,0))))
  returning id into v_scan;
  insert into private.catalog_moderation_findings(
    product_id,rule_code,severity,matched_terms,explanation,status,ai_model,ai_confidence,ai_analysis,ai_analyzed_at
  ) values (
    p_product_id,'AI_PRODUCT_REVIEW',v_severity,v_terms,v_explanation,'OPEN',
    left(coalesce(p_model,'unknown'),100),v_confidence,p_result,now()
  )
  on conflict(product_id,rule_code) do update set
    severity=excluded.severity,matched_terms=excluded.matched_terms,explanation=excluded.explanation,
    status=case when private.catalog_moderation_findings.status in ('CLEARED','REJECTED') then 'OPEN' else private.catalog_moderation_findings.status end,
    ai_model=excluded.ai_model,ai_confidence=excluded.ai_confidence,ai_analysis=excluded.ai_analysis,ai_analyzed_at=now(),
    detected_at=now();
  insert into private.platform_agent_runs(agent_code,started_at,finished_at,status,findings_count,details)
  values('AI_PRODUCT_VISION',now(),now(),'OK',1,jsonb_build_object('product_id',p_product_id,'scan_id',v_scan,'decision',v_decision,'confidence',v_confidence));
  return v_scan;
end;
$$;
revoke all on function private.record_ai_product_analysis(uuid,text,jsonb,integer) from public,anon,authenticated;
grant execute on function private.record_ai_product_analysis(uuid,text,jsonb,integer) to service_role;
grant usage on schema private to service_role;

create or replace function public.record_ai_product_analysis(p_product_id uuid,p_model text,p_result jsonb,p_image_count integer)
returns uuid language sql security invoker set search_path='' as $$
  select private.record_ai_product_analysis(p_product_id,p_model,p_result,p_image_count);
$$;
revoke all on function public.record_ai_product_analysis(uuid,text,jsonb,integer) from public,anon,authenticated;
grant execute on function public.record_ai_product_analysis(uuid,text,jsonb,integer) to service_role;
