DROP POLICY IF EXISTS sellers_public_verified ON public.sellers;
CREATE POLICY sellers_public_verified
  ON public.sellers
  FOR SELECT TO anon, authenticated
  USING (private.is_verified_active_seller(id));

CREATE OR REPLACE FUNCTION public.respond_agriculture_order_request(
  p_order_id uuid,
  p_decision text
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
  v_listing_active boolean;
  v_reserved numeric(16,3);
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

  SELECT
    r.listing_id,
    r.quantity,
    r.status,
    (s.verification_status = 'VERIFIED'::public.verification_status),
    (p.status = 'ACTIVE'::public.account_status),
    l.active,
    l.reserved_quantity
  INTO
    v_listing_id,
    v_quantity,
    v_status,
    v_seller_verified,
    v_profile_active,
    v_listing_active,
    v_reserved
  FROM public.agriculture_order_requests AS r
  JOIN public.agriculture_listings AS l ON l.id = r.listing_id
  JOIN public.sellers AS s ON s.id = r.seller_id
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE r.id = p_order_id
    AND s.user_id = v_uid
    AND r.status = 'REQUESTED'
  FOR UPDATE OF r, l, s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found_or_not_owned' USING ERRCODE = 'P0002';
  END IF;
  IF v_profile_active IS NOT TRUE THEN
    RAISE EXCEPTION 'seller_account_not_active' USING ERRCODE = '42501';
  END IF;
  IF v_reserved < v_quantity THEN
    RAISE EXCEPTION 'reserved_stock_inconsistent' USING ERRCODE = '23514';
  END IF;

  IF v_decision = 'ACCEPT' THEN
    IF v_seller_verified IS NOT TRUE OR v_listing_active IS NOT TRUE THEN
      RAISE EXCEPTION 'verified_active_listing_required' USING ERRCODE = '42501';
    END IF;

    UPDATE public.agriculture_order_requests
    SET status = 'ACCEPTED', updated_at = pg_catalog.now()
    WHERE id = p_order_id AND status = 'REQUESTED';
  ELSE
    UPDATE public.agriculture_listings
    SET reserved_quantity = reserved_quantity - v_quantity
    WHERE id = v_listing_id
      AND reserved_quantity >= v_quantity;

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
  v_seller_verified boolean;
  v_stock numeric(16,3);
  v_reserved numeric(16,3);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;

  SELECT
    r.listing_id,
    r.quantity,
    (s.verification_status = 'VERIFIED'::public.verification_status),
    l.quantity,
    l.reserved_quantity
  INTO
    v_listing_id,
    v_quantity,
    v_seller_verified,
    v_stock,
    v_reserved
  FROM public.agriculture_order_requests AS r
  JOIN public.agriculture_listings AS l ON l.id = r.listing_id
  JOIN public.sellers AS s ON s.id = r.seller_id
  JOIN public.profiles AS p ON p.id = s.user_id
  WHERE r.id = p_order_id
    AND s.user_id = v_uid
    AND p.status = 'ACTIVE'::public.account_status
    AND r.status = 'ACCEPTED'
  FOR UPDATE OF r, l, s, p;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_fulfillable_or_not_owned' USING ERRCODE = 'P0002';
  END IF;
  IF v_seller_verified IS NOT TRUE THEN
    RAISE EXCEPTION 'verified_seller_required' USING ERRCODE = '42501';
  END IF;
  IF v_stock IS NULL OR v_stock < v_quantity OR v_reserved < v_quantity THEN
    RAISE EXCEPTION 'stock_reservation_inconsistent' USING ERRCODE = '23514';
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

REVOKE ALL ON FUNCTION public.respond_agriculture_order_request(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fulfill_agriculture_order_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_agriculture_order_request(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fulfill_agriculture_order_request(uuid) TO authenticated;
ALTER FUNCTION public.respond_agriculture_order_request(uuid, text) OWNER TO postgres;
ALTER FUNCTION public.fulfill_agriculture_order_request(uuid) OWNER TO postgres;
