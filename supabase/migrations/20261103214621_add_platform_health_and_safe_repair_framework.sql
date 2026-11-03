create table if not exists private.platform_health_checks (
  id uuid primary key default gen_random_uuid(),
  component text not null check (component in (
    'SUPABASE_AUTH','SUPABASE_REST','SUPABASE_STORAGE','NETWORK',
    'WAVE','CINETPAY','OPENAI','EDGE_FUNCTIONS'
  )),
  status text not null check (status in ('UP','DEGRADED','DOWN','NOT_CONFIGURED','NOT_TESTED')),
  response_ms integer,
  details jsonb not null default '{}'::jsonb,
  checked_at timestamptz not null default now()
);
create index if not exists platform_health_checks_component_time_idx
  on private.platform_health_checks(component,checked_at desc);
alter table private.platform_health_checks enable row level security;
revoke all on private.platform_health_checks from public,anon,authenticated;

create table if not exists private.platform_repair_backups (
  id uuid primary key default gen_random_uuid(),
  repair_code text not null,
  target_table text not null,
  target_key text not null,
  before_data jsonb not null,
  created_at timestamptz not null default now(),
  restored_at timestamptz,
  restored_by uuid references public.profiles(id) on delete restrict
);
create index if not exists platform_repair_backups_code_time_idx
  on private.platform_repair_backups(repair_code,created_at desc);
alter table private.platform_repair_backups enable row level security;
revoke all on private.platform_repair_backups from public,anon,authenticated;

