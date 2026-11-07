CREATE OR REPLACE FUNCTION private.get_public_health_products_internal()
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  price numeric,
  requires_prescription boolean,
  available_quantity integer,
  provider_name text,
  provider_type text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    hpdt.id,
    hpdt.name,
    hpdt.description,
    hpdt.price,
    hpdt.requires_prescription,
    GREATEST(hpdt.stock_quantity - hpdt.reserved_quantity, 0),
    sp.display_name,
    hp.provider_type
  FROM public.health_products AS hpdt
  JOIN public.health_providers AS hp ON hp.id = hpdt.health_provider_id
  JOIN public.service_providers AS sp ON sp.id = hp.provider_id
  WHERE hpdt.active IS TRUE
    AND hp.provider_type = 'PHARMACY'
    AND private.is_verified_active_health_provider(hp.id, 'PHARMACY')
  ORDER BY hpdt.name
  LIMIT 100;
$function$;

ALTER FUNCTION private.get_public_health_products_internal() OWNER TO postgres;
REVOKE ALL ON FUNCTION private.get_public_health_products_internal() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION private.get_public_health_products_internal() TO anon, authenticated;
