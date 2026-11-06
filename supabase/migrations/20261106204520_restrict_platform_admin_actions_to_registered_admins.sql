-- Separate registered administrators from moderators for platform-wide controls.
-- Catalog and review moderation retains the broader public.is_admin_actor() check.

create or replace function private.admin_get_return_policy_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  select jsonb_agg(to_jsonb(x) order by x.is_default desc, x.name)
  into v_result
  from (
    select
      '00000000-0000-0000-0000-000000000000'::uuid as category_id,
      'Toutes les catégories (par défaut)'::text as name,
      coalesce((
        select r.return_window_hours
        from private.return_policy_rules r
        where r.category_id = '00000000-0000-0000-0000-000000000000'::uuid
      ), 72) as return_window_hours,
      true as is_default
    union all
    select
      c.id,
      c.name,
      coalesce(
        r.return_window_hours,
        (
          select d.return_window_hours
          from private.return_policy_rules d
          where d.category_id = '00000000-0000-0000-0000-000000000000'::uuid
        ),
        72
      ),
      false
    from public.categories c
    left join private.return_policy_rules r on r.category_id = c.id
    where c.is_active = true
  ) x;

  return coalesce(v_result, '[]'::jsonb);
end;
$function$;

create or replace function private.admin_run_safe_platform_repairs()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  return private.run_safe_platform_repairs();
end;
$function$;

create or replace function private.admin_set_return_window(
  p_category_id uuid,
  p_hours integer
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_category uuid;
  v_previous integer;
begin
  if v_actor is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  if p_hours not in (24, 48, 72) then
    raise exception 'return_window_must_be_24_48_or_72_hours';
  end if;

  v_category := coalesce(
    p_category_id,
    '00000000-0000-0000-0000-000000000000'::uuid
  );

  select return_window_hours
  into v_previous
  from private.return_policy_rules
  where category_id = v_category
  for update;

  insert into private.return_policy_rules(
    category_id, return_window_hours, updated_at, updated_by
  )
  values(v_category, p_hours, now(), v_actor)
  on conflict(category_id) do update
    set return_window_hours = excluded.return_window_hours,
        updated_at = now(),
        updated_by = v_actor;

  insert into private.return_policy_audit(
    category_id, previous_window_hours, new_window_hours, actor_id
  )
  values(v_category, v_previous, p_hours, v_actor);

  return true;
end;
$function$;

create or replace function public.get_admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
begin
  if not private.is_admin() then
    raise exception 'admin access required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'users', (select count(*) from public.profiles),
    'sellers', (select count(*) from public.sellers),
    'shops', (select count(*) from public.shops),
    'active_products', (select count(*) from public.products where status = 'ACTIVE'),
    'orders', (select count(*) from public.orders),
    'open_support', (
      select count(*) from public.support_tickets
      where status not in ('RESOLVED', 'CLOSED')
    ),
    'fraud_reports', (
      select count(*) from public.fraud_reports
      where status not in ('RESOLVED', 'CLOSED')
    )
  );
end;
$function$;

create or replace function private.get_platform_health()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.component), '[]'::jsonb)
  into v_result
  from (
    select distinct on (component)
      component, status, response_ms, details, checked_at
    from private.platform_health_checks
    order by component, checked_at desc
  ) q;

  return v_result;
end;
$function$;

create or replace function private.get_platform_repair_audit(
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_result jsonb;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc), '[]'::jsonb)
  into v_result
  from (
    select id, repair_code, status, details, created_at
    from private.platform_repair_audit
    order by created_at desc
    limit greatest(1, least(coalesce(p_limit, 20), 100))
  ) q;

  return v_result;
end;
$function$;

create or replace function private.rollback_platform_repair(p_backup_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_backup private.platform_repair_backups%rowtype;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  select *
  into v_backup
  from private.platform_repair_backups
  where id = p_backup_id
  for update;

  if not found or v_backup.restored_at is not null then
    raise exception 'backup_not_available';
  end if;

  if v_backup.repair_code <> 'RELEASE_STALE_AI_SCAN_LOCK'
     or v_backup.target_table <> 'private.catalog_ai_product_scan_locks' then
    raise exception 'repair_not_reversible_by_this_handler';
  end if;

  insert into private.catalog_ai_product_scan_locks(
    product_id, locked_until, requested_at
  )
  values(
    (v_backup.before_data->>'product_id')::uuid,
    (v_backup.before_data->>'locked_until')::timestamptz,
    (v_backup.before_data->>'requested_at')::timestamptz
  )
  on conflict(product_id) do nothing;

  update private.platform_repair_backups
  set restored_at = now(), restored_by = auth.uid()
  where id = p_backup_id;

  insert into private.platform_repair_audit(repair_code, status, details)
  values(
    v_backup.repair_code,
    'ROLLED_BACK',
    jsonb_build_object('backup_id', p_backup_id)
  );

  return true;
end;
$function$;

create or replace function public.enforce_profile_security_fields()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if auth.uid() is null then
    return new;
  end if;

  if private.is_admin() then
    return new;
  end if;

  if new.status is distinct from old.status then
    raise exception 'profile_status_admin_only' using errcode = '42501';
  end if;

  if new.verification_status is distinct from old.verification_status then
    raise exception 'profile_verification_admin_only' using errcode = '42501';
  end if;

  return new;
end;
$function$;

create or replace function public.enforce_seller_document_review_fields()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if auth.uid() is null then
    return new;
  end if;

  if private.is_admin() then
    return new;
  end if;

  if new.verification_status is distinct from old.verification_status then
    raise exception 'document_verification_admin_only' using errcode = '42501';
  end if;

  if new.reviewed_by is distinct from old.reviewed_by then
    raise exception 'document_review_metadata_admin_only' using errcode = '42501';
  end if;

  if new.reviewed_at is distinct from old.reviewed_at then
    raise exception 'document_review_metadata_admin_only' using errcode = '42501';
  end if;

  return new;
end;
$function$;
