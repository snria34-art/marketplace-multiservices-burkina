-- Public professional directory: expose only verified active provider identity fields.
GRANT SELECT (id, display_name, active, verification_status)
  ON TABLE public.service_providers TO anon;

DROP POLICY IF EXISTS service_providers_anon_verified_read
  ON public.service_providers;
CREATE POLICY service_providers_anon_verified_read
  ON public.service_providers
  FOR SELECT TO anon
  USING (
    active IS TRUE
    AND verification_status = 'VERIFIED'::public.verification_status
  );

DROP POLICY IF EXISTS professional_public
  ON public.professional_profiles;
DROP POLICY IF EXISTS professional_public_verified
  ON public.professional_profiles;
CREATE POLICY professional_public_verified
  ON public.professional_profiles
  FOR SELECT TO anon, authenticated
  USING (
    active IS TRUE
    AND EXISTS (
      SELECT 1
      FROM public.service_providers AS sp
      WHERE sp.id = professional_profiles.provider_id
        AND sp.active IS TRUE
        AND sp.verification_status = 'VERIFIED'::public.verification_status
    )
  );

-- Reuse the existing service request and quote ledger for the professional vertical.
ALTER TABLE public.service_requests
  ALTER COLUMN service_id DROP NOT NULL;

ALTER TABLE public.service_requests
  ADD COLUMN IF NOT EXISTS professional_profile_id uuid;

ALTER TABLE public.service_requests
  DROP CONSTRAINT IF EXISTS service_requests_professional_profile_id_fkey;
ALTER TABLE public.service_requests
  ADD CONSTRAINT service_requests_professional_profile_id_fkey
  FOREIGN KEY (professional_profile_id)
  REFERENCES public.professional_profiles(id)
  ON DELETE RESTRICT;

ALTER TABLE public.service_requests
  DROP CONSTRAINT IF EXISTS service_requests_exactly_one_target_check;
ALTER TABLE public.service_requests
  ADD CONSTRAINT service_requests_exactly_one_target_check
  CHECK (
    (service_id IS NOT NULL AND professional_profile_id IS NULL)
    OR
    (service_id IS NULL AND professional_profile_id IS NOT NULL)
  );

CREATE INDEX IF NOT EXISTS idx_service_requests_professional_profile_status_created
  ON public.service_requests (professional_profile_id, status, created_at DESC)
  WHERE professional_profile_id IS NOT NULL;

ALTER TABLE public.service_quotes
  ADD COLUMN IF NOT EXISTS message text;

ALTER TABLE public.service_quotes
  DROP CONSTRAINT IF EXISTS service_quotes_message_length_check;
ALTER TABLE public.service_quotes
  ADD CONSTRAINT service_quotes_message_length_check
  CHECK (message IS NULL OR pg_catalog.char_length(message) <= 1000);

CREATE UNIQUE INDEX IF NOT EXISTS service_quotes_one_proposed_per_request_provider
  ON public.service_quotes (request_id, provider_id)
  WHERE status = 'PROPOSED';

