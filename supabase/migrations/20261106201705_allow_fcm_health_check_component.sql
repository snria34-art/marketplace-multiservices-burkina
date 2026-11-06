alter table private.platform_health_checks
  drop constraint platform_health_checks_component_check;

alter table private.platform_health_checks
  add constraint platform_health_checks_component_check
  check (
    component = any (
      array[
        'SUPABASE_AUTH',
        'SUPABASE_REST',
        'SUPABASE_STORAGE',
        'NETWORK',
        'WAVE',
        'CINETPAY',
        'FCM',
        'OPENAI',
        'EDGE_FUNCTIONS'
      ]::text[]
    )
  );
