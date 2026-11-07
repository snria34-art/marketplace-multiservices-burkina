BEGIN;
SELECT plan(13);
SELECT ok(to_regclass('public.real_estate_visit_requests') IS NOT NULL,'the real estate visit request table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid='public.real_estate_visit_requests'::regclass),'RLS is enabled on real estate visit requests');
SELECT ok(
 NOT has_table_privilege('anon','public.real_estate_visit_requests','SELECT')
 AND NOT has_table_privilege('anon','public.real_estate_visit_requests','INSERT')
 AND NOT has_table_privilege('authenticated','public.real_estate_visit_requests','SELECT')
 AND NOT has_table_privilege('authenticated','public.real_estate_visit_requests','INSERT')
 AND NOT has_table_privilege('authenticated','public.real_estate_visit_requests','UPDATE')
 AND NOT has_table_privilege('authenticated','public.real_estate_visit_requests','DELETE'),
 'API roles have no direct access to the private request table'
);
SELECT ok(
 EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='real_estate_visit_requests'
 AND policyname='real_estate_visit_requests_active_account_guard' AND permissive='RESTRICTIVE'
 AND cmd='ALL' AND roles @> ARRAY['authenticated']::name[]),
 'the authenticated active-account guard is restrictive'
);
SELECT ok(
 (SELECT count(*)=2 FROM pg_constraint WHERE conrelid='public.real_estate_visit_requests'::regclass AND contype='f')
 AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.real_estate_visit_requests'::regclass AND contype='f' AND confrelid='public.real_estate_listings'::regclass)
 AND EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid='public.real_estate_visit_requests'::regclass AND contype='f' AND confrelid='auth.users'::regclass),
 'requests reference a real estate listing and an auth user'
);
SELECT ok(
 EXISTS (SELECT 1 FROM pg_index i JOIN pg_class idx ON idx.oid=i.indexrelid
 WHERE i.indrelid='public.real_estate_visit_requests'::regclass
 AND idx.relname='real_estate_visit_requests_one_pending_per_user_listing'
 AND i.indisunique AND pg_get_expr(i.indpred,i.indrelid) ILIKE '%REQUESTED%'),
 'a partial unique index allows only one pending request per user and listing'
);
SELECT ok(
 to_regprocedure('public.request_real_estate_visit(uuid,timestamp with time zone,text)') IS NOT NULL
 AND to_regprocedure('public.cancel_real_estate_visit(uuid)') IS NOT NULL
 AND to_regprocedure('public.get_my_real_estate_visit_requests()') IS NOT NULL
 AND to_regprocedure('public.get_provider_real_estate_visit_requests()') IS NOT NULL
 AND to_regprocedure('public.respond_real_estate_visit(uuid,text)') IS NOT NULL,
 'all five real estate visit RPCs exist'
);
SELECT ok(
 (SELECT count(*)=5 AND bool_and(p.prosecdef AND pg_get_userbyid(p.proowner)='postgres'
 AND p.proconfig @> ARRAY['search_path=""']::text[])
 FROM pg_proc p WHERE p.oid IN (
 'public.request_real_estate_visit(uuid,timestamp with time zone,text)'::regprocedure,
 'public.cancel_real_estate_visit(uuid)'::regprocedure,
 'public.get_my_real_estate_visit_requests()'::regprocedure,
 'public.get_provider_real_estate_visit_requests()'::regprocedure,
 'public.respond_real_estate_visit(uuid,text)'::regprocedure)),
 'all RPCs are owned by postgres, SECURITY DEFINER, and use an empty search_path'
);
SELECT ok(
 has_function_privilege('authenticated','public.request_real_estate_visit(uuid,timestamp with time zone,text)','EXECUTE')
 AND has_function_privilege('authenticated','public.cancel_real_estate_visit(uuid)','EXECUTE')
 AND has_function_privilege('authenticated','public.get_my_real_estate_visit_requests()','EXECUTE')
 AND has_function_privilege('authenticated','public.get_provider_real_estate_visit_requests()','EXECUTE')
 AND has_function_privilege('authenticated','public.respond_real_estate_visit(uuid,text)','EXECUTE'),
 'authenticated users can call the guarded RPCs'
);
SELECT ok(
 NOT has_function_privilege('anon','public.request_real_estate_visit(uuid,timestamp with time zone,text)','EXECUTE')
 AND NOT has_function_privilege('anon','public.cancel_real_estate_visit(uuid)','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_my_real_estate_visit_requests()','EXECUTE')
 AND NOT has_function_privilege('anon','public.get_provider_real_estate_visit_requests()','EXECUTE')
 AND NOT has_function_privilege('anon','public.respond_real_estate_visit(uuid,text)','EXECUTE')
 AND NOT has_function_privilege('public','public.request_real_estate_visit(uuid,timestamp with time zone,text)','EXECUTE')
 AND NOT has_function_privilege('public','public.cancel_real_estate_visit(uuid)','EXECUTE')
 AND NOT has_function_privilege('public','public.get_my_real_estate_visit_requests()','EXECUTE')
 AND NOT has_function_privilege('public','public.get_provider_real_estate_visit_requests()','EXECUTE')
 AND NOT has_function_privilege('public','public.respond_real_estate_visit(uuid,text)','EXECUTE'),
 'anonymous and PUBLIC roles cannot execute the RPCs'
);
SELECT ok(
 pg_get_function_result('public.get_provider_real_estate_visit_requests()'::regprocedure) NOT ILIKE '%requester_id%',
 'the provider response does not expose the requester account UUID'
);
SELECT ok(
 (SELECT count(*)=3 FROM pg_constraint WHERE conrelid='public.real_estate_visit_requests'::regclass AND contype='c'),
 'status, message length, and preferred time constraints exist'
);
SELECT ok(
 pg_get_functiondef('public.request_real_estate_visit(uuid,timestamp with time zone,text)'::regprocedure) ILIKE '%FOR SHARE OF l, sp%'
 AND pg_get_functiondef('public.respond_real_estate_visit(uuid,text)'::regprocedure) ILIKE '%FOR UPDATE OF r, l, sp%',
 'creation and provider decisions lock listing and provider state against concurrent changes'
);

SELECT * FROM finish();
ROLLBACK;