CREATE OR REPLACE FUNCTION public.create_professional_service_request(
  p_professional_profile_id uuid,
  p_description text,
  p_scheduled_at timestamptz DEFAULT NULL
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
  v_description text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_professional_profile_id IS NULL THEN
    RAISE EXCEPTION 'professional_profile_required' USING ERRCODE = '22023';
  END IF;

  v_description := NULLIF(pg_catalog.btrim(p_description), '');
  IF v_description IS NULL OR pg_catalog.char_length(v_description) > 2000 THEN
    RAISE EXCEPTION 'description_required_or_too_long' USING ERRCODE = '22023';
  END IF;
  IF p_scheduled_at IS NOT NULL
     AND (
       p_scheduled_at <= pg_catalog.now()
       OR p_scheduled_at > pg_catalog.now() + interval '180 days'
     ) THEN
    RAISE EXCEPTION 'scheduled_time_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT pp.provider_id
    INTO v_provider_id
  FROM public.professional_profiles AS pp
  JOIN public.service_providers AS sp ON sp.id = pp.provider_id
  WHERE pp.id = p_professional_profile_id
    AND pp.active IS TRUE
    AND sp.active IS TRUE
    AND sp.verification_status = 'VERIFIED'::public.verification_status
    AND sp.user_id <> v_uid
  FOR SHARE OF pp, sp;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'professional_unavailable' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.service_requests (
    service_id, professional_profile_id, customer_id,
    status, scheduled_at, description
  )
  VALUES (
    NULL, p_professional_profile_id, v_uid,
    'REQUESTED', p_scheduled_at, v_description
  )
  RETURNING id INTO v_request_id;

  RETURN v_request_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_professional_service_request(p_request_id uuid)
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

  PERFORM 1
  FROM public.service_requests AS r
  WHERE r.id = p_request_id
    AND r.professional_profile_id IS NOT NULL
    AND r.customer_id = v_uid
    AND r.status IN ('REQUESTED', 'QUOTED')
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'request_not_cancellable' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.service_quotes
  SET status = 'EXPIRED'
  WHERE request_id = p_request_id AND status = 'PROPOSED';

  UPDATE public.service_requests
  SET status = 'CANCELLED'
  WHERE id = p_request_id
    AND customer_id = v_uid
    AND status IN ('REQUESTED', 'QUOTED');
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_professional_service_requests()
RETURNS TABLE (
  request_id uuid,
  professional_profile_id uuid,
  profession text,
  provider_name text,
  scheduled_at timestamptz,
  description text,
  status text,
  created_at timestamptz,
  quotes jsonb
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
  SELECT
    r.id, pp.id, pp.profession, sp.display_name,
    r.scheduled_at, r.description, r.status, r.created_at,
    COALESCE(
      (
        SELECT pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', q.id,
            'amount', q.amount,
            'currency', q.currency,
            'status', q.status,
            'message', q.message,
            'created_at', q.created_at
          )
          ORDER BY q.created_at DESC
        )
        FROM public.service_quotes AS q
        WHERE q.request_id = r.id
      ),
      '[]'::jsonb
    )
  FROM public.service_requests AS r
  JOIN public.professional_profiles AS pp ON pp.id = r.professional_profile_id
  JOIN public.service_providers AS sp ON sp.id = pp.provider_id
  WHERE r.customer_id = v_uid
    AND r.professional_profile_id IS NOT NULL
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_provider_professional_service_requests()
RETURNS TABLE (
  request_id uuid,
  professional_profile_id uuid,
  profession text,
  scheduled_at timestamptz,
  description text,
  request_status text,
  created_at timestamptz,
  quote_id uuid,
  quote_amount numeric,
  quote_currency text,
  quote_status text,
  quote_message text
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
  SELECT
    r.id, pp.id, pp.profession, r.scheduled_at, r.description,
    r.status, r.created_at, q.id, q.amount, q.currency, q.status, q.message
  FROM public.service_requests AS r
  JOIN public.professional_profiles AS pp ON pp.id = r.professional_profile_id
  JOIN public.service_providers AS sp ON sp.id = pp.provider_id
  LEFT JOIN LATERAL (
    SELECT sq.id, sq.amount, sq.currency, sq.status, sq.message
    FROM public.service_quotes AS sq
    WHERE sq.request_id = r.id AND sq.provider_id = sp.id
    ORDER BY sq.created_at DESC
    LIMIT 1
  ) AS q ON TRUE
  WHERE sp.user_id = v_uid
    AND r.professional_profile_id IS NOT NULL
  ORDER BY r.created_at DESC
  LIMIT 100;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_professional_service_quote(
  p_request_id uuid,
  p_amount numeric,
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
  v_quote_id uuid;
  v_message text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication_required' USING ERRCODE = '42501';
  END IF;
  IF NOT COALESCE(private.is_active_account(), false) THEN
    RAISE EXCEPTION 'account_not_active' USING ERRCODE = '42501';
  END IF;
  IF p_amount IS NULL OR p_amount < 0 THEN
    RAISE EXCEPTION 'quote_amount_invalid' USING ERRCODE = '22023';
  END IF;
  IF p_message IS NOT NULL AND pg_catalog.char_length(p_message) > 1000 THEN
    RAISE EXCEPTION 'quote_message_too_long' USING ERRCODE = '22023';
  END IF;
  v_message := NULLIF(pg_catalog.btrim(p_message), '');

  SELECT pp.provider_id
    INTO v_provider_id
  FROM public.service_requests AS r
  JOIN public.professional_profiles AS pp ON pp.id = r.professional_profile_id
  JOIN public.service_providers AS sp ON sp.id = pp.provider_id
  WHERE r.id = p_request_id
    AND r.status = 'REQUESTED'
    AND pp.active IS TRUE
    AND sp.active IS TRUE
    AND sp.verification_status = 'VERIFIED'::public.verification_status
    AND sp.user_id = v_uid
  FOR UPDATE OF r, pp, sp;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'professional_request_not_found_or_not_owned' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.service_quotes (
    request_id, provider_id, amount, currency, status, message
  )
  VALUES (
    p_request_id, v_provider_id, p_amount, 'XOF', 'PROPOSED', v_message
  )
  RETURNING id INTO v_quote_id;

  UPDATE public.service_requests
  SET status = 'QUOTED'
  WHERE id = p_request_id AND status = 'REQUESTED';

  RETURN v_quote_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'quote_already_pending' USING ERRCODE = '23505';
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_professional_service_quote(
  p_quote_id uuid,
  p_decision text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_request_id uuid;
  v_request_status text;
  v_quote_status text;
  v_decision text;
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
  IF v_decision IS NULL OR v_decision NOT IN ('ACCEPT', 'REJECT') THEN
    RAISE EXCEPTION 'decision_invalid' USING ERRCODE = '22023';
  END IF;

  SELECT q.request_id, r.status, q.status, sp.active, sp.verification_status
    INTO v_request_id, v_request_status, v_quote_status,
         v_provider_active, v_provider_verification
  FROM public.service_quotes AS q
  JOIN public.service_requests AS r ON r.id = q.request_id
  JOIN public.professional_profiles AS pp ON pp.id = r.professional_profile_id
  JOIN public.service_providers AS sp ON sp.id = pp.provider_id
  WHERE q.id = p_quote_id
    AND r.customer_id = v_uid
    AND r.professional_profile_id IS NOT NULL
  FOR UPDATE OF q, r, pp, sp;

  IF NOT FOUND OR v_quote_status <> 'PROPOSED' OR v_request_status <> 'QUOTED' THEN
    RAISE EXCEPTION 'quote_not_available_to_customer' USING ERRCODE = 'P0002';
  END IF;

  IF v_decision = 'ACCEPT'
     AND (
       v_provider_active IS NOT TRUE
       OR v_provider_verification <> 'VERIFIED'::public.verification_status
     ) THEN
    RAISE EXCEPTION 'professional_unavailable' USING ERRCODE = '42501';
  END IF;

  IF v_decision = 'ACCEPT' THEN
    UPDATE public.service_quotes
    SET status = 'ACCEPTED'
    WHERE id = p_quote_id AND status = 'PROPOSED';

    UPDATE public.service_quotes
    SET status = 'EXPIRED'
    WHERE request_id = v_request_id
      AND id <> p_quote_id
      AND status = 'PROPOSED';

    UPDATE public.service_requests
    SET status = 'ACCEPTED'
    WHERE id = v_request_id AND status = 'QUOTED';
  ELSE
    UPDATE public.service_quotes
    SET status = 'REJECTED'
    WHERE id = p_quote_id AND status = 'PROPOSED';

    UPDATE public.service_requests
    SET status = 'REQUESTED'
    WHERE id = v_request_id AND status = 'QUOTED';
  END IF;
END;
$function$;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.service_requests FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
  ON TABLE public.service_quotes FROM anon, authenticated;

REVOKE ALL ON FUNCTION public.create_professional_service_request(uuid, text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cancel_professional_service_request(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_my_professional_service_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_provider_professional_service_requests() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_professional_service_quote(uuid, numeric, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.respond_professional_service_quote(uuid, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_professional_service_request(uuid, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_professional_service_request(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_professional_service_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_provider_professional_service_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_professional_service_quote(uuid, numeric, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_professional_service_quote(uuid, text) TO authenticated;

ALTER FUNCTION public.create_professional_service_request(uuid, text, timestamptz) OWNER TO postgres;
ALTER FUNCTION public.cancel_professional_service_request(uuid) OWNER TO postgres;
ALTER FUNCTION public.get_my_professional_service_requests() OWNER TO postgres;
ALTER FUNCTION public.get_provider_professional_service_requests() OWNER TO postgres;
ALTER FUNCTION public.create_professional_service_quote(uuid, numeric, text) OWNER TO postgres;
ALTER FUNCTION public.respond_professional_service_quote(uuid, text) OWNER TO postgres;
