BEGIN;
SELECT plan(17);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='service_requests'
      AND column_name='professional_profile_id' AND data_type='uuid'
  )
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='service_requests'
      AND column_name='service_id' AND is_nullable='YES'
  ),
  'service requests can target either a generic service or a professional profile'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.service_requests'::regclass
      AND conname='service_requests_professional_profile_id_fkey'
      AND confrelid='public.professional_profiles'::regclass
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.service_requests'::regclass
      AND conname='service_requests_exactly_one_target_check'
      AND contype='c'
  ),
  'professional requests have a profile FK and exactly-one-target constraint'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='professional_profiles'
      AND policyname='professional_public_verified'
      AND cmd='SELECT'
      AND roles @> ARRAY['anon']::name[]
      AND qual ILIKE '%verification_status%'
  ),
  'public professional profiles require an active verified provider'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='service_providers'
      AND policyname='service_providers_anon_verified_read'
      AND cmd='SELECT'
      AND roles @> ARRAY['anon']::name[]
      AND qual ILIKE '%VERIFIED%'
  ),
  'anonymous provider read policy is restricted to verified active providers'
);

SELECT ok(
  has_column_privilege('anon','public.service_providers','id','SELECT')
  AND has_column_privilege('anon','public.service_providers','display_name','SELECT')
  AND has_column_privilege('anon','public.service_providers','active','SELECT')
  AND has_column_privilege('anon','public.service_providers','verification_status','SELECT')
  AND NOT has_column_privilege('anon','public.service_providers','user_id','SELECT')
  AND NOT has_column_privilege('anon','public.service_providers','provider_type','SELECT')
  AND NOT has_column_privilege('anon','public.service_providers','description','SELECT'),
  'anonymous catalog access exposes only provider id, display name, active and verification fields'
);

SELECT ok(
  NOT has_table_privilege('anon','public.service_requests','INSERT')
  AND NOT has_table_privilege('anon','public.service_requests','UPDATE')
  AND NOT has_table_privilege('anon','public.service_requests','DELETE')
  AND NOT has_table_privilege('authenticated','public.service_requests','INSERT')
  AND NOT has_table_privilege('authenticated','public.service_requests','UPDATE')
  AND NOT has_table_privilege('authenticated','public.service_requests','DELETE'),
  'clients cannot directly write service requests'
);

SELECT ok(
  NOT has_table_privilege('anon','public.service_quotes','INSERT')
  AND NOT has_table_privilege('anon','public.service_quotes','UPDATE')
  AND NOT has_table_privilege('anon','public.service_quotes','DELETE')
  AND NOT has_table_privilege('authenticated','public.service_quotes','INSERT')
  AND NOT has_table_privilege('authenticated','public.service_quotes','UPDATE')
  AND NOT has_table_privilege('authenticated','public.service_quotes','DELETE'),
  'clients and providers cannot directly write service quotes'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='service_quotes'
      AND column_name='message' AND data_type='text'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.service_quotes'::regclass
      AND conname='service_quotes_message_length_check'
  ),
  'service quotes support a length-limited explanatory message'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_index i
    JOIN pg_class idx ON idx.oid=i.indexrelid
    WHERE i.indrelid='public.service_quotes'::regclass
      AND idx.relname='service_quotes_one_proposed_per_request_provider'
      AND i.indisunique
      AND pg_get_expr(i.indpred,i.indrelid) ILIKE '%PROPOSED%'
  ),
  'only one proposed quote can exist for a request and provider'
);

SELECT ok(
  to_regprocedure('public.create_professional_service_request(uuid,text,timestamp with time zone)') IS NOT NULL
  AND to_regprocedure('public.cancel_professional_service_request(uuid)') IS NOT NULL
  AND to_regprocedure('public.get_my_professional_service_requests()') IS NOT NULL
  AND to_regprocedure('public.get_provider_professional_service_requests()') IS NOT NULL
  AND to_regprocedure('public.create_professional_service_quote(uuid,numeric,text)') IS NOT NULL
  AND to_regprocedure('public.respond_professional_service_quote(uuid,text)') IS NOT NULL,
  'all six professional request and quote RPCs exist'
);

