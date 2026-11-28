begin;
select plan(9);

select has_function('public','admin_list_pending_provider_applications',array[]::text[]);
select has_function('public','admin_review_provider_application',array['uuid','text','text']);

select ok(
  has_function_privilege('authenticated','public.admin_list_pending_provider_applications()','EXECUTE')
  and not has_function_privilege('anon','public.admin_list_pending_provider_applications()','EXECUTE'),
  'pending provider applications are exposed only to authenticated callers'
);

select ok(
  position('private.is_admin()' in pg_get_functiondef('public.admin_list_pending_provider_applications()'::regprocedure)) > 0,
  'the pending queue requires an administrator'
);

select ok(
  position('private.is_admin()' in pg_get_functiondef('public.admin_review_provider_application(uuid,text,text)'::regprocedure)) > 0,
  'provider decisions require an administrator'
);

select ok(
  position('for update' in lower(pg_get_functiondef('public.admin_review_provider_application(uuid,text,text)'::regprocedure))) > 0,
  'provider review locks the pending application row'
);

select ok(
  position('verification_status' in pg_get_functiondef('public.admin_review_provider_application(uuid,text,text)'::regprocedure)) > 0
  and position('active = (v_decision = ''APPROVE'')' in pg_get_functiondef('public.admin_review_provider_application(uuid,text,text)'::regprocedure)) > 0,
  'approval verifies and activates while rejection deactivates'
);

select ok(
  position('provider_kyc_documents_required' in pg_get_functiondef('public.admin_review_provider_application(uuid,text,text)'::regprocedure)) > 0,
  'approval is fail-closed until private KYC documents are verified'
);

select ok(
  position('ADMIN_PROVIDER_APPLICATION_' in pg_get_functiondef('public.admin_review_provider_application(uuid,text,text)'::regprocedure)) > 0,
  'every provider decision is audited'
);

select * from finish();
rollback;
