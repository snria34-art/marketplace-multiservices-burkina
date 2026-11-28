begin;

-- Admin-managed, customer-safe configuration only.
-- Payment providers, commissions, pricing and payment rules are intentionally excluded.
insert into public.platform_settings(key, value)
values
  (
    'platform_profile',
    jsonb_build_object(
      'name', 'Marketplace Multiservices Burkina',
      'country_code', 'BF',
      'currency', 'XOF',
      'locale', 'fr',
      'timezone', 'Africa/Ouagadougou'
    )
  ),
  (
    'support_contacts',
    jsonb_build_object('phone', '', 'whatsapp', '', 'email', '')
  ),
  (
    'public_announcement',
    jsonb_build_object(
      'enabled', false,
      'title', '',
      'message', '',
      'severity', 'info'
    )
  )
on conflict (key) do nothing;

create or replace function public.admin_upsert_marketplace_setting(
  p_key text,
  p_value jsonb
)
returns boolean
language plpgsql
security definer
set search_path = 'pg_catalog, public, private, pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  v_key text := nullif(pg_catalog.btrim(p_key), '');
  v_value jsonb;
  v_name text;
  v_phone text;
  v_whatsapp text;
  v_email text;
  v_enabled boolean;
  v_title text;
  v_message text;
  v_severity text;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if not (select private.is_admin()) then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  if v_key is null or p_value is null or pg_catalog.jsonb_typeof(p_value) <> 'object' then
    raise exception 'invalid_setting_payload' using errcode = '22023';
  end if;

  case v_key
    when 'platform_profile' then
      v_name := nullif(pg_catalog.btrim(p_value ->> 'name'), '');
      if v_name is null or pg_catalog.char_length(v_name) > 80 then
        raise exception 'invalid_platform_name' using errcode = '22023';
      end if;

      -- Burkina Faso-specific identity is deliberately fixed in this first version.
      v_value := pg_catalog.jsonb_build_object(
        'name', v_name,
        'country_code', 'BF',
        'currency', 'XOF',
        'locale', 'fr',
        'timezone', 'Africa/Ouagadougou'
      );

    when 'support_contacts' then
      v_phone := nullif(pg_catalog.btrim(p_value ->> 'phone'), '');
      v_whatsapp := nullif(pg_catalog.btrim(p_value ->> 'whatsapp'), '');
      v_email := nullif(pg_catalog.btrim(p_value ->> 'email'), '');

      if (v_phone is not null and
          (pg_catalog.char_length(v_phone) > 30 or v_phone !~ '^[+0-9][0-9 ()-]{5,28}$'))
         or (v_whatsapp is not null and
          (pg_catalog.char_length(v_whatsapp) > 30 or v_whatsapp !~ '^[+0-9][0-9 ()-]{5,28}$'))
         or (v_email is not null and
          (pg_catalog.char_length(v_email) > 254 or v_email !~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$')) then
        raise exception 'invalid_support_contact' using errcode = '22023';
      end if;

      v_value := pg_catalog.jsonb_build_object(
        'phone', coalesce(v_phone, ''),
        'whatsapp', coalesce(v_whatsapp, ''),
        'email', coalesce(v_email, '')
      );

    when 'public_announcement' then
      if pg_catalog.jsonb_typeof(p_value -> 'enabled') is distinct from 'boolean' then
        raise exception 'invalid_announcement_enabled' using errcode = '22023';
      end if;

      v_enabled := (p_value ->> 'enabled')::boolean;
      v_title := coalesce(pg_catalog.btrim(p_value ->> 'title'), '');
      v_message := coalesce(pg_catalog.btrim(p_value ->> 'message'), '');
      v_severity := coalesce(p_value ->> 'severity', 'info');

      if pg_catalog.char_length(v_title) > 120
         or pg_catalog.char_length(v_message) > 600
         or v_severity not in ('info', 'warning', 'success')
         or (v_enabled and (v_title = '' or v_message = '')) then
        raise exception 'invalid_public_announcement' using errcode = '22023';
      end if;

      v_value := pg_catalog.jsonb_build_object(
        'enabled', v_enabled,
        'title', v_title,
        'message', v_message,
        'severity', v_severity
      );

    else
      -- Financial settings and all payment-related keys
      -- cannot be changed through this operational settings endpoint.
      raise exception 'setting_not_editable' using errcode = '22023';
  end case;

  insert into public.platform_settings(key, value, updated_by, updated_at)
  values (v_key, v_value, v_user, pg_catalog.now())
  on conflict (key) do update
    set value = excluded.value,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;

  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  values (
    v_user,
    'ADMIN_PLATFORM_SETTING_UPDATED',
    'platform_setting',
    null,
    pg_catalog.jsonb_build_object('key', v_key)
  );

  return true;
end;
$function$;

revoke all on function public.admin_upsert_marketplace_setting(text, jsonb)
  from public, anon;
grant execute on function public.admin_upsert_marketplace_setting(text, jsonb)
  to authenticated;

create or replace function public.get_public_marketplace_settings()
returns jsonb
language sql
stable
security definer
set search_path = 'pg_catalog, public, private, pg_temp'
as $function$
  select coalesce(
    pg_catalog.jsonb_object_agg(ps.key, ps.value),
    '{}'::jsonb
  )
  from public.platform_settings ps
  where ps.key in (
    'platform_profile',
    'support_contacts',
    'public_announcement'
  );
$function$;

revoke all on function public.get_public_marketplace_settings()
  from public;
grant execute on function public.get_public_marketplace_settings()
  to anon, authenticated;

commit;
