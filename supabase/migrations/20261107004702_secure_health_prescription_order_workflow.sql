-- AUD-10.5: private prescription documents, pharmacy-owned catalog and order workflow.

CREATE OR REPLACE FUNCTION private.is_verified_active_health_provider(
  p_health_provider_id uuid,
  p_required_type text DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.health_providers AS hp
    JOIN public.service_providers AS sp ON sp.id = hp.provider_id
    JOIN public.profiles AS pr ON pr.id = sp.user_id
    WHERE hp.id = p_health_provider_id
      AND hp.active IS TRUE
      AND hp.verified IS TRUE
      AND NULLIF(pg_catalog.btrim(hp.license_reference), '') IS NOT NULL
      AND (p_required_type IS NULL OR hp.provider_type = p_required_type)
      AND sp.active IS TRUE
      AND sp.verification_status = 'VERIFIED'::public.verification_status
      AND pr.status = 'ACTIVE'::public.account_status
  );
$function$;
ALTER FUNCTION private.is_verified_active_health_provider(uuid, text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_verified_active_health_provider(uuid, text) FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.is_verified_active_health_provider(uuid, text) TO anon, authenticated;

ALTER TABLE public.health_products
  ADD COLUMN IF NOT EXISTS reserved_quantity integer NOT NULL DEFAULT 0;

ALTER TABLE public.health_products
  DROP CONSTRAINT IF EXISTS health_products_reserved_quantity_nonnegative;
ALTER TABLE public.health_products
  ADD CONSTRAINT health_products_reserved_quantity_nonnegative
  CHECK (reserved_quantity >= 0);

ALTER TABLE public.health_products
  DROP CONSTRAINT IF EXISTS health_products_reserved_not_above_stock;
ALTER TABLE public.health_products
  ADD CONSTRAINT health_products_reserved_not_above_stock
  CHECK (reserved_quantity <= stock_quantity);

CREATE INDEX IF NOT EXISTS health_products_active_provider_idx
  ON public.health_products (health_provider_id, name)
  WHERE active IS TRUE;

CREATE TABLE public.health_order_requests (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  product_id uuid NOT NULL REFERENCES public.health_products(id) ON DELETE RESTRICT,
  health_provider_id uuid NOT NULL REFERENCES public.health_providers(id) ON DELETE RESTRICT,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  product_name text NOT NULL,
  provider_name text NOT NULL,
  provider_type text NOT NULL CHECK (provider_type IN ('PHARMACY', 'CLINIC', 'LAB', 'OTHER')),
  requires_prescription boolean NOT NULL,
  prescription_path text,
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 50),
  unit_price numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  total_amount numeric(16,2) NOT NULL CHECK (total_amount >= 0),
  status text NOT NULL CHECK (status IN (
    'PENDING_REVIEW', 'REQUESTED', 'APPROVED_FOR_DISPENSING',
    'ACCEPTED', 'REJECTED', 'CANCELLED', 'EXPIRED', 'DISPENSED'
  )),
  review_note text CHECK (review_note IS NULL OR pg_catalog.char_length(review_note) <= 1000),
  reviewed_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  expires_at timestamptz NOT NULL DEFAULT (pg_catalog.now() + interval '48 hours'),
  dispensed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT health_order_requests_prescription_required_check
    CHECK (
      (requires_prescription IS TRUE AND prescription_path IS NOT NULL)
      OR (requires_prescription IS FALSE AND prescription_path IS NULL)
    )
);

CREATE INDEX health_order_requests_customer_created_idx
  ON public.health_order_requests (customer_id, created_at DESC);
CREATE INDEX health_order_requests_provider_status_created_idx
  ON public.health_order_requests (health_provider_id, status, created_at DESC);
CREATE INDEX health_order_requests_expiry_idx
  ON public.health_order_requests (expires_at)
  WHERE status IN ('PENDING_REVIEW', 'REQUESTED', 'APPROVED_FOR_DISPENSING', 'ACCEPTED');

ALTER TABLE public.health_order_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.health_order_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.health_order_requests TO service_role;