create table if not exists private.platform_repair_audit (
  id uuid primary key default gen_random_uuid(),
  repair_code text not null,
  status text not null check (status in ('APPLIED','SKIPPED','FAILED','ROLLED_BACK')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists platform_repair_audit_time_idx
  on private.platform_repair_audit(created_at desc);
alter table private.platform_repair_audit enable row level security;
revoke all on private.platform_repair_audit from public,anon,authenticated;

create or replace function private.record_platform_health_checks(p_results jsonb)
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_item jsonb; v_count integer := 0; v_has_down boolean := false; v_has_degraded boolean := false;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role_required'; end if;
  if jsonb_typeof(p_results) <> 'array' or jsonb_array_length(p_results) > 20 then
    raise exception 'invalid_health_payload';
  end if;
  for v_item in select value from jsonb_array_elements(p_results)
  loop
    if v_item->>'component' not in ('SUPABASE_AUTH','SUPABASE_REST','SUPABASE_STORAGE','NETWORK','WAVE','CINETPAY','OPENAI','EDGE_FUNCTIONS')
      or v_item->>'status' not in ('UP','DEGRADED','DOWN','NOT_CONFIGURED','NOT_TESTED') then
      raise exception 'invalid_health_component';
    end if;
    insert into private.platform_health_checks(component,status,response_ms,details)
    values(
      v_item->>'component',
      v_item->>'status',
      case when (v_item->>'response_ms') ~ '^[0-9]+$' then (v_item->>'response_ms')::integer else null end,
      coalesce(v_item->'details','{}'::jsonb)
    );
    v_count := v_count + 1;
    v_has_down := v_has_down or v_item->>'status'='DOWN';
    v_has_degraded := v_has_degraded or v_item->>'status' in ('DEGRADED','NOT_CONFIGURED');
  end loop;
  insert into private.platform_agent_runs(agent_code,started_at,finished_at,status,findings_count,details)
  values(
    'PLATFORM_HEALTH_MONITOR',now(),now(),
    case when v_has_down then 'ERROR' when v_has_degraded then 'DEGRADED' else 'OK' end,
    (select count(*) from jsonb_array_elements(p_results) x where x->>'status' in ('DOWN','DEGRADED','NOT_CONFIGURED')),
    jsonb_build_object('components_checked',v_count)
  );
  return v_count;
end;
$$;
revoke all on function private.record_platform_health_checks(jsonb) from public,anon,authenticated;
grant execute on function private.record_platform_health_checks(jsonb) to service_role;
grant usage on schema private to service_role;

create or replace function public.record_platform_health_checks(p_results jsonb)
returns integer language sql security invoker set search_path='' as $$
  select private.record_platform_health_checks(p_results);
$$;
revoke all on function public.record_platform_health_checks(jsonb) from public,anon,authenticated;
grant execute on function public.record_platform_health_checks(jsonb) to service_role;

create or replace function private.get_platform_health()
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
  select coalesce(jsonb_agg(to_jsonb(q) order by q.component),'[]'::jsonb) into v_result
  from (
    select distinct on (component) component,status,response_ms,details,checked_at
    from private.platform_health_checks
    order by component,checked_at desc
  ) q;
  return v_result;
end;
$$;
revoke all on function private.get_platform_health() from public,anon;
grant execute on function private.get_platform_health() to authenticated;

create or replace function public.get_platform_health()
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.get_platform_health();
$$;
revoke all on function public.get_platform_health() from public,anon;
grant execute on function public.get_platform_health() to authenticated;

create or replace function private.run_safe_platform_repairs()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_lock record; v_backup uuid; v_count integer := 0;
begin
  for v_lock in
    select * from private.catalog_ai_product_scan_locks
    where locked_until < now()-interval '20 minutes'
    order by requested_at
    for update skip locked
  loop
    insert into private.platform_repair_backups(
      repair_code,target_table,target_key,before_data
    ) values(
      'RELEASE_STALE_AI_SCAN_LOCK','private.catalog_ai_product_scan_locks',
      v_lock.product_id::text,to_jsonb(v_lock)
    ) returning id into v_backup;
    delete from private.catalog_ai_product_scan_locks where product_id=v_lock.product_id;
    insert into private.platform_repair_audit(repair_code,status,details)
    values(
      'RELEASE_STALE_AI_SCAN_LOCK','APPLIED',
      jsonb_build_object('backup_id',v_backup,'product_id',v_lock.product_id)
    );
    v_count := v_count + 1;
  end loop;
  if v_count=0 then
    insert into private.platform_repair_audit(repair_code,status,details)
    values('RELEASE_STALE_AI_SCAN_LOCK','SKIPPED',jsonb_build_object('reason','no_stale_locks'));
  end if;
  insert into private.platform_agent_runs(agent_code,started_at,finished_at,status,findings_count,details)
  values('SAFE_PLATFORM_REPAIR',now(),now(),'OK',v_count,jsonb_build_object('repair_code','RELEASE_STALE_AI_SCAN_LOCK'));
  return v_count;
end;
$$;
revoke all on function private.run_safe_platform_repairs() from public,anon,authenticated;

create or replace function private.rollback_platform_repair(p_backup_id uuid)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_backup private.platform_repair_backups%rowtype;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  select * into v_backup from private.platform_repair_backups where id=p_backup_id for update;
  if not found or v_backup.restored_at is not null then raise exception 'backup_not_available'; end if;
  if v_backup.repair_code <> 'RELEASE_STALE_AI_SCAN_LOCK'
     or v_backup.target_table <> 'private.catalog_ai_product_scan_locks' then
    raise exception 'repair_not_reversible_by_this_handler';
  end if;
  insert into private.catalog_ai_product_scan_locks(product_id,locked_until,requested_at)
  values(
    (v_backup.before_data->>'product_id')::uuid,
    (v_backup.before_data->>'locked_until')::timestamptz,
    (v_backup.before_data->>'requested_at')::timestamptz
  )
  on conflict(product_id) do nothing;
  update private.platform_repair_backups
  set restored_at=now(),restored_by=auth.uid()
  where id=p_backup_id;
  insert into private.platform_repair_audit(repair_code,status,details)
  values(v_backup.repair_code,'ROLLED_BACK',jsonb_build_object('backup_id',p_backup_id));
  return true;
end;
$$;
revoke all on function private.rollback_platform_repair(uuid) from public,anon;
grant execute on function private.rollback_platform_repair(uuid) to authenticated;

do $$
begin
  if not exists(select 1 from cron.job where jobname='platform-safe-repairs') then
    perform cron.schedule('platform-safe-repairs','*/15 * * * *','select private.run_safe_platform_repairs();');
  end if;
end $$;
