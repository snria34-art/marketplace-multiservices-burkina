-- Prevent an authenticated seller from reassigning an inventory row
-- to a product owned by another seller during UPDATE.
ALTER POLICY inventory_owner_update
ON public.inventory
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.products p
    JOIN public.shops sh ON sh.id = p.shop_id
    JOIN public.sellers s ON s.id = sh.seller_id
    WHERE p.id = inventory.product_id
      AND s.user_id = (SELECT auth.uid())
  )
);
