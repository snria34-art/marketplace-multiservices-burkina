create index if not exists review_media_review_created_idx on public.review_media(review_id,created_at desc);
create index if not exists review_media_customer_idx on public.review_media(customer_id);
create index if not exists delivery_evidence_assignment_idx on public.delivery_evidence(assignment_id,created_at desc);
create index if not exists delivery_evidence_courier_idx on public.delivery_evidence(courier_id,created_at desc);
create index if not exists catalog_moderation_audit_finding_idx on private.catalog_moderation_audit(finding_id,created_at desc);
create index if not exists catalog_moderation_audit_product_idx on private.catalog_moderation_audit(product_id,created_at desc);
create index if not exists catalog_moderation_audit_actor_idx on private.catalog_moderation_audit(actor_id,created_at desc);
create index if not exists catalog_moderation_responses_finding_idx on private.catalog_moderation_responses(finding_id,created_at desc);
create index if not exists catalog_moderation_responses_seller_idx on private.catalog_moderation_responses(seller_user_id,created_at desc);
create index if not exists product_listing_restrictions_finding_idx on private.product_listing_restrictions(finding_id);
create index if not exists product_listing_restrictions_applied_by_idx on private.product_listing_restrictions(applied_by);
create index if not exists product_listing_restrictions_restored_by_idx on private.product_listing_restrictions(restored_by);

alter function public.attach_review_media(uuid,text,text,numeric) set schema private;
alter function public.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) set schema private;
alter function public.seller_respond_to_catalog_finding(uuid,text,text) set schema private;
alter function public.admin_get_catalog_moderation_queue(integer) set schema private;
alter function public.admin_decide_catalog_finding(uuid,text,text) set schema private;

grant usage on schema private to authenticated;
grant execute on function private.attach_review_media(uuid,text,text,numeric) to authenticated;
grant execute on function private.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) to authenticated;
grant execute on function private.seller_respond_to_catalog_finding(uuid,text,text) to authenticated;
grant execute on function private.admin_get_catalog_moderation_queue(integer) to authenticated;
grant execute on function private.admin_decide_catalog_finding(uuid,text,text) to authenticated;
revoke all on function private.attach_review_media(uuid,text,text,numeric) from public,anon;
revoke all on function private.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) from public,anon;
revoke all on function private.seller_respond_to_catalog_finding(uuid,text,text) from public,anon;
revoke all on function private.admin_get_catalog_moderation_queue(integer) from public,anon;
revoke all on function private.admin_decide_catalog_finding(uuid,text,text) from public,anon;

create or replace function public.attach_review_media(p_review_id uuid,p_storage_path text,p_media_type text,p_duration_seconds numeric default null)
returns uuid language sql security invoker set search_path='' as $$
  select private.attach_review_media(p_review_id,p_storage_path,p_media_type,p_duration_seconds);
$$;
create or replace function public.attach_delivery_evidence(p_package_id uuid,p_storage_path text,p_media_type text,p_evidence_type text,p_duration_seconds numeric default null,p_person_visible boolean default false,p_person_consent boolean default false)
returns uuid language sql security invoker set search_path='' as $$
  select private.attach_delivery_evidence(p_package_id,p_storage_path,p_media_type,p_evidence_type,p_duration_seconds,p_person_visible,p_person_consent);
$$;
create or replace function public.seller_respond_to_catalog_finding(p_finding_id uuid,p_response_text text,p_media_storage_path text default null)
returns uuid language sql security invoker set search_path='' as $$
  select private.seller_respond_to_catalog_finding(p_finding_id,p_response_text,p_media_storage_path);
$$;
create or replace function public.admin_get_catalog_moderation_queue(p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.admin_get_catalog_moderation_queue(p_limit);
$$;
create or replace function public.admin_decide_catalog_finding(p_finding_id uuid,p_decision text,p_note text)
returns boolean language sql security invoker set search_path='' as $$
  select private.admin_decide_catalog_finding(p_finding_id,p_decision,p_note);
$$;

revoke all on function public.attach_review_media(uuid,text,text,numeric) from public,anon;
revoke all on function public.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) from public,anon;
revoke all on function public.seller_respond_to_catalog_finding(uuid,text,text) from public,anon;
revoke all on function public.admin_get_catalog_moderation_queue(integer) from public,anon;
revoke all on function public.admin_decide_catalog_finding(uuid,text,text) from public,anon;
grant execute on function public.attach_review_media(uuid,text,text,numeric) to authenticated;
grant execute on function public.attach_delivery_evidence(uuid,text,text,text,numeric,boolean,boolean) to authenticated;
grant execute on function public.seller_respond_to_catalog_finding(uuid,text,text) to authenticated;
grant execute on function public.admin_get_catalog_moderation_queue(integer) to authenticated;
grant execute on function public.admin_decide_catalog_finding(uuid,text,text) to authenticated;
