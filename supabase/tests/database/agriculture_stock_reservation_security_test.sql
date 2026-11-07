BEGIN;
SELECT plan(25);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='agriculture_listings'
      AND column_name='reserved_quantity'
      AND data_type='numeric'
      AND is_nullable='NO'
  ),
  'agriculture listings have a non-null reserved quantity'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_listings'::regclass
      AND conname='agriculture_listings_reserved_quantity_nonnegative'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_listings'::regclass
      AND conname='agriculture_listings_reserved_not_above_quantity'
  ),
  'reserved stock cannot be negative or exceed total stock'
);

SELECT ok(
  to_regclass('public.agriculture_order_requests') IS NOT NULL
  AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.agriculture_order_requests'::regclass),
  'agriculture order requests exist with RLS enabled'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='agriculture_order_requests'
      AND policyname='agriculture_order_requests_active_account_guard'
      AND cmd='ALL' AND permissive='RESTRICTIVE'
  ),
  'agriculture requests retain a restrictive active-account guard'
);

SELECT ok(
  NOT has_table_privilege('anon','public.agriculture_order_requests','SELECT')
  AND NOT has_table_privilege('anon','public.agriculture_order_requests','INSERT')
  AND NOT has_table_privilege('authenticated','public.agriculture_order_requests','SELECT')
  AND NOT has_table_privilege('authenticated','public.agriculture_order_requests','INSERT')
  AND NOT has_table_privilege('authenticated','public.agriculture_order_requests','UPDATE')
  AND NOT has_table_privilege('authenticated','public.agriculture_order_requests','DELETE'),
  'client roles have no direct access to agriculture order requests'
);

SELECT ok(
  (SELECT count(*)=3 FROM pg_constraint
   WHERE conrelid='public.agriculture_order_requests'::regclass
     AND contype='f')
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_order_requests'::regclass
      AND confrelid='public.agriculture_listings'::regclass
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_order_requests'::regclass
      AND confrelid='public.sellers'::regclass
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_order_requests'::regclass
      AND confrelid='auth.users'::regclass
  ),
  'orders reference their listing, seller and customer identity'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='agriculture_order_requests'
      AND indexname='agriculture_order_requests_customer_created_idx'
  )
  AND EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='agriculture_order_requests'
      AND indexname='agriculture_order_requests_seller_status_created_idx'
  )
  AND EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='agriculture_order_requests'
      AND indexname='agriculture_order_requests_listing_status_created_idx'
  ),
  'customer, seller and listing order lookups are indexed'
);

SELECT ok(
  to_regprocedure('private.is_verified_active_seller(uuid)') IS NOT NULL
  AND (
    SELECT prosecdef
      AND pg_get_userbyid(proowner)='postgres'
      AND proconfig @> ARRAY['search_path=""']::text[]
    FROM pg_proc
    WHERE oid='private.is_verified_active_seller(uuid)'::regprocedure
  ),
  'seller verification helper is postgres-owned, SECURITY DEFINER and uses empty search_path'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='sellers'
      AND policyname='sellers_public_verified'
      AND cmd='SELECT'
      AND roles @> ARRAY['anon']::name[]
      AND NOT roles @> ARRAY['authenticated']::name[]
  ),
  'anonymous public seller row access is limited to verified sellers'
);

SELECT ok(
  has_column_privilege('anon','public.sellers','id','SELECT')
  AND has_column_privilege('anon','public.sellers','business_name','SELECT')
  AND has_column_privilege('anon','public.sellers','verification_status','SELECT')
  AND NOT has_column_privilege('anon','public.sellers','user_id','SELECT')
  AND NOT has_column_privilege('anon','public.sellers','business_phone','SELECT'),
  'anonymous seller data access excludes user ids and phone numbers'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='agriculture_listings'
      AND policyname='agriculture_public_verified'
      AND cmd='SELECT'
      AND roles @> ARRAY['anon']::name[]
      AND qual ILIKE '%is_verified_active_seller%'
  ),
  'public agriculture listings require an active verified seller'
);

SELECT ok(
  NOT has_table_privilege('anon','public.agriculture_listings','INSERT')
  AND NOT has_table_privilege('authenticated','public.agriculture_listings','INSERT')
  AND NOT has_table_privilege('authenticated','public.agriculture_listings','UPDATE')
  AND NOT has_table_privilege('authenticated','public.agriculture_listings','DELETE'),
  'listing changes cannot bypass seller-ownership RPCs'
);

