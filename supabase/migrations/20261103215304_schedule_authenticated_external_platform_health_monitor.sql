do $$
begin
  if not exists(select 1 from vault.secrets where name='platform_health_monitor_secret') then
    perform vault.create_secret(
      encode(gen_random_bytes(32),'hex'),
      'platform_health_monitor_secret',
      'Private bearer secret used only by pg_cron to call the platform health monitor',
      null::uuid
    );
  end if;
end $$;

create or replace function private.check_platform_monitor_secret(p_secret text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from vault.decrypted_secrets
    where name='platform_health_monitor_secret' and decrypted_secret=p_secret
  );
$$;
revoke all on function private.check_platform_monitor_secret(text) from public,anon,authenticated;
grant execute on function private.check_platform_monitor_secret(text) to service_role;
grant usage on schema private to service_role;

create or replace function public.check_platform_monitor_secret(p_secret text)
returns boolean language sql security invoker set search_path='' as $$
  select private.check_platform_monitor_secret(p_secret);
$$;
revoke all on function public.check_platform_monitor_secret(text) from public,anon,authenticated;
grant execute on function public.check_platform_monitor_secret(text) to service_role;

do $$
begin
  if not exists(select 1 from cron.job where jobname='platform-health-monitor-external') then
    perform cron.schedule(
      'platform-health-monitor-external',
      '*/5 * * * *',
      $job$
        select net.http_post(
          (select decrypted_secret from vault.decrypted_secrets where name='project_url')
            || '/functions/v1/platform-health-monitor',
          '{}'::jsonb,
          '{}'::jsonb,
          jsonb_build_object(
            'Content-Type','application/json',
            'x-platform-monitor-secret',
            (select decrypted_secret from vault.decrypted_secrets where name='platform_health_monitor_secret')
          ),
          15000
        );
      $job$
    );
  end if;
end $$;