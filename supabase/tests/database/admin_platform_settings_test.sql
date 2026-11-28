begin;
select plan(11);

select has_function(
  'public',
  'admin_upsert_marketplace_setting',
  array['text', 'jsonb']
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.admin_upsert_marketplace_setting(text,jsonb)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.admin_upsert_marketplace_setting(text,jsonb)',
    'EXECUTE'
  ),
  'only authenticated sessions can invoke the admin settings RPC'
);

select ok(
  position(
    'private.is_admin()'
    in pg_get_functiondef(
      'public.admin_upsert_marketplace_setting(text,jsonb)'::regprocedure
    )
  ) > 0,
  'the settings RPC enforces the active administrator check'
);

select ok(
  position(
    'setting_not_editable'
    in pg_get_functiondef(
      'public.admin_upsert_marketplace_setting(text,jsonb)'::regprocedure
    )
  ) > 0
  and position(
    'default_commission_rate'
    in pg_get_functiondef(
      'public.admin_upsert_marketplace_setting(text,jsonb)'::regprocedure
    )
  ) = 0,
  'the operational settings RPC does not expose payment or commission keys'
);

select ok(
  position(
    'is distinct from' 
    in pg_get_functiondef(
      'public.admin_upsert_marketplace_setting(text,jsonb)'::regprocedure
    )
  ) > 0,
  'an announcement cannot be saved without an explicit enabled flag'
);

select has_function(
  'public',
  'get_public_marketplace_settings',
  array[]::text[]
);

select ok(
  has_function_privilege(
    'anon',
    'public.get_public_marketplace_settings()',
    'EXECUTE'
  )
  and has_function_privilege(
    'authenticated',
    'public.get_public_marketplace_settings()',
    'EXECUTE'
  ),
  'the public settings accessor is readable by application clients'
);

select is(
  public.get_public_marketplace_settings() -> 'platform_profile' ->> 'country_code',
  'BF',
  'the seeded public platform profile is Burkina Faso'
);

select is(
  public.get_public_marketplace_settings() -> 'platform_profile' ->> 'currency',
  'XOF',
  'the seeded public platform profile uses XOF'
);

select is(
  public.get_public_marketplace_settings() -> 'public_announcement' ->> 'enabled',
  'false',
  'public announcements are disabled by default'
);

select ok(
  position(
    'public_announcement'
    in pg_get_functiondef(
      'public.get_public_marketplace_settings()'::regprocedure
    )
  ) > 0,
  'the public accessor is limited to the explicitly public settings'
);

select * from finish();
rollback;
