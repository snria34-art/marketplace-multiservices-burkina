BEGIN;
SELECT plan(29);

SELECT ok(
  EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='health_products'
      AND column_name='reserved_quantity'
      AND data_type='integer' AND is_nullable='NO'
  ),
  'health products have a non-null reserved quantity'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.health_products'::regclass
      AND conname='health_products_reserved_quantity_nonnegative'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.health_products'::regclass
      AND conname='health_products_reserved_not_above_stock'
  ),
  'reserved health stock cannot be negative or exceed physical stock'
);

SELECT ok(
  to_regclass('public.health_order_requests') IS NOT NULL
  AND (SELECT relrowsecurity FROM pg_class WHERE oid='public.health_order_requests'::regclass),
  'health order requests exist with RLS enabled'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='health_order_requests'
      AND policyname='health_order_requests_active_account_guard'
      AND cmd='ALL' AND permissive='RESTRICTIVE'
  ),
  'health orders use a restrictive active-account guard'
);

SELECT ok(
  NOT has_table_privilege('anon','public.health_order_requests','SELECT')
  AND NOT has_table_privilege('anon','public.health_order_requests','INSERT')
  AND NOT has_table_privilege('authenticated','public.health_order_requests','SELECT')
  AND NOT has_table_privilege('authenticated','public.health_order_requests','INSERT')
  AND NOT has_table_privilege('authenticated','public.health_order_requests','UPDATE')
  AND NOT has_table_privilege('authenticated','public.health_order_requests','DELETE'),
  'clients cannot directly read or write health order records'
);

SELECT ok(
  (SELECT count(*)=4
   FROM pg_constraint
   WHERE conrelid='public.health_order_requests'::regclass
     AND contype='f'),
  'health orders reference product, health provider, customer and reviewer'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='health_order_requests'
      AND indexname='health_order_requests_customer_created_idx'
  )
  AND EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='health_order_requests'
      AND indexname='health_order_requests_provider_status_created_idx'
  )
  AND EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND tablename='health_order_requests'
      AND indexname='health_order_requests_expiry_idx'
  ),
  'customer, pharmacy and expiry queries are indexed'
);

SELECT ok(
  to_regprocedure('private.is_verified_active_health_provider(uuid,text)') IS NOT NULL
  AND (
    SELECT prosecdef AND pg_get_userbyid(proowner)='postgres'
      AND proconfig @> ARRAY['search_path=""']::text[]
    FROM pg_proc
    WHERE oid='private.is_verified_active_health_provider(uuid,text)'::regprocedure
  ),
  'health provider verification helper is owner-controlled and uses an empty search_path'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
      AND policyname='health_prescriptions_upload_own' AND cmd='INSERT'
      AND qual IS NULL
      AND with_check ILIKE '%health-prescriptions%'
      AND with_check ILIKE '%auth.uid%'
  )
  AND EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
      AND policyname='health_prescriptions_read_authorized' AND cmd='SELECT'
      AND qual ILIKE '%can_read_health_prescription%'
  )
  AND EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects'
      AND policyname='health_prescriptions_delete_owner' AND cmd='DELETE'
      AND qual ILIKE '%can_delete_health_prescription%'
  ),
  'prescription storage access is scoped to upload owner, order customer and assigned pharmacy'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM storage.buckets
    WHERE id='health-prescriptions'
      AND public IS FALSE
      AND file_size_limit=10485760
      AND allowed_mime_types @> ARRAY['image/jpeg','image/png']
      AND cardinality(allowed_mime_types)=2
  ),
  'prescriptions use a private 10 MB JPEG/PNG bucket'
);

SELECT ok(
  NOT has_table_privilege('anon','public.health_products','SELECT')
  AND NOT has_table_privilege('authenticated','public.health_products','SELECT'),
  'health product rows are not directly selectable through the Data API'
);

SELECT ok(
  NOT has_table_privilege('anon','public.health_providers','SELECT')
  AND NOT has_table_privilege('authenticated','public.health_providers','SELECT'),
  'health provider records and license references are not directly selectable'
);

SELECT ok(
  (
    SELECT prosecdef AND pg_get_userbyid(proowner)='postgres'
      AND proconfig @> ARRAY['search_path=""']::text[]
    FROM pg_proc
    WHERE oid='private.get_public_health_products_internal()'::regprocedure
  ),
  'public health catalog uses a restricted private reader'
);

SELECT ok(
  NOT (SELECT prosecdef FROM pg_proc WHERE oid='public.get_public_health_products()'::regprocedure)
  AND has_function_privilege('anon','public.get_public_health_products()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_public_health_products()','EXECUTE'),
  'public health catalog wrapper is SECURITY INVOKER and read-only'
);