CREATE POLICY health_order_requests_active_account_guard
  ON public.health_order_requests
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (private.is_active_account())
  WITH CHECK (private.is_active_account());

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('health-prescriptions', 'health-prescriptions', false, 10485760, ARRAY['image/jpeg', 'image/png'])
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = false,
    file_size_limit = EXCLUDED.file_size_limit,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE OR REPLACE FUNCTION private.can_read_health_prescription(p_object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM public.health_order_requests AS r
      JOIN public.health_providers AS hp ON hp.id = r.health_provider_id
      JOIN public.service_providers AS sp ON sp.id = hp.provider_id
      WHERE r.prescription_path = p_object_name
        AND (
          r.customer_id = auth.uid()
          OR (
            sp.user_id = auth.uid()
            AND hp.provider_type = 'PHARMACY'
            AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
          )
        )
    );
$function$;

CREATE OR REPLACE FUNCTION private.can_delete_health_prescription(p_object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT auth.uid() IS NOT NULL
    AND (storage.foldername(p_object_name))[1] = auth.uid()::text
    AND NOT EXISTS (
      SELECT 1
      FROM public.health_order_requests AS r
      WHERE r.prescription_path = p_object_name
        AND r.status NOT IN ('REJECTED', 'CANCELLED', 'EXPIRED')
    );
$function$;

ALTER FUNCTION private.can_read_health_prescription(text) OWNER TO postgres;
ALTER FUNCTION private.can_delete_health_prescription(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.can_read_health_prescription(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.can_delete_health_prescription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.can_read_health_prescription(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_delete_health_prescription(text) TO authenticated;

DROP POLICY IF EXISTS health_prescriptions_upload_own ON storage.objects;
CREATE POLICY health_prescriptions_upload_own
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'health-prescriptions'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND private.is_active_account()
  );

DROP POLICY IF EXISTS health_prescriptions_read_authorized ON storage.objects;
CREATE POLICY health_prescriptions_read_authorized
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'health-prescriptions'
    AND private.can_read_health_prescription(name)
  );

DROP POLICY IF EXISTS health_prescriptions_delete_owner ON storage.objects;
CREATE POLICY health_prescriptions_delete_owner
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'health-prescriptions'
    AND private.can_delete_health_prescription(name)
  );

REVOKE ALL ON TABLE public.health_products FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.health_providers FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.health_products TO service_role;
GRANT ALL ON TABLE public.health_providers TO service_role;

DROP POLICY IF EXISTS health_products_public ON public.health_products;
CREATE POLICY health_products_public_verified
  ON public.health_products FOR SELECT TO anon, authenticated
  USING (
    active IS TRUE
    AND private.is_verified_active_health_provider(health_provider_id, NULL)
  );

DROP POLICY IF EXISTS health_providers_public ON public.health_providers;
CREATE POLICY health_providers_public_verified
  ON public.health_providers FOR SELECT TO anon, authenticated
  USING (private.is_verified_active_health_provider(id, NULL));

CREATE OR REPLACE FUNCTION private.get_public_health_products_internal()
RETURNS TABLE (
  id uuid, name text, description text, price numeric,
  requires_prescription boolean, available_quantity integer,
  provider_name text, provider_type text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT hpdt.id, hpdt.name, hpdt.description, hpdt.price,
         hpdt.requires_prescription,
         GREATEST(hpdt.stock_quantity - hpdt.reserved_quantity, 0),
         sp.display_name, hp.provider_type
  FROM public.health_products AS hpdt
  JOIN public.health_providers AS hp ON hp.id = hpdt.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  WHERE hpdt.active IS TRUE
    AND private.is_verified_active_health_provider(hp.id, NULL)
  ORDER BY hpdt.name
  LIMIT 100;
$function$;

CREATE OR REPLACE FUNCTION private.create_health_product_internal(
  p_name text, p_description text, p_price numeric,
  p_requires_prescription boolean, p_stock_quantity integer
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_health_provider_id uuid;
  v_product_id uuid;
  v_name text := NULLIF(pg_catalog.btrim(p_name), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF v_name IS NULL OR pg_catalog.char_length(v_name) > 160 THEN
    RAISE EXCEPTION 'product_name_required_or_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_description IS NOT NULL AND pg_catalog.char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'description_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_price IS NULL OR p_price < 0 OR p_stock_quantity IS NULL OR p_stock_quantity < 0
     OR p_requires_prescription IS NULL THEN
    RAISE EXCEPTION 'product_values_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT hp.id INTO v_health_provider_id
  FROM public.health_providers AS hp
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  JOIN public.profiles AS pr ON pr.id = sp.user_id
  WHERE sp.user_id = v_uid
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
  FOR SHARE OF hp, sp, pr;

  IF NOT FOUND THEN RAISE EXCEPTION 'verified_active_pharmacy_required' USING ERRCODE = '42501'; END IF;

  INSERT INTO public.health_products (
    health_provider_id, name, description, price,
    requires_prescription, stock_quantity, reserved_quantity, active
  )
  VALUES (
    v_health_provider_id, v_name, NULLIF(pg_catalog.btrim(p_description), ''),
    p_price, p_requires_prescription, p_stock_quantity, 0, p_stock_quantity > 0
  )
  RETURNING id INTO v_product_id;
  RETURN v_product_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.update_health_product_internal(
  p_product_id uuid, p_name text, p_description text, p_price numeric,
  p_requires_prescription boolean, p_stock_quantity integer, p_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_reserved integer;
  v_name text := NULLIF(pg_catalog.btrim(p_name), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_product_id IS NULL OR v_name IS NULL OR pg_catalog.char_length(v_name) > 160 THEN
    RAISE EXCEPTION 'product_identity_invalid' USING ERRCODE = '22023';
  END IF;
  IF p_description IS NOT NULL AND pg_catalog.char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'description_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_price IS NULL OR p_price < 0 OR p_stock_quantity IS NULL OR p_stock_quantity < 0
     OR p_requires_prescription IS NULL THEN
    RAISE EXCEPTION 'product_values_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT p.reserved_quantity INTO v_reserved
  FROM public.health_products AS p
  JOIN public.health_providers AS hp ON hp.id = p.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  JOIN public.profiles AS pr ON pr.id = sp.user_id
  WHERE p.id = p_product_id
    AND sp.user_id = v_uid
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
  FOR UPDATE OF p, hp, sp, pr;

  IF NOT FOUND THEN RAISE EXCEPTION 'product_not_found_or_not_owned' USING ERRCODE = 'P0002'; END IF;
  IF p_stock_quantity < v_reserved THEN
    RAISE EXCEPTION 'stock_below_reserved_quantity' USING ERRCODE = '23514';
  END IF;

  UPDATE public.health_products
  SET name = v_name,
      description = NULLIF(pg_catalog.btrim(p_description), ''),
      price = p_price,
      requires_prescription = p_requires_prescription,
      stock_quantity = p_stock_quantity,
      active = COALESCE(p_active, false) AND p_stock_quantity > 0
  WHERE id = p_product_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.get_my_health_products_internal()
RETURNS TABLE (
  product_id uuid, name text, description text, price numeric,
  requires_prescription boolean, stock_quantity integer,
  reserved_quantity integer, available_quantity integer, active boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  PERFORM private.expire_health_order_requests_internal();

  RETURN QUERY
  SELECT p.id, p.name, p.description, p.price, p.requires_prescription,
         p.stock_quantity, p.reserved_quantity,
         GREATEST(p.stock_quantity - p.reserved_quantity, 0), p.active
  FROM public.health_products AS p
  JOIN public.health_providers AS hp ON hp.id = p.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  WHERE sp.user_id = v_uid
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
  ORDER BY p.name
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION private.expire_health_order_requests_internal()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_row record;
  v_count integer := 0;
BEGIN
  FOR v_row IN
    SELECT r.id, r.product_id, r.quantity
    FROM public.health_order_requests AS r
    WHERE r.status IN ('PENDING_REVIEW', 'REQUESTED', 'APPROVED_FOR_DISPENSING', 'ACCEPTED')
      AND r.expires_at <= pg_catalog.now()
    ORDER BY r.expires_at
    FOR UPDATE SKIP LOCKED
  LOOP
    UPDATE public.health_products AS p
    SET reserved_quantity = p.reserved_quantity - v_row.quantity
    WHERE p.id = v_row.product_id AND p.reserved_quantity >= v_row.quantity;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'health_stock_reservation_inconsistent' USING ERRCODE = '23514';
    END IF;

    UPDATE public.health_order_requests AS r
    SET status = 'EXPIRED', updated_at = pg_catalog.now()
    WHERE r.id = v_row.id
      AND r.status IN ('PENDING_REVIEW', 'REQUESTED', 'APPROVED_FOR_DISPENSING', 'ACCEPTED');
    IF FOUND THEN v_count := v_count + 1; END IF;
  END LOOP;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION private.create_health_order_request_internal(
  p_product_id uuid, p_quantity integer, p_prescription_path text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_health_provider_id uuid;
  v_provider_name text;
  v_provider_type text;
  v_product_name text;
  v_price numeric(14,2);
  v_stock integer;
  v_reserved integer;
  v_requires_prescription boolean;
  v_request_id uuid;
  v_status text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_product_id IS NULL OR p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 50 THEN
    RAISE EXCEPTION 'order_values_invalid' USING ERRCODE = '22023';
  END IF;

  PERFORM private.expire_health_order_requests_internal();

  SELECT hp.id, sp.display_name, hp.provider_type, p.name, p.price,
         p.stock_quantity, p.reserved_quantity, p.requires_prescription
  INTO v_health_provider_id, v_provider_name, v_provider_type, v_product_name, v_price,
       v_stock, v_reserved, v_requires_prescription
  FROM public.health_products AS p
  JOIN public.health_providers AS hp ON hp.id = p.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  JOIN public.profiles AS pr ON pr.id = sp.user_id
  WHERE p.id = p_product_id
    AND p.active IS TRUE
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
    AND sp.user_id <> v_uid
  FOR UPDATE OF p, hp, sp, pr;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'verified_pharmacy_product_unavailable' USING ERRCODE = 'P0002';
  END IF;
  IF v_price IS NULL OR v_stock - v_reserved < p_quantity THEN
    RAISE EXCEPTION 'insufficient_health_product_stock' USING ERRCODE = '23514';
  END IF;

  IF v_requires_prescription IS TRUE THEN
    IF p_prescription_path IS NULL
       OR (storage.foldername(p_prescription_path))[1] <> v_uid::text
       OR pg_catalog.strpos(p_prescription_path, '..') > 0
       OR pg_catalog.char_length(p_prescription_path) > 512 THEN
      RAISE EXCEPTION 'prescription_upload_required' USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM storage.objects AS o
      WHERE o.bucket_id = 'health-prescriptions'
        AND o.name = p_prescription_path
        AND o.owner_id = v_uid::text
        AND o.metadata ->> 'mimetype' IN ('image/jpeg', 'image/png')
        AND o.created_at >= pg_catalog.now() - interval '30 minutes'
    ) THEN
      RAISE EXCEPTION 'prescription_upload_not_found_or_invalid' USING ERRCODE = '22023';
    END IF;
    v_status := 'PENDING_REVIEW';
  ELSE
    IF p_prescription_path IS NOT NULL THEN
      RAISE EXCEPTION 'prescription_not_expected_for_product' USING ERRCODE = '22023';
    END IF;
    v_status := 'REQUESTED';
  END IF;

  UPDATE public.health_products
  SET reserved_quantity = reserved_quantity + p_quantity
  WHERE id = p_product_id;

  INSERT INTO public.health_order_requests (
    product_id, health_provider_id, customer_id, product_name, provider_name, provider_type,
    requires_prescription, prescription_path, quantity, unit_price, total_amount, status, expires_at
  )
  VALUES (
    p_product_id, v_health_provider_id, v_uid, v_product_name, v_provider_name, v_provider_type,
    v_requires_prescription, p_prescription_path, p_quantity, v_price,
    pg_catalog.round(v_price * p_quantity, 2), v_status, pg_catalog.now() + interval '48 hours'
  )
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION private.cancel_health_order_request_internal(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_product_id uuid;
  v_quantity integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  SELECT r.product_id, r.quantity
  INTO v_product_id, v_quantity
  FROM public.health_order_requests AS r
  WHERE r.id = p_request_id
    AND r.customer_id = v_uid
    AND r.status IN ('PENDING_REVIEW', 'REQUESTED', 'APPROVED_FOR_DISPENSING', 'ACCEPTED')
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'health_order_not_cancellable' USING ERRCODE = 'P0002'; END IF;

  UPDATE public.health_products AS p
  SET reserved_quantity = p.reserved_quantity - v_quantity
  WHERE p.id = v_product_id AND p.reserved_quantity >= v_quantity;
  IF NOT FOUND THEN RAISE EXCEPTION 'health_stock_reservation_inconsistent' USING ERRCODE = '23514'; END IF;

  UPDATE public.health_order_requests AS r
  SET status = 'CANCELLED', updated_at = pg_catalog.now()
  WHERE r.id = p_request_id AND r.customer_id = v_uid
    AND r.status IN ('PENDING_REVIEW', 'REQUESTED', 'APPROVED_FOR_DISPENSING', 'ACCEPTED');
END;
$function$;

CREATE OR REPLACE FUNCTION private.get_my_health_order_requests_internal()
RETURNS TABLE (
  request_id uuid, product_name text, provider_name text,
  requires_prescription boolean, quantity integer, unit_price numeric,
  total_amount numeric, status text, review_note text,
  created_at timestamptz, expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  PERFORM private.expire_health_order_requests_internal();

  RETURN QUERY
  SELECT r.id, r.product_name, r.provider_name, r.requires_prescription,
         r.quantity, r.unit_price, r.total_amount, r.status, r.review_note,
         r.created_at, r.expires_at
  FROM public.health_order_requests AS r
  WHERE r.customer_id = v_uid
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION private.get_pharmacy_health_order_requests_internal()
RETURNS TABLE (
  request_id uuid, product_name text, requires_prescription boolean,
  prescription_path text, quantity integer, unit_price numeric,
  total_amount numeric, status text, review_note text,
  created_at timestamptz, expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  PERFORM private.expire_health_order_requests_internal();

  RETURN QUERY
  SELECT r.id, r.product_name, r.requires_prescription, r.prescription_path,
         r.quantity, r.unit_price, r.total_amount, r.status, r.review_note,
         r.created_at, r.expires_at
  FROM public.health_order_requests AS r
  JOIN public.health_providers AS hp ON hp.id = r.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  WHERE sp.user_id = v_uid
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION private.respond_health_order_request_internal(
  p_request_id uuid, p_decision text, p_review_note text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text;
  v_status text;
  v_requires_prescription boolean;
  v_product_id uuid;
  v_quantity integer;
  v_note text := NULLIF(pg_catalog.btrim(p_review_note), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_review_note IS NOT NULL AND pg_catalog.char_length(p_review_note) > 1000 THEN
    RAISE EXCEPTION 'review_note_too_long' USING ERRCODE = '22023';
  END IF;
  v_decision := pg_catalog.upper(pg_catalog.btrim(p_decision));
  IF v_decision IS NULL OR v_decision NOT IN ('APPROVE', 'ACCEPT', 'REJECT') THEN
    RAISE EXCEPTION 'health_order_decision_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT r.status, r.requires_prescription, r.product_id, r.quantity
  INTO v_status, v_requires_prescription, v_product_id, v_quantity
  FROM public.health_order_requests AS r
  JOIN public.health_products AS p ON p.id = r.product_id
  JOIN public.health_providers AS hp ON hp.id = r.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  JOIN public.profiles AS pr ON pr.id = sp.user_id
  WHERE r.id = p_request_id
    AND sp.user_id = v_uid
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
  FOR UPDATE OF r, p, hp, sp, pr;

  IF NOT FOUND THEN RAISE EXCEPTION 'health_order_not_found_or_not_owned' USING ERRCODE = 'P0002'; END IF;

  IF v_status = 'PENDING_REVIEW' AND v_requires_prescription IS TRUE THEN
    IF v_decision = 'APPROVE' THEN
      UPDATE public.health_order_requests
      SET status = 'APPROVED_FOR_DISPENSING', review_note = v_note,
          reviewed_by = v_uid, reviewed_at = pg_catalog.now(),
          expires_at = pg_catalog.now() + interval '24 hours',
          updated_at = pg_catalog.now()
      WHERE id = p_request_id AND status = 'PENDING_REVIEW';
      RETURN;
    ELSIF v_decision = 'REJECT' THEN
      UPDATE public.health_products
      SET reserved_quantity = reserved_quantity - v_quantity
      WHERE id = v_product_id AND reserved_quantity >= v_quantity;
      IF NOT FOUND THEN RAISE EXCEPTION 'health_stock_reservation_inconsistent' USING ERRCODE = '23514'; END IF;
      UPDATE public.health_order_requests
      SET status = 'REJECTED', review_note = v_note,
          reviewed_by = v_uid, reviewed_at = pg_catalog.now(),
          updated_at = pg_catalog.now()
      WHERE id = p_request_id AND status = 'PENDING_REVIEW';
      RETURN;
    END IF;
    RAISE EXCEPTION 'prescription_review_decision_required' USING ERRCODE = '22023';
  END IF;

  IF v_status = 'REQUESTED' AND v_requires_prescription IS FALSE THEN
    IF v_decision = 'ACCEPT' THEN
      UPDATE public.health_order_requests
      SET status = 'ACCEPTED', review_note = v_note,
          reviewed_by = v_uid, reviewed_at = pg_catalog.now(),
          expires_at = pg_catalog.now() + interval '24 hours',
          updated_at = pg_catalog.now()
      WHERE id = p_request_id AND status = 'REQUESTED';
      RETURN;
    ELSIF v_decision = 'REJECT' THEN
      UPDATE public.health_products
      SET reserved_quantity = reserved_quantity - v_quantity
      WHERE id = v_product_id AND reserved_quantity >= v_quantity;
      IF NOT FOUND THEN RAISE EXCEPTION 'health_stock_reservation_inconsistent' USING ERRCODE = '23514'; END IF;
      UPDATE public.health_order_requests
      SET status = 'REJECTED', review_note = v_note,
          reviewed_by = v_uid, reviewed_at = pg_catalog.now(),
          updated_at = pg_catalog.now()
      WHERE id = p_request_id AND status = 'REQUESTED';
      RETURN;
    END IF;
    RAISE EXCEPTION 'health_order_accept_or_reject_required' USING ERRCODE = '22023';
  END IF;

  RAISE EXCEPTION 'health_order_not_reviewable' USING ERRCODE = 'P0002';
END;
$function$;

CREATE OR REPLACE FUNCTION private.fulfill_health_order_request_internal(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_product_id uuid;
  v_quantity integer;
  v_stock integer;
  v_reserved integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501'; END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  SELECT r.product_id, r.quantity, p.stock_quantity, p.reserved_quantity
  INTO v_product_id, v_quantity, v_stock, v_reserved
  FROM public.health_order_requests AS r
  JOIN public.health_products AS p ON p.id = r.product_id
  JOIN public.health_providers AS hp ON hp.id = r.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  JOIN public.profiles AS pr ON pr.id = sp.user_id
  WHERE r.id = p_request_id
    AND sp.user_id = v_uid
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
    AND r.status IN ('APPROVED_FOR_DISPENSING', 'ACCEPTED')
  FOR UPDATE OF r, p, hp, sp, pr;

  IF NOT FOUND THEN RAISE EXCEPTION 'health_order_not_fulfillable_or_not_owned' USING ERRCODE = 'P0002'; END IF;
  IF v_stock < v_quantity OR v_reserved < v_quantity THEN
    RAISE EXCEPTION 'health_stock_reservation_inconsistent' USING ERRCODE = '23514';
  END IF;

  UPDATE public.health_products
  SET stock_quantity = stock_quantity - v_quantity,
      reserved_quantity = reserved_quantity - v_quantity,
      active = (stock_quantity - v_quantity) > 0
  WHERE id = v_product_id
    AND stock_quantity >= v_quantity
    AND reserved_quantity >= v_quantity;

  IF NOT FOUND THEN RAISE EXCEPTION 'health_stock_reservation_inconsistent' USING ERRCODE = '23514'; END IF;

  UPDATE public.health_order_requests
  SET status = 'DISPENSED', dispensed_at = pg_catalog.now(), updated_at = pg_catalog.now()
  WHERE id = p_request_id AND status IN ('APPROVED_FOR_DISPENSING', 'ACCEPTED');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_health_products()
RETURNS TABLE (
  id uuid, name text, description text, price numeric,
  requires_prescription boolean, available_quantity integer,
  provider_name text, provider_type text
)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT * FROM private.get_public_health_products_internal(); $function$;

CREATE OR REPLACE FUNCTION public.create_health_product(
  p_name text, p_description text, p_price numeric,
  p_requires_prescription boolean, p_stock_quantity integer
)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$
  SELECT private.create_health_product_internal(
    p_name, p_description, p_price, p_requires_prescription, p_stock_quantity
  );
$function$;

CREATE OR REPLACE FUNCTION public.update_health_product(
  p_product_id uuid, p_name text, p_description text, p_price numeric,
  p_requires_prescription boolean, p_stock_quantity integer, p_active boolean
)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$
  SELECT private.update_health_product_internal(
    p_product_id, p_name, p_description, p_price,
    p_requires_prescription, p_stock_quantity, p_active
  );
$function$;

CREATE OR REPLACE FUNCTION public.get_my_health_products()
RETURNS TABLE (
  product_id uuid, name text, description text, price numeric,
  requires_prescription boolean, stock_quantity integer,
  reserved_quantity integer, available_quantity integer, active boolean
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT * FROM private.get_my_health_products_internal(); $function$;

CREATE OR REPLACE FUNCTION public.create_health_order_request(
  p_product_id uuid, p_quantity integer, p_prescription_path text DEFAULT NULL
)
RETURNS uuid
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$
  SELECT private.create_health_order_request_internal(
    p_product_id, p_quantity, p_prescription_path
  );
$function$;

CREATE OR REPLACE FUNCTION public.cancel_health_order_request(p_request_id uuid)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT private.cancel_health_order_request_internal(p_request_id); $function$;

CREATE OR REPLACE FUNCTION public.get_my_health_order_requests()
RETURNS TABLE (
  request_id uuid, product_name text, provider_name text,
  requires_prescription boolean, quantity integer, unit_price numeric,
  total_amount numeric, status text, review_note text,
  created_at timestamptz, expires_at timestamptz
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT * FROM private.get_my_health_order_requests_internal(); $function$;

CREATE OR REPLACE FUNCTION public.get_pharmacy_health_order_requests()
RETURNS TABLE (
  request_id uuid, product_name text, requires_prescription boolean,
  prescription_path text, quantity integer, unit_price numeric,
  total_amount numeric, status text, review_note text,
  created_at timestamptz, expires_at timestamptz
)
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT * FROM private.get_pharmacy_health_order_requests_internal(); $function$;

CREATE OR REPLACE FUNCTION public.respond_health_order_request(
  p_request_id uuid, p_decision text, p_review_note text DEFAULT NULL
)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$
  SELECT private.respond_health_order_request_internal(
    p_request_id, p_decision, p_review_note
  );
$function$;

CREATE OR REPLACE FUNCTION public.fulfill_health_order_request(p_request_id uuid)
RETURNS void
LANGUAGE sql VOLATILE SECURITY INVOKER SET search_path = ''
AS $function$ SELECT private.fulfill_health_order_request_internal(p_request_id); $function$;

ALTER FUNCTION private.get_public_health_products_internal() OWNER TO postgres;
ALTER FUNCTION private.create_health_product_internal(text, text, numeric, boolean, integer) OWNER TO postgres;
ALTER FUNCTION private.update_health_product_internal(uuid, text, text, numeric, boolean, integer, boolean) OWNER TO postgres;
ALTER FUNCTION private.get_my_health_products_internal() OWNER TO postgres;
ALTER FUNCTION private.expire_health_order_requests_internal() OWNER TO postgres;
ALTER FUNCTION private.create_health_order_request_internal(uuid, integer, text) OWNER TO postgres;
ALTER FUNCTION private.cancel_health_order_request_internal(uuid) OWNER TO postgres;
ALTER FUNCTION private.get_my_health_order_requests_internal() OWNER TO postgres;
ALTER FUNCTION private.get_pharmacy_health_order_requests_internal() OWNER TO postgres;
ALTER FUNCTION private.respond_health_order_request_internal(uuid, text, text) OWNER TO postgres;
ALTER FUNCTION private.fulfill_health_order_request_internal(uuid) OWNER TO postgres;

REVOKE ALL ON FUNCTION private.get_public_health_products_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.create_health_product_internal(text, text, numeric, boolean, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.update_health_product_internal(uuid, text, text, numeric, boolean, integer, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.get_my_health_products_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.expire_health_order_requests_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.create_health_order_request_internal(uuid, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.cancel_health_order_request_internal(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.get_my_health_order_requests_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.get_pharmacy_health_order_requests_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.respond_health_order_request_internal(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.fulfill_health_order_request_internal(uuid) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION private.get_public_health_products_internal() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_health_product_internal(text, text, numeric, boolean, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION private.update_health_product_internal(uuid, text, text, numeric, boolean, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION private.get_my_health_products_internal() TO authenticated;
GRANT EXECUTE ON FUNCTION private.create_health_order_request_internal(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.cancel_health_order_request_internal(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.get_my_health_order_requests_internal() TO authenticated;
GRANT EXECUTE ON FUNCTION private.get_pharmacy_health_order_requests_internal() TO authenticated;
GRANT EXECUTE ON FUNCTION private.respond_health_order_request_internal(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.fulfill_health_order_request_internal(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.get_public_health_products() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_health_product(text, text, numeric, boolean, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_health_product(uuid, text, text, numeric, boolean, integer, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_health_products() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_health_order_request(uuid, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_health_order_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_health_order_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_pharmacy_health_order_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_health_order_request(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fulfill_health_order_request(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_public_health_products() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_health_product(text, text, numeric, boolean, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_health_product(uuid, text, text, numeric, boolean, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_health_products() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_health_order_request(uuid, integer, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_health_order_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_health_order_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pharmacy_health_order_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_health_order_request(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_health_order_request(uuid) TO authenticated;

ALTER FUNCTION public.get_public_health_products() OWNER TO postgres;
ALTER FUNCTION public.create_health_product(text, text, numeric, boolean, integer) OWNER TO postgres;
ALTER FUNCTION public.update_health_product(uuid, text, text, numeric, boolean, integer, boolean) OWNER TO postgres;
ALTER FUNCTION public.get_my_health_products() OWNER TO postgres;
ALTER FUNCTION public.create_health_order_request(uuid, integer, text) OWNER TO postgres;
ALTER FUNCTION public.cancel_health_order_request(uuid) OWNER TO postgres;
ALTER FUNCTION public.get_my_health_order_requests() OWNER TO postgres;
ALTER FUNCTION public.get_pharmacy_health_order_requests() OWNER TO postgres;
ALTER FUNCTION public.respond_health_order_request(uuid, text, text) OWNER TO postgres;
ALTER FUNCTION public.fulfill_health_order_request(uuid) OWNER TO postgres;
