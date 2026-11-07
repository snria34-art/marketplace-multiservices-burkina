CREATE OR REPLACE FUNCTION private.is_verified_active_seller(p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM public.sellers AS s
    JOIN public.profiles AS p ON p.id = s.user_id
    WHERE s.id = p_seller_id
      AND s.verification_status = 'VERIFIED'::public.verification_status
      AND p.status = 'ACTIVE'::public.account_status
  );
$function$;

ALTER FUNCTION private.is_verified_active_seller(uuid) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.is_verified_active_seller(uuid) FROM PUBLIC;
GRANT USAGE ON SCHEMA private TO anon, authenticated;
GRANT EXECUTE ON FUNCTION private.is_verified_active_seller(uuid) TO anon, authenticated;

GRANT SELECT (id, business_name, verification_status)
  ON TABLE public.sellers TO anon;

DROP POLICY IF EXISTS sellers_public_verified ON public.sellers;
CREATE POLICY sellers_public_verified
  ON public.sellers
  FOR SELECT TO anon
  USING (private.is_verified_active_seller(id));

DROP POLICY IF EXISTS agriculture_public ON public.agriculture_listings;
CREATE POLICY agriculture_public_verified
  ON public.agriculture_listings
  FOR SELECT TO anon, authenticated
  USING (
    active IS TRUE
    AND seller_id IS NOT NULL
    AND private.is_verified_active_seller(seller_id)
  );

ALTER TABLE public.agriculture_listings
  ADD COLUMN IF NOT EXISTS reserved_quantity numeric(16,3) NOT NULL DEFAULT 0;

ALTER TABLE public.agriculture_listings
  DROP CONSTRAINT IF EXISTS agriculture_listings_reserved_quantity_nonnegative;
ALTER TABLE public.agriculture_listings
  ADD CONSTRAINT agriculture_listings_reserved_quantity_nonnegative
  CHECK (reserved_quantity >= 0);

ALTER TABLE public.agriculture_listings
  DROP CONSTRAINT IF EXISTS agriculture_listings_reserved_not_above_quantity;
ALTER TABLE public.agriculture_listings
  ADD CONSTRAINT agriculture_listings_reserved_not_above_quantity
  CHECK (quantity IS NULL OR reserved_quantity <= quantity);

CREATE INDEX IF NOT EXISTS idx_agriculture_listings_public_active_seller
  ON public.agriculture_listings (seller_id, created_at DESC)
  WHERE active IS TRUE;

