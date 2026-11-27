CREATE OR REPLACE FUNCTION private.get_customer_order_delivery_assignments(
  p_order_id uuid
)
RETURNS TABLE (
  package_id uuid,
  order_group_id uuid,
  shop_id uuid,
  shop_name text,
  package_status text,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  package_updated_at timestamptz,
  assignment_id uuid,
  assignment_status text,
  assigned_at timestamptz,
  accepted_at timestamptz,
  assignment_completed_at timestamptz,
  courier_id uuid,
  courier_latitude double precision,
  courier_longitude double precision,
  courier_accuracy_m numeric,
  courier_recorded_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := (SELECT auth.uid());
BEGIN
  PERFORM private.require_active_account();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING errcode = '42501';
  END IF;

  IF p_order_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = p_order_id
      AND o.customer_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'order_not_found_or_not_owned' USING errcode = '42501';
  END IF;

  RETURN QUERY
  SELECT
    op.id,
    og.id,
    og.shop_id,
    sh.name,
    op.status::text,
    op.picked_up_at,
    op.delivered_at,
    op.updated_at,
    da.id,
    da.status::text,
    da.assigned_at,
    da.accepted_at,
    da.completed_at,
    CASE
      WHEN da.status::text IN ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
       AND op.status::text IN ('READY_FOR_PICKUP', 'PICKED_UP', 'IN_TRANSIT')
      THEN da.courier_id
      ELSE NULL
    END,
    loc.latitude,
    loc.longitude,
    loc.accuracy_m,
    loc.recorded_at
  FROM public.orders o
  JOIN public.order_groups og
    ON og.order_id = o.id
  JOIN public.order_packages op
    ON op.order_group_id = og.id
  LEFT JOIN public.shops sh
    ON sh.id = og.shop_id
  LEFT JOIN LATERAL (
    SELECT da0.*
    FROM public.delivery_assignments da0
    WHERE da0.package_id = op.id
    ORDER BY
      CASE
        WHEN da0.status::text IN ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
        THEN 0
        ELSE 1
      END,
      da0.assigned_at DESC NULLS LAST,
      da0.id DESC
    LIMIT 1
  ) da ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      public.st_y(cl.location::public.geometry)::double precision AS latitude,
      public.st_x(cl.location::public.geometry)::double precision AS longitude,
      cl.accuracy_m,
      cl.recorded_at
    FROM public.courier_locations cl
    WHERE cl.courier_id = da.courier_id
      AND da.status::text IN ('ASSIGNED', 'ACCEPTED', 'PICKED_UP', 'IN_TRANSIT')
      AND op.status::text IN ('READY_FOR_PICKUP', 'PICKED_UP', 'IN_TRANSIT')
      AND og.status::text <> 'CANCELLED'
      AND o.status::text NOT IN ('CANCELLED', 'REFUNDED')
    ORDER BY cl.recorded_at DESC, cl.id DESC
    LIMIT 1
  ) loc ON TRUE
  WHERE o.id = p_order_id
    AND o.customer_id = v_user_id
  ORDER BY op.created_at, op.id;
END;
$function$;

REVOKE ALL ON FUNCTION private.get_customer_order_delivery_assignments(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.get_customer_order_delivery_assignments(uuid)
  TO authenticated;

COMMENT ON FUNCTION private.get_customer_order_delivery_assignments(uuid) IS
  'Returns delivery assignment and only the latest active courier location for an order owned by the authenticated customer.';

CREATE OR REPLACE FUNCTION public.get_customer_order_delivery_assignments(
  p_order_id uuid
)
RETURNS TABLE (
  package_id uuid,
  order_group_id uuid,
  shop_id uuid,
  shop_name text,
  package_status text,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  package_updated_at timestamptz,
  assignment_id uuid,
  assignment_status text,
  assigned_at timestamptz,
  accepted_at timestamptz,
  assignment_completed_at timestamptz,
  courier_id uuid,
  courier_latitude double precision,
  courier_longitude double precision,
  courier_accuracy_m numeric,
  courier_recorded_at timestamptz
)
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT *
  FROM private.get_customer_order_delivery_assignments(p_order_id);
$function$;

REVOKE ALL ON FUNCTION public.get_customer_order_delivery_assignments(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_customer_order_delivery_assignments(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_customer_order_delivery_assignments(uuid) IS
  'Customer-scoped delivery tracking RPC; ownership and courier-location visibility are enforced by a private helper.';
