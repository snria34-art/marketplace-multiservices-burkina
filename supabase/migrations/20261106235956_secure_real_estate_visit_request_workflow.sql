CREATE TABLE public.real_estate_visit_requests (
  id uuid PRIMARY KEY DEFAULT pg_catalog.gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES public.real_estate_listings(id) ON DELETE RESTRICT,
  requester_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  preferred_visit_at timestamptz,
  message text,
  status text NOT NULL DEFAULT 'REQUESTED'
    CHECK (status IN ('REQUESTED', 'ACCEPTED', 'DECLINED', 'CANCELLED')),
  created_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  updated_at timestamptz NOT NULL DEFAULT pg_catalog.now(),
  CONSTRAINT real_estate_visit_requests_message_length_check
    CHECK (message IS NULL OR pg_catalog.char_length(message) <= 1000),
  CONSTRAINT real_estate_visit_requests_preferred_visit_check
    CHECK (preferred_visit_at IS NULL OR preferred_visit_at > created_at)
);

CREATE UNIQUE INDEX real_estate_visit_requests_one_pending_per_user_listing
  ON public.real_estate_visit_requests (listing_id, requester_id)
  WHERE status = 'REQUESTED';

CREATE INDEX real_estate_visit_requests_requester_created_idx
  ON public.real_estate_visit_requests (requester_id, created_at DESC);

CREATE INDEX real_estate_visit_requests_listing_status_created_idx
  ON public.real_estate_visit_requests (listing_id, status, created_at DESC);

ALTER TABLE public.real_estate_visit_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.real_estate_visit_requests FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.real_estate_visit_requests TO service_role;

CREATE POLICY real_estate_visit_requests_active_account_guard
  ON public.real_estate_visit_requests
  AS RESTRICTIVE
  FOR ALL
  TO authenticated
  USING (private.is_active_account())
  WITH CHECK (private.is_active_account());

COMMENT ON TABLE public.real_estate_visit_requests IS
  'Private visit/inquiry requests. Public clients must use the guarded RPC functions; no direct table grants are exposed.';

CREATE OR REPLACE FUNCTION public.request_real_estate_visit(
  p_listing_id uuid,
  p_preferred_visit_at timestamptz DEFAULT NULL,
  p_message text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_provider_id uuid;
  v_request_id uuid;
  v_message text;
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
  IF p_preferred_visit_at IS NOT NULL
     AND (p_preferred_visit_at <= pg_catalog.now()
       OR p_preferred_visit_at > pg_catalog.now() + interval '180 days') THEN
    RAISE EXCEPTION 'preferred_visit_time_invalid' USING ERRCODE = '22023';
  END IF;
  IF p_message IS NOT NULL AND pg_catalog.char_length(p_message) > 1000 THEN
    RAISE EXCEPTION 'message_too_long' USING ERRCODE = '22023';
  END IF;
  v_message := NULLIF(pg_catalog.btrim(p_message), '');

  SELECT l.provider_id
    INTO v_provider_id
  FROM public.real_estate_listings AS l
  JOIN public.service_providers AS sp ON sp.id = l.provider_id
  WHERE l.id = p_listing_id
    AND l.active IS TRUE
    AND l.verification_status = 'VERIFIED'::public.verification_status
    AND sp.active IS TRUE
    AND sp.verification_status = 'VERIFIED'::public.verification_status
    AND sp.user_id <> v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'listing_unavailable' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.real_estate_visit_requests (
    listing_id, requester_id, preferred_visit_at, message
  )
  VALUES (p_listing_id, v_uid, p_preferred_visit_at, v_message)
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'request_already_pending' USING ERRCODE = '23505';
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_real_estate_visit(p_request_id uuid)
RETURNS void
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
  UPDATE public.real_estate_visit_requests
  SET status = 'CANCELLED', updated_at = pg_catalog.now()
  WHERE id = p_request_id AND requester_id = v_uid AND status = 'REQUESTED';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_cancellable' USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_real_estate_visit_requests()
RETURNS TABLE (
  request_id uuid, listing_id uuid, listing_title text, listing_type text,
  city text, preferred_visit_at timestamptz, message text, status text, created_at timestamptz
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
  SELECT r.id, l.id, l.title, l.listing_type, l.city,
         r.preferred_visit_at, r.message, r.status, r.created_at
  FROM public.real_estate_visit_requests AS r
  JOIN public.real_estate_listings AS l ON l.id = r.listing_id
  WHERE r.requester_id = v_uid
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_provider_real_estate_visit_requests()
RETURNS TABLE (
  request_id uuid, listing_id uuid, listing_title text, listing_type text,
  city text, preferred_visit_at timestamptz, message text, status text, created_at timestamptz
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
  SELECT r.id, l.id, l.title, l.listing_type, l.city,
         r.preferred_visit_at, r.message, r.status, r.created_at
  FROM public.real_estate_visit_requests AS r
  JOIN public.real_estate_listings AS l ON l.id = r.listing_id
  JOIN public.service_providers AS sp ON sp.id = l.provider_id
  WHERE sp.user_id = v_uid
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_real_estate_visit(
  p_request_id uuid, p_decision text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_decision text;
  v_listing_active boolean;
  v_listing_verification public.verification_status;
  v_provider_active boolean;
  v_provider_verification public.verification_status;
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

  SELECT l.active, l.verification_status, sp.active, sp.verification_status
  INTO v_listing_active, v_listing_verification, v_provider_active, v_provider_verification
  FROM public.real_estate_visit_requests AS r
  JOIN public.real_estate_listings AS l ON l.id = r.listing_id
  JOIN public.service_providers AS sp ON sp.id = l.provider_id
  WHERE r.id = p_request_id AND r.status = 'REQUESTED' AND sp.user_id = v_uid
  FOR UPDATE OF r;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_found_or_not_owned' USING ERRCODE = 'P0002';
  END IF;

  IF v_decision = 'ACCEPT'
     AND (v_listing_active IS NOT TRUE
       OR v_listing_verification <> 'VERIFIED'::public.verification_status
       OR v_provider_active IS NOT TRUE
       OR v_provider_verification <> 'VERIFIED'::public.verification_status) THEN
    RAISE EXCEPTION 'listing_or_provider_unavailable' USING ERRCODE = '42501';
  END IF;

  UPDATE public.real_estate_visit_requests
  SET status = CASE WHEN v_decision = 'ACCEPT' THEN 'ACCEPTED' ELSE 'DECLINED' END,
      updated_at = pg_catalog.now()
  WHERE id = p_request_id AND status = 'REQUESTED';
END;
$function$;

REVOKE ALL ON FUNCTION public.request_real_estate_visit(uuid, timestamptz, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_real_estate_visit(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_real_estate_visit_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_provider_real_estate_visit_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_real_estate_visit(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_real_estate_visit(uuid, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_real_estate_visit(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_real_estate_visit_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_provider_real_estate_visit_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_real_estate_visit(uuid, text) TO authenticated;
ALTER FUNCTION public.request_real_estate_visit(uuid, timestamptz, text) OWNER TO postgres;
ALTER FUNCTION public.cancel_real_estate_visit(uuid) OWNER TO postgres;
ALTER FUNCTION public.get_my_real_estate_visit_requests() OWNER TO postgres;
ALTER FUNCTION public.get_provider_real_estate_visit_requests() OWNER TO postgres;
ALTER FUNCTION public.respond_real_estate_visit(uuid, text) OWNER TO postgres;
