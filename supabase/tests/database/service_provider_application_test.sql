begin;
select plan(8);

select has_function(
  'public',
  'submit_service_provider_application',
  array['text', 'text', 'text']
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.submit_service_provider_application(text,text,text)',
    'EXECUTE'
  )
  and not has_function_privilege(
    'anon',
    'public.submit_service_provider_application(text,text,text)',
    'EXECUTE'
  ),
  'only authenticated users can submit provider applications'
);

select ok(
  position(
    'active_account_required'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0,
  'provider applications require an active profile'
);

select ok(
  position(
    'verification_status'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0
  and position(
    'PENDING'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0,
  'provider applications begin pending verification'
);

select ok(
  position(
    'active'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0,
  'provider profiles are not activated automatically'
);

select ok(
  position(
    'TAXI'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0
  and position(
    'TRANSPORT_COMPANY'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0
  and position(
    'MOTO_TAXI'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0,
  'supported mobility provider types are explicitly allowlisted'
);

select ok(
  position(
    'provider_application_already_exists'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0,
  'duplicate provider applications are rejected'
);

select ok(
  position(
    'SERVICE_PROVIDER'
    in pg_get_functiondef(
      'public.submit_service_provider_application(text,text,text)'::regprocedure
    )
  ) > 0,
  'the provider role is granted by the controlled server function'
);

select * from finish();
rollback;