SELECT ok(
  (
    SELECT count(*)=6 AND bool_and(
      p.prosecdef
      AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
    )
    FROM pg_proc p
    WHERE p.oid IN (
      'public.create_professional_service_request(uuid,text,timestamp with time zone)'::regprocedure,
      'public.cancel_professional_service_request(uuid)'::regprocedure,
      'public.get_my_professional_service_requests()'::regprocedure,
      'public.get_provider_professional_service_requests()'::regprocedure,
      'public.create_professional_service_quote(uuid,numeric,text)'::regprocedure,
      'public.respond_professional_service_quote(uuid,text)'::regprocedure
    )
  ),
  'all professional RPCs are SECURITY DEFINER, postgres-owned and use an empty search_path'
);

SELECT ok(
  has_function_privilege('authenticated','public.create_professional_service_request(uuid,text,timestamp with time zone)','EXECUTE')
  AND has_function_privilege('authenticated','public.cancel_professional_service_request(uuid)','EXECUTE')
  AND has_function_privilege('authenticated','public.get_my_professional_service_requests()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_provider_professional_service_requests()','EXECUTE')
  AND has_function_privilege('authenticated','public.create_professional_service_quote(uuid,numeric,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.respond_professional_service_quote(uuid,text)','EXECUTE'),
  'authenticated users can call the ownership-checked professional RPCs'
);

SELECT ok(
  NOT has_function_privilege('anon','public.create_professional_service_request(uuid,text,timestamp with time zone)','EXECUTE')
  AND NOT has_function_privilege('anon','public.cancel_professional_service_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('anon','public.get_my_professional_service_requests()','EXECUTE')
  AND NOT has_function_privilege('anon','public.get_provider_professional_service_requests()','EXECUTE')
  AND NOT has_function_privilege('anon','public.create_professional_service_quote(uuid,numeric,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.respond_professional_service_quote(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('public','public.create_professional_service_request(uuid,text,timestamp with time zone)','EXECUTE')
  AND NOT has_function_privilege('public','public.cancel_professional_service_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('public','public.get_my_professional_service_requests()','EXECUTE')
  AND NOT has_function_privilege('public','public.get_provider_professional_service_requests()','EXECUTE')
  AND NOT has_function_privilege('public','public.create_professional_service_quote(uuid,numeric,text)','EXECUTE')
  AND NOT has_function_privilege('public','public.respond_professional_service_quote(uuid,text)','EXECUTE'),
  'anon and PUBLIC cannot execute professional RPCs'
);

SELECT ok(
  pg_get_function_result('public.get_provider_professional_service_requests()'::regprocedure)
    NOT ILIKE '%customer_id%',
  'the provider inbox does not expose customer account identifiers'
);

SELECT ok(
  pg_get_function_result('public.get_my_professional_service_requests()'::regprocedure)
    ILIKE '%quotes jsonb%',
  'the customer request reader returns the quote history as JSON'
);

SELECT ok(
  pg_get_functiondef('public.create_professional_service_request(uuid,text,timestamp with time zone)'::regprocedure)
    ILIKE '%FOR SHARE OF pp, sp%'
  AND pg_get_functiondef('public.create_professional_service_quote(uuid,numeric,text)'::regprocedure)
    ILIKE '%FOR UPDATE OF r, pp, sp%'
  AND pg_get_functiondef('public.respond_professional_service_quote(uuid,text)'::regprocedure)
    ILIKE '%FOR UPDATE OF q, r, pp, sp%',
  'request and quote transitions lock profile, provider and request rows against concurrent changes'
);

SELECT ok(
  (SELECT count(*)=2
   FROM pg_constraint
   WHERE conrelid='public.service_requests'::regclass
     AND conname IN (
       'service_requests_professional_profile_id_fkey',
       'service_requests_exactly_one_target_check'
     ))
  AND EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='service_requests'
      AND indexname='idx_service_requests_professional_profile_status_created'
  ),
  'professional request FK, target constraint and index are present'
);

SELECT ok(
  (SELECT count(*)=2
   FROM pg_constraint
   WHERE conrelid='public.service_quotes'::regclass
     AND conname IN (
       'service_quotes_message_length_check',
       'service_quote_amount_nonnegative'
     )),
  'quote message and nonnegative amount constraints are present'
);

SELECT * FROM finish();
ROLLBACK;