SELECT ok(
  to_regprocedure('public.create_agriculture_listing(text,text,text,numeric,text,numeric)') IS NOT NULL
  AND to_regprocedure('public.update_agriculture_listing(uuid,text,text,text,numeric,text,numeric,boolean)') IS NOT NULL
  AND to_regprocedure('public.get_my_agriculture_listings()') IS NOT NULL
  AND to_regprocedure('public.create_agriculture_order_request(uuid,numeric)') IS NOT NULL
  AND to_regprocedure('public.cancel_agriculture_order_request(uuid)') IS NOT NULL
  AND to_regprocedure('public.get_my_agriculture_order_requests()') IS NOT NULL
  AND to_regprocedure('public.get_seller_agriculture_order_requests()') IS NOT NULL
  AND to_regprocedure('public.respond_agriculture_order_request(uuid,text)') IS NOT NULL
  AND to_regprocedure('public.fulfill_agriculture_order_request(uuid)') IS NOT NULL,
  'all nine agriculture listing and order RPCs exist'
);

SELECT ok(
  (
    SELECT count(*)=9 AND bool_and(
      p.prosecdef
      AND pg_get_userbyid(p.proowner)='postgres'
      AND p.proconfig @> ARRAY['search_path=""']::text[]
    )
    FROM pg_proc p
    WHERE p.oid IN (
      'public.create_agriculture_listing(text,text,text,numeric,text,numeric)'::regprocedure,
      'public.update_agriculture_listing(uuid,text,text,text,numeric,text,numeric,boolean)'::regprocedure,
      'public.get_my_agriculture_listings()'::regprocedure,
      'public.create_agriculture_order_request(uuid,numeric)'::regprocedure,
      'public.cancel_agriculture_order_request(uuid)'::regprocedure,
      'public.get_my_agriculture_order_requests()'::regprocedure,
      'public.get_seller_agriculture_order_requests()'::regprocedure,
      'public.respond_agriculture_order_request(uuid,text)'::regprocedure,
      'public.fulfill_agriculture_order_request(uuid)'::regprocedure
    )
  ),
  'all nine agriculture RPCs are owner-controlled SECURITY DEFINER with empty search_path'
);

SELECT ok(
  has_function_privilege('authenticated','public.create_agriculture_listing(text,text,text,numeric,text,numeric)','EXECUTE')
  AND has_function_privilege('authenticated','public.update_agriculture_listing(uuid,text,text,text,numeric,text,numeric,boolean)','EXECUTE')
  AND has_function_privilege('authenticated','public.get_my_agriculture_listings()','EXECUTE')
  AND has_function_privilege('authenticated','public.create_agriculture_order_request(uuid,numeric)','EXECUTE')
  AND has_function_privilege('authenticated','public.cancel_agriculture_order_request(uuid)','EXECUTE')
  AND has_function_privilege('authenticated','public.get_my_agriculture_order_requests()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_seller_agriculture_order_requests()','EXECUTE')
  AND has_function_privilege('authenticated','public.respond_agriculture_order_request(uuid,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.fulfill_agriculture_order_request(uuid)','EXECUTE'),
  'authenticated users can call guarded agriculture RPCs'
);

