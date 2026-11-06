create or replace function private.expire_seller_access_requests_internal()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer;
begin
  with expired as (
    update private.seller_access_requests
    set status='EXPIRED'
    where status='APPROVED'
      and expires_at is not null
      and expires_at <= now()
    returning id
  )
  insert into private.seller_access_audit(request_id,event_type,event_details)
  select id,'EXPIRED','{"reason":"validity_period_elapsed","source":"scheduled_job"}'::jsonb
  from expired;
  get diagnostics v_count = row_count;
  return v_count;
end;
$function$;

revoke all on function private.expire_seller_access_requests_internal() from public, anon, authenticated;

create or replace function public.expire_seller_access_requests()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'Accès administrateur requis' using errcode='42501';
  end if;
  select private.expire_seller_access_requests_internal() into v_count;
  return v_count;
end;
$function$;

revoke all on function public.expire_seller_access_requests() from public, anon;
grant execute on function public.expire_seller_access_requests() to authenticated;

select cron.schedule(
  'expire-seller-access-requests',
  '*/5 * * * *',
  $$select private.expire_seller_access_requests_internal();$$
);