SELECT ok(
  (
    SELECT count(*)=10 AND bool_and(NOT prosecdef)
    FROM pg_proc
    WHERE oid IN (
      'public.get_public_health_products()'::regprocedure,
      'public.create_health_product(text,text,numeric,boolean,integer)'::regprocedure,
      'public.update_health_product(uuid,text,text,numeric,boolean,integer,boolean)'::regprocedure,
      'public.get_my_health_products()'::regprocedure,
      'public.create_health_order_request(uuid,integer,text)'::regprocedure,
      'public.cancel_health_order_request(uuid)'::regprocedure,
      'public.get_my_health_order_requests()'::regprocedure,
      'public.get_pharmacy_health_order_requests()'::regprocedure,
      'public.respond_health_order_request(uuid,text,text)'::regprocedure,
      'public.fulfill_health_order_request(uuid)'::regprocedure
    )
  ),
  'all ten public health API wrappers are SECURITY INVOKER'
);

SELECT ok(
  (
    SELECT count(*)=11 AND bool_and(
      prosecdef AND pg_get_userbyid(proowner)='postgres'
      AND proconfig @> ARRAY['search_path=""']::text[]
    )
    FROM pg_proc
    WHERE oid IN (
      'private.get_public_health_products_internal()'::regprocedure,
      'private.create_health_product_internal(text,text,numeric,boolean,integer)'::regprocedure,
      'private.update_health_product_internal(uuid,text,text,numeric,boolean,integer,boolean)'::regprocedure,
      'private.get_my_health_products_internal()'::regprocedure,
      'private.expire_health_order_requests_internal()'::regprocedure,
      'private.create_health_order_request_internal(uuid,integer,text)'::regprocedure,
      'private.cancel_health_order_request_internal(uuid)'::regprocedure,
      'private.get_my_health_order_requests_internal()'::regprocedure,
      'private.get_pharmacy_health_order_requests_internal()'::regprocedure,
      'private.respond_health_order_request_internal(uuid,text,text)'::regprocedure,
      'private.fulfill_health_order_request_internal(uuid)'::regprocedure
    )
  ),
  'all eleven internal health functions are postgres-owned SECURITY DEFINER with empty search_path'
);

SELECT ok(
  has_function_privilege('authenticated','public.create_health_product(text,text,numeric,boolean,integer)','EXECUTE')
  AND has_function_privilege('authenticated','public.update_health_product(uuid,text,text,numeric,boolean,integer,boolean)','EXECUTE')
  AND has_function_privilege('authenticated','public.get_my_health_products()','EXECUTE')
  AND has_function_privilege('authenticated','public.create_health_order_request(uuid,integer,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.cancel_health_order_request(uuid)','EXECUTE')
  AND has_function_privilege('authenticated','public.get_my_health_order_requests()','EXECUTE')
  AND has_function_privilege('authenticated','public.get_pharmacy_health_order_requests()','EXECUTE')
  AND has_function_privilege('authenticated','public.respond_health_order_request(uuid,text,text)','EXECUTE')
  AND has_function_privilege('authenticated','public.fulfill_health_order_request(uuid)','EXECUTE'),
  'authenticated users can call health workflow endpoints'
);

SELECT ok(
  NOT has_function_privilege('anon','public.create_health_product(text,text,numeric,boolean,integer)','EXECUTE')
  AND NOT has_function_privilege('anon','public.update_health_product(uuid,text,text,numeric,boolean,integer,boolean)','EXECUTE')
  AND NOT has_function_privilege('anon','public.create_health_order_request(uuid,integer,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.cancel_health_order_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('anon','public.respond_health_order_request(uuid,text,text)','EXECUTE')
  AND NOT has_function_privilege('anon','public.fulfill_health_order_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('public','public.create_health_product(text,text,numeric,boolean,integer)','EXECUTE')
  AND NOT has_function_privilege('public','public.update_health_product(uuid,text,text,numeric,boolean,integer,boolean)','EXECUTE')
  AND NOT has_function_privilege('public','public.create_health_order_request(uuid,integer,text)','EXECUTE')
  AND NOT has_function_privilege('public','public.cancel_health_order_request(uuid)','EXECUTE')
  AND NOT has_function_privilege('public','public.respond_health_order_request(uuid,text,text)','EXECUTE')
  AND NOT has_function_privilege('public','public.fulfill_health_order_request(uuid)','EXECUTE'),
  'anon and PUBLIC cannot mutate the health workflow'
);

SELECT ok(
  pg_get_function_result('public.get_public_health_products()'::regprocedure)
    NOT ILIKE '%health_provider_id%'
  AND pg_get_function_result('public.get_public_health_products()'::regprocedure)
    NOT ILIKE '%license_reference%'
  AND pg_get_function_result('public.get_public_health_products()'::regprocedure)
    NOT ILIKE '%provider_id%',
  'public health catalog omits internal provider and license identifiers'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.health_order_requests'::regclass
      AND conname='health_order_requests_prescription_required_check'
  ),
  'prescription-required orders cannot be created without a prescription path'
);

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.health_order_requests'::regclass
      AND conname='health_order_requests_status_check'
  )
  AND EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.health_order_requests'::regclass
      AND conname='health_order_requests_quantity_check'
  ),
  'health order status and quantity are constrained'
);

