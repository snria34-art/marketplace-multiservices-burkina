create or replace function private.can_read_customer_delivery_media(p_storage_path text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select exists(
    select 1
    from public.delivery_evidence de
    join public.order_packages op on op.id=de.package_id
    join public.order_groups og on og.id=op.order_group_id
    join public.orders o on o.id=og.order_id
    where de.storage_path=p_storage_path and o.customer_id=(select auth.uid())
  );
$$;
revoke all on function private.can_read_customer_delivery_media(text) from public,anon;
grant execute on function private.can_read_customer_delivery_media(text) to authenticated;

drop policy if exists order_feedback_media_customer_delivery_read on storage.objects;
create policy order_feedback_media_customer_delivery_read on storage.objects
for select to authenticated
using (bucket_id='order-feedback-media' and (select private.can_read_customer_delivery_media(name)));

create or replace function private.get_customer_delivery_evidence(p_order_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_uid uuid := (select auth.uid()); v_result jsonb;
begin
  if v_uid is null or not private.is_active_account() then raise exception 'active_authentication_required'; end if;
  if not exists(select 1 from public.orders o where o.id=p_order_id and o.customer_id=v_uid) then
    raise exception 'order_not_owned';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'package_id',de.package_id,
    'evidence_type',de.evidence_type,
    'media_type',de.media_type,
    'storage_path',de.storage_path,
    'created_at',de.created_at
  ) order by de.created_at desc),'[]'::jsonb) into v_result
  from public.delivery_evidence de
  join public.order_packages op on op.id=de.package_id
  join public.order_groups og on og.id=op.order_group_id
  join public.orders o on o.id=og.order_id
  where o.id=p_order_id and o.customer_id=v_uid and de.evidence_type='DELIVERY';
  return v_result;
end;
$$;
revoke all on function private.get_customer_delivery_evidence(uuid) from public,anon;
grant execute on function private.get_customer_delivery_evidence(uuid) to authenticated;

create or replace function public.get_customer_delivery_evidence(p_order_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.get_customer_delivery_evidence(p_order_id);
$$;
revoke all on function public.get_customer_delivery_evidence(uuid) from public,anon;
grant execute on function public.get_customer_delivery_evidence(uuid) to authenticated;
