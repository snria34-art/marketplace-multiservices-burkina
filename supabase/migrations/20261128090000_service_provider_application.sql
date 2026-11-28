begin;

-- First provider onboarding step: create a pending provider profile.
-- Verification remains an explicit administrative action; no provider is
-- made public or bookable by submitting this application.
create or replace function public.submit_service_provider_application(
  p_provider_type text,
  p_display_name text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = 'pg_catalog, public, private, pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  v_type text := upper(pg_catalog.btrim(coalesce(p_provider_type, '')));
  v_name text := nullif(pg_catalog.btrim(p_display_name), '');
  v_description text := nullif(pg_catalog.btrim(p_description), '');
  v_status public.account_status;
  v_provider_id uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select p.status into v_status
  from public.profiles p
  where p.id = v_user;

  if not found or v_status <> 'ACTIVE'::public.account_status then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  if v_type not in (
    'TAXI',
    'MOTO_TAXI',
    'VTC',
    'VEHICLE_RENTAL',
    'TRANSPORT_COMPANY',
    'FREIGHT',
    'COURIER'
  ) then
    raise exception 'unsupported_provider_type' using errcode = '22023';
  end if;

  if v_name is null or pg_catalog.char_length(v_name) < 2
     or pg_catalog.char_length(v_name) > 100 then
    raise exception 'invalid_provider_name' using errcode = '22023';
  end if;

  if v_description is not null and pg_catalog.char_length(v_description) > 1000 then
    raise exception 'invalid_provider_description' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.service_providers sp
    where sp.user_id = v_user
  ) then
    raise exception 'provider_application_already_exists' using errcode = '23505';
  end if;

  insert into public.service_providers(
    user_id, provider_type, display_name, description,
    verification_status, active
  )
  values (
    v_user, v_type, v_name, v_description,
    'PENDING'::public.verification_status, false
  )
  returning id into v_provider_id;

  insert into public.user_roles(user_id, role)
  values (v_user, 'SERVICE_PROVIDER'::public.user_role)
  on conflict (user_id, role) do nothing;

  return v_provider_id;
end;
$function$;

revoke all on function public.submit_service_provider_application(text,text,text)
  from public, anon;
grant execute on function public.submit_service_provider_application(text,text,text)
  to authenticated;

commit;