SELECT ok(
  NOT has_function_privilege('anon','public.create_agriculture_listing(text,text,text,numeric,text,numeric)','EXECUTE')
  AND NOT has_function_privilege('anon','public.update_agriculture_listing(uuid,text,text,text,numeric,text,numeric,boolean)','EXECUTE')
  AND NOT has_function_privilege('anon','public.create_agriculture_order_request(uuid,numeric)','EXECUTE')
  AND NOT has_function_privilege('anon','public.cancel_agriculture_order_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('anon','public.respond_agriculture_order_request(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.fulfill_agriculture_order_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('public','public.create_agriculture_listing(text,text,text,numeric,text,numeric)','EXECUTE')
  AND NOT has_function_privilege('public','public.update_agriculture_listing(uuid,text,text,text,numeric,text,numeric,boolean)','EXECUTE')
  AND NOT has_function_privilege('public','public.create_agriculture_order_request(uuid,numeric)','EXECUTE')
  AND NOT has_function_privilege('public','public.cancel_agriculture_order_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('public','public.respond_agriculture_order_request(uuid,text)','EXECUTE')
  AND NOT has_function_privilege('public','public.fulfill_agriculture_order_request(uuid)','EXECUTE'),
  'anonymous and PUBLIC roles cannot execute agriculture mutation RPCs'
);

SELECT ok(
  has_function_privilege('anon','public.get_public_agriculture_listings()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_public_agriculture_listings()','EXECUTE')
  AND NOT (SELECT prosecdef FROM pg_proc WHERE oid='public.get_public_agriculture_listings()'::regprocedure)
  AND has_function_privilege('anon','private.get_public_agriculture_listings_internal()','EXECUTE')
  AND has_function_privilege('authenticated','private.get_public_agriculture_listings_internal()','EXECUTE')
  AND (
    SELECT prosecdef
      AND pg_get_userbyid(proowner)='postgres'
      AND proconfig @> ARRAY['search_path=""']::text[]
    FROM pg_proc
    WHERE oid='private.get_public_agriculture_listings_internal()'::regprocedure
  ),
  'public catalog is SECURITY INVOKER and delegates to a locked private read function'
);

SELECT ok(
  pg_get_function_result('public.get_public_agriculture_listings()'::regprocedure) NOT ILIKE '%seller_id%'
  AND pg_get_function_result('public.get_public_agriculture_listings()'::regprocedure) NOT ILIKE '%reserved_quantity%'
  AND pg_get_function_result('public.get_public_agriculture_listings()'::regprocedure) NOT ILIKE '%user_id%'
  AND pg_get_function_result('public.get_public_agriculture_listings()'::regprocedure) NOT ILIKE '%business_phone%',
  'public catalog response excludes seller identifiers, reserved stock and private contact fields'
);

SELECT ok(
  pg_get_function_result('public.get_seller_agriculture_order_requests()'::regprocedure) NOT ILIKE '%customer_id%',
  'seller order inbox never returns customer account identifiers'
);

SELECT ok(
  pg_get_functiondef('public.create_agriculture_order_request(uuid,numeric)'::regprocedure)
    ILIKE '%FOR UPDATE OF l, s, p%'
  AND pg_get_functiondef('public.create_agriculture_order_request(uuid,numeric)'::regprocedure)
    ILIKE '%v_stock - v_reserved < p_quantity%',
  'order creation locks stock rows and checks available quantity before reservation'
);

SELECT ok(
  pg_get_functiondef('public.respond_agriculture_order_request(uuid,text)'::regprocedure)
    ILIKE '%FOR UPDATE OF r, l, s, p%'
  AND pg_get_functiondef('public.respond_agriculture_order_request(uuid,text)'::regprocedure)
    ILIKE '%v_reserved < v_quantity%',
  'seller acceptance locks the request and listing and verifies the held reservation'
);

SELECT ok(
  pg_get_functiondef('public.fulfill_agriculture_order_request(uuid)'::regprocedure)
    ILIKE '%FOR UPDATE OF r, l, s, p%'
  AND pg_get_functiondef('public.fulfill_agriculture_order_request(uuid)'::regprocedure)
    ILIKE '%reserved_quantity = reserved_quantity - v_quantity%'
  AND pg_get_functiondef('public.fulfill_agriculture_order_request(uuid)'::regprocedure)
    ILIKE '%quantity = quantity - v_quantity%',
  'fulfillment atomically converts reserved stock into consumed stock'
);

SELECT ok(
  pg_get_functiondef('public.cancel_agriculture_order_request(uuid)'::regprocedure)
    ILIKE '%reserved_quantity = reserved_quantity - v_quantity%'
  AND pg_get_functiondef('public.respond_agriculture_order_request(uuid,text)'::regprocedure)
    ILIKE '%status = ''REJECTED''%',
  'customer cancellation and seller rejection both release reserved stock'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_order_requests'::regclass
      AND conname='agriculture_order_requests_quantity_check'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.agriculture_order_requests'::regclass
      AND conname='agriculture_order_requests_listing_type_check'
  ),
  'order quantity and listing type are constrained by the database'
);

SELECT ok(
  pg_get_function_result('public.get_my_agriculture_listings()'::regprocedure)
    ILIKE '%reserved_quantity%'
  AND pg_get_function_result('public.get_my_agriculture_listings()'::regprocedure)
    ILIKE '%available_quantity%',
  'seller inventory view returns both reserved and available stock'
);

SELECT * FROM finish();
ROLLBACK;
