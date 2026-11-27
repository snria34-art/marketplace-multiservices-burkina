CREATE OR REPLACE FUNCTION private.confirm_customer_order_received(
  p_order_id uuid
)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_user_id uuid := (SELECT auth.uid());
  v_order public.orders%ROWTYPE;
  v_confirmed_at timestamptz;
BEGIN
  PERFORM private.require_active_account();

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING errcode = '42501';
  END IF;

  SELECT *
  INTO v_order
  FROM public.orders
  WHERE id = p_order_id
    AND customer_id = v_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_not_found_or_not_owned' USING errcode = '42501';
  END IF;

  IF v_order.status <> 'DELIVERED' THEN
    RAISE EXCEPTION 'order_not_delivered';
  END IF;

  IF v_order.review_deadline_at IS NULL
     OR now() > v_order.review_deadline_at THEN
    RAISE EXCEPTION 'receipt_confirmation_window_expired';
  END IF;

  -- Idempotent: a repeated tap returns the existing confirmation timestamp.
  IF v_order.completed_at IS NOT NULL THEN
    RETURN v_order.completed_at;
  END IF;

  v_confirmed_at := now();

  UPDATE public.orders
  SET completed_at = v_confirmed_at,
      updated_at = v_confirmed_at
  WHERE id = p_order_id
    AND customer_id = v_user_id
    AND completed_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order_receipt_confirmation_conflict';
  END IF;

  INSERT INTO public.order_events(order_id, actor_id, status, metadata)
  VALUES (
    p_order_id,
    v_user_id,
    'DELIVERED',
    jsonb_build_object(
      'source', 'customer_app',
      'action', 'CUSTOMER_CONFIRMED_RECEIPT',
      'confirmed_at', v_confirmed_at
    )
  );

  RETURN v_confirmed_at;
END;
$function$;

REVOKE ALL ON FUNCTION private.confirm_customer_order_received(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.confirm_customer_order_received(uuid)
  TO authenticated;

COMMENT ON FUNCTION private.confirm_customer_order_received(uuid) IS
  'Allows only the owning active customer to confirm receipt of a delivered order during the existing review window. The review deadline is never extended.';

CREATE OR REPLACE FUNCTION public.confirm_customer_order_received(
  p_order_id uuid
)
RETURNS timestamptz
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $function$
  SELECT private.confirm_customer_order_received(p_order_id);
$function$;

REVOKE ALL ON FUNCTION public.confirm_customer_order_received(uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_customer_order_received(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.confirm_customer_order_received(uuid) IS
  'Authenticated customer RPC for confirming receipt of their own delivered order.';

-- A customer must acknowledge receipt before submitting a product review.
-- The original seven-day deadline still governs the review window.
CREATE OR REPLACE FUNCTION private.create_review(
  p_product_id uuid,
  p_shop_id uuid,
  p_rating integer,
  p_body text DEFAULT NULL,
  p_issue_codes text[] DEFAULT '{}'::text[]
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'pg_catalog', 'public'
AS $function$
DECLARE
  v_user uuid := (SELECT auth.uid());
  v_review uuid;
  v_issue_codes text[] := coalesce(p_issue_codes, '{}'::text[]);
BEGIN
  PERFORM private.require_active_account();

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'invalid_rating';
  END IF;

  IF length(coalesce(p_body, '')) > 2000 THEN
    RAISE EXCEPTION 'review_too_long';
  END IF;

  IF cardinality(v_issue_codes) > 5
     OR NOT (
       v_issue_codes <@ ARRAY[
         'NOT_AS_DESCRIBED',
         'DAMAGED',
         'WRONG_ITEM',
         'MISSING_PARTS',
         'QUALITY_ISSUE',
         'PACKAGING_ISSUE',
         'OTHER'
       ]::text[]
     ) THEN
    RAISE EXCEPTION 'invalid_review_issue_codes';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.order_items oi
    JOIN public.order_groups og ON og.id = oi.order_group_id
    JOIN public.orders o ON o.id = og.order_id
    JOIN public.order_packages op ON op.order_group_id = og.id
    WHERE o.customer_id = v_user
      AND o.completed_at IS NOT NULL
      AND o.review_deadline_at IS NOT NULL
      AND now() <= o.review_deadline_at
      AND op.status::text = 'DELIVERED'
      AND op.delivered_at IS NOT NULL
      AND op.delivered_at >= now() - interval '7 days'
      AND oi.product_id = p_product_id
      AND og.shop_id = p_shop_id
  ) THEN
    RAISE EXCEPTION 'receipt_not_confirmed_or_review_window_expired';
  END IF;

  INSERT INTO public.reviews(
    customer_id, product_id, shop_id, rating, body, status, issue_codes
  )
  VALUES (
    v_user,
    p_product_id,
    p_shop_id,
    p_rating,
    nullif(trim(p_body), ''),
    'PENDING',
    v_issue_codes
  )
  RETURNING id INTO v_review;

  RETURN v_review;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'review_already_exists';
END;
$function$;

COMMENT ON FUNCTION private.create_review(uuid, uuid, integer, text, text[]) IS
  'Creates a verified-purchase review only after customer receipt confirmation and within the seven-day review window.';
