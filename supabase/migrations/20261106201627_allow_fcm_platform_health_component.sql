-- Add the FCM component to the allowlist accepted by the private health recorder.
-- Keep the existing service_role-only execution guard, SECURITY DEFINER and empty search_path.

create or replace function private.record_platform_health_checks(p_results jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_item jsonb;
  v_count integer := 0;
  v_has_down boolean := false;
  v_has_degraded boolean := false;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service_role_required';
  end if;

  if jsonb_typeof(p_results) <> 'array'
     or jsonb_array_length(p_results) > 20 then
    raise exception 'invalid_health_payload';
  end if;

  for v_item in
    select value from jsonb_array_elements(p_results)
  loop
    if v_item->>'component' not in (
      'SUPABASE_AUTH',
      'SUPABASE_REST',
      'SUPABASE_STORAGE',
      'NETWORK',
      'WAVE',
      'CINETPAY',
      'FCM',
      'OPENAI',
      'EDGE_FUNCTIONS'
    )
    or v_item->>'status' not in (
      'UP',
      'DEGRADED',
      'DOWN',
      'NOT_CONFIGURED',
      'NOT_TESTED'
    ) then
      raise exception 'invalid_health_component';
    end if;

    insert into private.platform_health_checks(
      component,status,response_ms,details
    )
    values(
      v_item->>'component',
      v_item->>'status',
      case
        when (v_item->>'response_ms') ~ '^[0-9]+$'
          then (v_item->>'response_ms')::integer
        else null
      end,
      coalesce(v_item->'details','{}'::jsonb)
    );

    v_count := v_count + 1;
    v_has_down := v_has_down or v_item->>'status'='DOWN';
    v_has_degraded := v_has_degraded
      or v_item->>'status' in ('DEGRADED','NOT_CONFIGURED');
  end loop;

  insert into private.platform_agent_runs(
    agent_code,started_at,finished_at,status,findings_count,details
  )
  values(
    'PLATFORM_HEALTH_MONITOR',
    now(),
    now(),
    case
      when v_has_down then 'ERROR'
      when v_has_degraded then 'DEGRADED'
      else 'OK'
    end,
    (
      select count(*)
      from jsonb_array_elements(p_results) x
      where x->>'status' in ('DOWN','DEGRADED','NOT_CONFIGURED')
    ),
    jsonb_build_object('components_checked',v_count)
  );

  return v_count;
end;
$function$;