SELECT ok(
  pg_get_functiondef('private.create_health_order_request_internal(uuid,integer,text)'::regprocedure)
    ILIKE '%FOR UPDATE OF p, hp, sp, pr%'
  AND pg_get_functiondef('private.create_health_order_request_internal(uuid,integer,text)'::regprocedure)
    ILIKE '%reserved_quantity = reserved_quantity + p_quantity%',
  'health order creation locks the product and reserves available stock atomically'
);

SELECT ok(
  pg_get_functiondef('private.create_health_order_request_internal(uuid,integer,text)'::regprocedure)
    ILIKE '%PENDING_REVIEW%'
  AND pg_get_functiondef('private.respond_health_order_request_internal(uuid,text,text)'::regprocedure)
    ILIKE '%APPROVED_FOR_DISPENSING%',
  'prescription orders require pharmacy review before they can be dispensed'
);

SELECT ok(
  pg_get_functiondef('private.respond_health_order_request_internal(uuid,text,text)'::regprocedure)
    ILIKE '%reserved_quantity = reserved_quantity - v_quantity%'
  AND pg_get_functiondef('private.cancel_health_order_request_internal(uuid)'::regprocedure)
    ILIKE '%reserved_quantity = p.reserved_quantity - v_quantity%',
  'rejection and customer cancellation release reserved health stock'
);

SELECT ok(
  pg_get_functiondef('private.fulfill_health_order_request_internal(uuid)'::regprocedure)
    ILIKE '%stock_quantity = stock_quantity - v_quantity%'
  AND pg_get_functiondef('private.fulfill_health_order_request_internal(uuid)'::regprocedure)
    ILIKE '%reserved_quantity = reserved_quantity - v_quantity%'
  AND pg_get_functiondef('private.fulfill_health_order_request_internal(uuid)'::regprocedure)
    ILIKE '%status = ''DISPENSED''%',
  'dispensing converts reserved stock into consumed stock and closes the order'
);

SELECT ok(
  pg_get_functiondef('private.expire_health_order_requests_internal()'::regprocedure)
    ILIKE '%FOR UPDATE SKIP LOCKED%'
  AND pg_get_functiondef('private.expire_health_order_requests_internal()'::regprocedure)
    ILIKE '%status = ''EXPIRED''%'
  AND pg_get_functiondef('private.expire_health_order_requests_internal()'::regprocedure)
    ILIKE '%reserved_quantity = p.reserved_quantity - v_row.quantity%',
  'expired health requests release reserved stock without double processing'
);

SELECT ok(
  pg_get_functiondef('private.is_verified_active_health_provider(uuid,text)'::regprocedure)
    ILIKE '%license_reference%'
  AND pg_get_functiondef('private.is_verified_active_health_provider(uuid,text)'::regprocedure)
    ILIKE '%verification_status%'
  AND pg_get_functiondef('private.is_verified_active_health_provider(uuid,text)'::regprocedure)
    ILIKE '%account_status%',
  'a health provider must have a license reference, verified provider and active account'
);

SELECT ok(
  pg_get_functiondef('private.get_pharmacy_health_order_requests_internal()'::regprocedure)
    NOT ILIKE '%customer_id%'
  AND pg_get_function_result('public.get_my_health_order_requests()'::regprocedure)
    NOT ILIKE '%prescription_path%',
  'pharmacy inbox omits customer identifiers and customer history omits raw document paths'
);

SELECT ok(
  pg_get_functiondef('private.get_public_health_products_internal()'::regprocedure)
    ILIKE '%provider_type = ''PHARMACY''%'
  AND pg_get_functiondef('private.get_public_health_products_internal()'::regprocedure)
    ILIKE '%is_verified_active_health_provider%',
  'public health product catalog contains only products from verified active pharmacies'
);

SELECT * FROM finish();
ROLLBACK;
