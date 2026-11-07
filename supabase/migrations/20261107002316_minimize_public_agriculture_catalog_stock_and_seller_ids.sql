DROP FUNCTION public.get_public_agriculture_listings();

CREATE FUNCTION public.get_public_agriculture_listings()
RETURNS TABLE (
  id uuid,
  seller_name text,
  listing_type text,
  name text,
  description text,
  price numeric,
  unit text,
  available_quantity numeric,
  active boolean,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $function$
  SELECT
    l.id,
    s.business_name,
    l.listing_type,
    l.name,
    l.description,
    l.price,
    l.unit,
    CASE
      WHEN l.quantity IS NULL THEN NULL
      ELSE GREATEST(l.quantity - l.reserved_quantity, 0)
    END,
    l.active,
    l.created_at
  FROM public.agriculture_listings AS l
  JOIN public.sellers AS s ON s.id = l.seller_id
  WHERE l.active IS TRUE
    AND private.is_verified_active_seller(s.id)
  ORDER BY l.created_at DESC
  LIMIT 100;
$function$;

ALTER FUNCTION public.get_public_agriculture_listings() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_public_agriculture_listings() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_agriculture_listings() TO anon, authenticated;
