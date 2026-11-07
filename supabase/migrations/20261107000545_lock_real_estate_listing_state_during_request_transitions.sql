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
    AND sp.user_id <> v_uid
  FOR SHARE OF l, sp;

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
  FOR UPDATE OF r, l, sp;

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