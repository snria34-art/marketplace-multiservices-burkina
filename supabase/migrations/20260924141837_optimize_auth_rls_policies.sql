ALTER POLICY "accommodation_bookings_customer_read" ON public.accommodation_bookings USING (customer_id = (select auth.uid()));
ALTER POLICY "beauty_bookings_customer_read" ON public.beauty_bookings USING (customer_id = (select auth.uid()));
ALTER POLICY "courier_locations_read" ON public.courier_locations USING ((courier_id = (select auth.uid())) OR ((id = ( SELECT cl.id
   FROM courier_locations cl
  ORDER BY cl.recorded_at DESC, cl.id DESC
 LIMIT 1)) AND (EXISTS ( SELECT 1
   FROM (((delivery_assignments da
     JOIN order_packages op ON ((op.id = da.package_id)))
     JOIN order_groups og ON ((og.id = op.order_group_id)))
     JOIN orders o ON ((o.id = og.order_id)))
  WHERE ((da.courier_id = courier_locations.courier_id) AND (o.customer_id = (select auth.uid())) AND (op.delivered_at IS NULL))))));
ALTER POLICY "digital_orders_customer_read" ON public.digital_orders USING (customer_id = (select auth.uid()));
ALTER POLICY "dispute_evidence_participant" ON public.dispute_evidence USING ((submitted_by = (select auth.uid())) AND ((EXISTS ( SELECT 1
   FROM disputes d
  WHERE ((d.id = dispute_evidence.dispute_id) AND ((d.opened_by = (select auth.uid())) OR (d.against_user_id = (select auth.uid())))))) OR private.is_admin())) WITH CHECK ((submitted_by = (select auth.uid())) AND ((EXISTS ( SELECT 1
   FROM disputes d
  WHERE ((d.id = dispute_evidence.dispute_id) AND ((d.opened_by = (select auth.uid())) OR (d.against_user_id = (select auth.uid())))))) OR private.is_admin()));
ALTER POLICY "event_bookings_customer_cancel_reserved" ON public.event_bookings USING ((customer_id = (select auth.uid())) AND (status = 'RESERVED'::text));
ALTER POLICY "event_bookings_customer_read" ON public.event_bookings USING (customer_id = (select auth.uid()));
ALTER POLICY "group_buy_members_customer_read" ON public.group_buy_members USING (user_id = (select auth.uid()));
ALTER POLICY "home_service_requests_customer_read" ON public.home_service_requests USING (customer_id = (select auth.uid()));
ALTER POLICY "job_applications_applicant_read" ON public.job_applications USING (applicant_id = (select auth.uid()));
ALTER POLICY "mechanic_review_customer_manage" ON public.mechanic_reviews USING (((customer_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM (mechanic_requests mr
     JOIN mechanic_interventions mi ON ((mi.request_id = mr.id)))
  WHERE ((mr.id = mechanic_reviews.request_id) AND (mr.customer_id = (select auth.uid())) AND (mi.mechanic_id = mechanic_reviews.mechanic_id) AND (mi.completed_at IS NOT NULL))))) OR private.is_admin()) WITH CHECK (((customer_id = (select auth.uid())) AND (EXISTS ( SELECT 1
   FROM (mechanic_requests mr
     JOIN mechanic_interventions mi ON ((mi.request_id = mr.id)))
  WHERE ((mr.id = mechanic_reviews.request_id) AND (mr.customer_id = (select auth.uid())) AND (mi.mechanic_id = mechanic_reviews.mechanic_id) AND (mi.completed_at IS NOT NULL))))) OR private.is_admin());
ALTER POLICY "products_read" ON public.products USING (((status = 'ACTIVE'::product_status) AND ((NOT is_expirable) OR (expiry_date IS NULL) OR (expiry_date >= CURRENT_DATE)) AND (EXISTS ( SELECT 1
   FROM shops s
  WHERE ((s.id = products.shop_id) AND (s.status = 'ACTIVE'::shop_status) AND (s.verification_status = 'VERIFIED'::verification_status))))) OR (shop_id IN ( SELECT s.id
   FROM (shops s
     JOIN sellers se ON ((se.id = s.seller_id)))
  WHERE (se.user_id = (select auth.uid())))));
ALTER POLICY "ride_requests_customer_read" ON public.ride_requests USING (customer_id = (select auth.uid()));
ALTER POLICY "training_enrollments_customer_read" ON public.training_enrollments USING (customer_id = (select auth.uid()));
ALTER POLICY "vehicle_rental_bookings_customer_read" ON public.vehicle_rental_bookings USING (customer_id = (select auth.uid()));
