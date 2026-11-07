CREATE OR REPLACE FUNCTION private.can_read_health_prescription(p_object_name text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    auth.uid() IS NOT NULL
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
            AND r.status IN (
              'PENDING_REVIEW',
              'APPROVED_FOR_DISPENSING',
              'DISPENSED'
            )
            AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
          )
        )
    );
$function$;

ALTER FUNCTION private.can_read_health_prescription(text) OWNER TO postgres;
REVOKE ALL ON FUNCTION private.can_read_health_prescription(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.can_read_health_prescription(text) TO authenticated;
