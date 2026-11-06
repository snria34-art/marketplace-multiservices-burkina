create or replace function public.deactivate_notification_device(
  p_push_token text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user uuid := (select auth.uid());
  v_token text := trim(coalesce(p_push_token, ''));
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if v_token = '' or length(v_token) > 4096 then
    raise exception 'invalid_device_token' using errcode = '22023';
  end if;

  -- Deliberately bypasses the active-account RLS guard so a suspended or
  -- blocked user can still revoke this own device token before signing out.
  update public.notification_devices
  set active = false,
      last_seen_at = now()
  where user_id = v_user
    and push_token = v_token
    and active = true;

  -- Idempotent success means no active row for this token remains for the
  -- authenticated user. An already inactive or absent token is safe to sign out.
  return not exists (
    select 1
    from public.notification_devices nd
    where nd.user_id = v_user
      and nd.push_token = v_token
      and nd.active = true
  );
end;
$function$;

revoke all on function public.deactivate_notification_device(text)
  from public, anon;
grant execute on function public.deactivate_notification_device(text)
  to authenticated, service_role;