CREATE TABLE public.agriculture_order_requests (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES public.agriculture_listings(id) ON DELETE RESTRICT,
  seller_id uuid NOT NULL REFERENCES public.sellers(id) ON DELETE RESTRICT,
  customer_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  listing_name text NOT NULL,
  listing_type text NOT NULL
    CHECK (listing_type IN ('PRODUCE', 'LIVESTOCK', 'SEEDS', 'EQUIPMENT', 'INPUTS')),
  quantity numeric(16,3) NOT NULL CHECK (quantity > 0),
  unit text NOT NULL,
  unit_price numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  total_amount numeric(16,2) NOT NULL CHECK (total_amount >= 0),
  status text NOT NULL DEFAULT 'REQUESTED'
    CHECK (status IN ('REQUESTED', 'ACCEPTED', 'REJECTED', 'CANCELLED', 'FULFILLED')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now()
);

CREATE INDEX agriculture_order_requests_customer_created_idx
  ON public.agriculture_order_requests (customer_id, created_at DESC);
CREATE INDEX agriculture_order_requests_seller_status_created_idx
  ON public.agriculture_order_requests (seller_id, status, created_at DESC);
CREATE INDEX agriculture_order_requests_listing_status_created_idx
  ON public.agriculture_order_requests (listing_id, status, created_at DESC);

ALTER TABLE public.agriculture_order_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.agriculture_order_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.agriculture_order_requests TO service_role;

CREATE POLICY agriculture_order_requests_active_account_guard
  ON public.agriculture_order_requests
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (private.is_active_account())
  WITH CHECK (private.is_active_account());

COMMENT ON TABLE public.agriculture_order_requests IS
  'Agriculture-specific stock reservations and seller decisions. Client writes are only through guarded RPCs; no in-app payment is executed by this workflow.';

CREATE OR REPLACE FUNCTION public.create_agriculture_listing(
  p_listing_type text, p_name text, p_description text,
  p_price numeric, p_unit text, p_quantity numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_seller_id uuid;
  v_listing_id uuid;
  v_type text := pg_catalog.upper(pg_catalog.btrim(p_listing_type));
  v_name text := NULLIF(pg_catalog.btrim(p_name), '');
  v_unit text := NULLIF(pg_catalog.btrim(p_unit), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF v_type NOT IN ('PRODUCE', 'LIVESTOCK', 'SEEDS', 'EQUIPMENT', 'INPUTS') THEN
    RAISE EXCEPTION 'listing_type_invalid' USING ERRCODE = '22023';
  END IF;
  IF v_name IS NULL OR pg_catalog.char_length(v_name) > 160 THEN
    RAISE EXCEPTION 'listing_name_required_or_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_description IS NOT NULL AND pg_catalog.char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'description_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'price_invalid' USING ERRCODE = '22023';
  END IF;
  IF v_unit IS NULL OR pg_catalog.char_length(v_unit) > 32 THEN
    RAISE EXCEPTION 'unit_required_or_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_quantity IS NULL OR p_quantity < 0 OR p_quantity <> pg_catalog.round(p_quantity, 3) THEN
    RAISE EXCEPTION 'quantity_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT s.id
    INTO v_seller_id
  FROM public.sellers AS s
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE s.user_id = v_uid
    AND s.verification_status = 'VERIFIED'::public.verification_status
    AND p.status = 'ACTIVE'::public.account_status
  FOR SHARE OF s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'verified_seller_required' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.agriculture_listings (
    seller_id, listing_type, name, description, price, unit,
    quantity, reserved_quantity, active
  )
  VALUES (
    v_seller_id, v_type, v_name, NULLIF(pg_catalog.btrim(p_description), ''),
    p_price, v_unit, p_quantity, 0, p_quantity > 0
  )
  RETURNING id INTO v_listing_id;

  RETURN v_listing_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.update_agriculture_listing(
  p_listing_id uuid, p_listing_type text, p_name text, p_description text,
  p_price numeric, p_unit text, p_quantity numeric, p_active boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_reserved numeric(16,3);
  v_seller_verified boolean;
  v_profile_active boolean;
  v_type text := pg_catalog.upper(pg_catalog.btrim(p_listing_type));
  v_name text := NULLIF(pg_catalog.btrim(p_name), '');
  v_unit text := NULLIF(pg_catalog.btrim(p_unit), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_listing_id IS NULL THEN
    RAISE EXCEPTION 'listing_id_required' USING ERRCODE = '22023';
  END IF;
  IF v_type NOT IN ('PRODUCE', 'LIVESTOCK', 'SEEDS', 'EQUIPMENT', 'INPUTS') THEN
    RAISE EXCEPTION 'listing_type_invalid' USING ERRCODE = '22023';
  END IF;
  IF v_name IS NULL OR pg_catalog.char_length(v_name) > 160 THEN
    RAISE EXCEPTION 'listing_name_required_or_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_description IS NOT NULL AND pg_catalog.char_length(p_description) > 2000 THEN
    RAISE EXCEPTION 'description_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    RAISE EXCEPTION 'price_invalid' USING ERRCODE = '22023';
  END IF;
  IF v_unit IS NULL OR pg_catalog.char_length(v_unit) > 32 THEN
    RAISE EXCEPTION 'unit_required_or_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_quantity IS NULL OR p_quantity < 0 OR p_quantity <> pg_catalog.round(p_quantity, 3) THEN
    RAISE EXCEPTION 'quantity_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT l.reserved_quantity,
         (s.verification_status = 'VERIFIED'::public.verification_status),
         (p.status = 'ACTIVE'::public.account_status)
    INTO v_reserved, v_seller_verified, v_profile_active
  FROM public.agriculture_listings AS l
  JOIN public.sellers AS s ON s.id = l.seller_id
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE l.id = p_listing_id AND s.user_id = v_uid
  FOR UPDATE OF l, s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listing_not_found_or_not_owned' USING ERRCODE = 'P0002';
  END IF;
  IF v_seller_verified IS NOT TRUE OR v_profile_active IS NOT TRUE THEN
    RAISE EXCEPTION 'verified_active_seller_required' USING ERRCODE = '42501';
  END IF;
  IF p_quantity < v_reserved THEN
    RAISE EXCEPTION 'quantity_below_reserved_stock' USING ERRCODE = '23514';
  END IF;

  UPDATE public.agriculture_listings
  SET listing_type = v_type,
      name = v_name,
      description = NULLIF(pg_catalog.btrim(p_description), ''),
      price = p_price,
      unit = v_unit,
      quantity = p_quantity,
      active = COALESCE(p_active, false) AND p_quantity > 0
  WHERE id = p_listing_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_agriculture_listings()
RETURNS TABLE (
  listing_id uuid, listing_type text, name text, description text,
  price numeric, unit text, quantity numeric, reserved_quantity numeric,
  available_quantity numeric, active boolean, created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT l.id, l.listing_type, l.name, l.description, l.price, l.unit,
         l.quantity, l.reserved_quantity,
         GREATEST(l.quantity - l.reserved_quantity, 0),
         l.active, l.created_at
  FROM public.agriculture_listings AS l
  JOIN public.sellers AS s ON s.id = l.seller_id
  WHERE s.user_id = v_uid
  ORDER BY l.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_agriculture_order_request(
  p_listing_id uuid, p_quantity numeric
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_seller_id uuid;
  v_name text;
  v_type text;
  v_price numeric(14,2);
  v_unit text;
  v_stock numeric;
  v_reserved numeric;
  v_order_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_listing_id IS NULL THEN
    RAISE EXCEPTION 'listing_id_required' USING ERRCODE = '22023';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_quantity <> pg_catalog.round(p_quantity, 3) THEN
    RAISE EXCEPTION 'quantity_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT l.seller_id, l.name, l.listing_type, l.price, l.unit,
         l.quantity, l.reserved_quantity
    INTO v_seller_id, v_name, v_type, v_price, v_unit, v_stock, v_reserved
  FROM public.agriculture_listings AS l
  JOIN public.sellers AS s ON s.id = l.seller_id
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE l.id = p_listing_id
    AND l.active IS TRUE
    AND l.price IS NOT NULL
    AND l.quantity IS NOT NULL
    AND l.unit IS NOT NULL
    AND s.verification_status = 'VERIFIED'::public.verification_status
    AND p.status = 'ACTIVE'::public.account_status
    AND s.user_id <> v_uid
  FOR UPDATE OF l, s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listing_unavailable' USING ERRCODE = 'P0002';
  END IF;
  IF v_stock - v_reserved < p_quantity THEN
    RAISE EXCEPTION 'insufficient_available_stock' USING ERRCODE = '23514';
  END IF;

  UPDATE public.agriculture_listings
  SET reserved_quantity = reserved_quantity + p_quantity
  WHERE id = p_listing_id;

  INSERT INTO public.agriculture_order_requests (
    listing_id, seller_id, customer_id, listing_name, listing_type,
    quantity, unit, unit_price, total_amount, status
  )
  VALUES (
    p_listing_id, v_seller_id, v_uid, v_name, v_type,
    p_quantity, v_unit, v_price, pg_catalog.round(p_quantity * v_price, 2), 'REQUESTED'
  )
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_agriculture_order_request(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_listing_id uuid;
  v_quantity numeric(16,3);
  v_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  SELECT r.listing_id, r.quantity, r.status
    INTO v_listing_id, v_quantity, v_status
  FROM public.agriculture_order_requests AS r
  WHERE r.id = p_order_id
    AND r.customer_id = v_uid
    AND r.status IN ('REQUESTED', 'ACCEPTED')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_cancellable' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.agriculture_listings
  SET reserved_quantity = reserved_quantity - v_quantity
  WHERE id = v_listing_id AND reserved_quantity >= v_quantity;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'reserved_stock_inconsistent' USING ERRCODE = '23514';
  END IF;

  UPDATE public.agriculture_order_requests
  SET status = 'CANCELLED', updated_at = pg_catalog.now()
  WHERE id = p_order_id
    AND customer_id = v_uid
    AND status IN ('REQUESTED', 'ACCEPTED');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_agriculture_order_requests()
RETURNS TABLE (
  order_id uuid, listing_id uuid, listing_name text, listing_type text,
  seller_name text, quantity numeric, unit text, unit_price numeric,
  total_amount numeric, status text, created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT r.id, r.listing_id, r.listing_name, r.listing_type,
         s.business_name, r.quantity, r.unit, r.unit_price, r.total_amount,
         r.status, r.created_at
  FROM public.agriculture_order_requests AS r
  JOIN public.sellers AS s ON s.id = r.seller_id
  WHERE r.customer_id = v_uid
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_seller_agriculture_order_requests()
RETURNS TABLE (
  order_id uuid, listing_id uuid, listing_name text, listing_type text,
  quantity numeric, unit text, unit_price numeric, total_amount numeric,
  status text, created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT r.id, r.listing_id, r.listing_name, r.listing_type,
         r.quantity, r.unit, r.unit_price, r.total_amount, r.status, r.created_at
  FROM public.agriculture_order_requests AS r
  JOIN public.sellers AS s ON s.id = r.seller_id
  WHERE s.user_id = v_uid
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_agriculture_order_request(
  p_order_id uuid, p_decision text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text;
  v_listing_id uuid;
  v_quantity numeric(16,3);
  v_status text;
  v_seller_verified boolean;
  v_profile_active boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  v_decision := pg_catalog.upper(pg_catalog.btrim(p_decision));
  IF v_decision IS NULL OR v_decision NOT IN ('ACCEPT', 'DECLINE') THEN
    RAISE EXCEPTION 'decision_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT r.listing_id, r.quantity, r.status,
         (s.verification_status = 'VERIFIED'::public.verification_status),
         (p.status = 'ACTIVE'::public.account_status)
    INTO v_listing_id, v_quantity, v_status, v_seller_verified, v_profile_active
  FROM public.agriculture_order_requests AS r
  JOIN public.sellers AS s ON s.id = r.seller_id
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE r.id = p_order_id
    AND s.user_id = v_uid
    AND r.status = 'REQUESTED'
  FOR UPDATE OF r, s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found_or_not_owned' USING ERRCODE = 'P0002';
  END IF;
  IF v_profile_active IS NOT TRUE THEN
    RAISE EXCEPTION 'seller_account_not_active' USING ERRCODE = '42501';
  END IF;

  IF v_decision = 'ACCEPT' THEN
    IF v_seller_verified IS NOT TRUE THEN
      RAISE EXCEPTION 'verified_seller_required' USING ERRCODE = '42501';
    END IF;

    UPDATE public.agriculture_order_requests
    SET status = 'ACCEPTED', updated_at = pg_catalog.now()
    WHERE id = p_order_id AND status = 'REQUESTED';
  ELSE
    UPDATE public.agriculture_listings
    SET reserved_quantity = reserved_quantity - v_quantity
    WHERE id = v_listing_id AND reserved_quantity >= v_quantity;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'reserved_stock_inconsistent' USING ERRCODE = '23514';
    END IF;

    UPDATE public.agriculture_order_requests
    SET status = 'REJECTED', updated_at = pg_catalog.now()
    WHERE id = p_order_id AND status = 'REQUESTED';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fulfill_agriculture_order_request(p_order_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_listing_id uuid;
  v_quantity numeric(16,3);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  SELECT r.listing_id, r.quantity
    INTO v_listing_id, v_quantity
  FROM public.agriculture_order_requests AS r
  JOIN public.sellers AS s ON s.id = r.seller_id
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE r.id = p_order_id
    AND s.user_id = v_uid
    AND p.status = 'ACTIVE'::public.account_status
    AND r.status = 'ACCEPTED'
  FOR UPDATE OF r, s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_fulfillable_or_not_owned' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.agriculture_listings
  SET quantity = quantity - v_quantity,
      reserved_quantity = reserved_quantity - v_quantity,
      active = (quantity - v_quantity) > 0
  WHERE id = v_listing_id
    AND quantity >= v_quantity
    AND reserved_quantity >= v_quantity;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'stock_reservation_inconsistent' USING ERRCODE = '23514';
  END IF;

  UPDATE public.agriculture_order_requests
  SET status = 'FULFILLED', updated_at = pg_catalog.now()
  WHERE id = p_order_id AND status = 'ACCEPTED';
END;
$function$;

REVOKE ALL ON FUNCTION public.create_agriculture_listing(text, text, text, numeric, text, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_agriculture_listing(uuid, text, text, text, numeric, text, numeric, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_agriculture_listings() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_agriculture_order_request(uuid, numeric) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_agriculture_order_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_agriculture_order_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_seller_agriculture_order_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_agriculture_order_request(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fulfill_agriculture_order_request(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_agriculture_listing(text, text, text, numeric, text, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_agriculture_listing(uuid, text, text, text, numeric, text, numeric, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_agriculture_listings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_agriculture_order_request(uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_agriculture_order_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_agriculture_order_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_seller_agriculture_order_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_agriculture_order_request(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_agriculture_order_request(uuid) TO authenticated;

ALTER FUNCTION public.create_agriculture_listing(text, text, text, numeric, text, numeric) OWNER TO postgres;
ALTER FUNCTION public.update_agriculture_listing(uuid, text, text, text, numeric, text, numeric, boolean) OWNER TO postgres;
ALTER FUNCTION public.get_my_agriculture_listings() OWNER TO postgres;
ALTER FUNCTION public.create_agriculture_order_request(uuid, numeric) OWNER TO postgres;
ALTER FUNCTION public.cancel_agriculture_order_request(uuid) OWNER TO postgres;
ALTER FUNCTION public.get_my_agriculture_order_requests() OWNER TO postgres;
ALTER FUNCTION public.get_seller_agriculture_order_requests() OWNER TO postgres;
ALTER FUNCTION public.respond_agriculture_order_request(uuid, text) OWNER TO postgres;
ALTER FUNCTION public.fulfill_agriculture_order_request(uuid) OWNER TO postgres;
