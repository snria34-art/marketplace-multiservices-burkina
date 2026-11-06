-- Harden application SECURITY DEFINER function search paths.
-- Keep trusted schemas explicit and pg_temp last to prevent temporary-object shadowing.
-- Function bodies, owners, privileges and business behavior are unchanged.

alter function public.admin_add_associate_after_payment(uuid, uuid, uuid, numeric, numeric, text)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.apply_to_job(uuid)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_accommodation_booking(uuid, date, date, integer)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_beauty_booking(uuid, timestamp with time zone)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_digital_order(uuid)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_freight_request(jsonb, jsonb, numeric, numeric, text)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_home_service_request(uuid, timestamp with time zone, jsonb)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_parcel_request(text, text, jsonb, jsonb, numeric)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_ride_request(jsonb, jsonb)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.create_vehicle_rental_booking(uuid, timestamp with time zone, timestamp with time zone)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.enroll_training_course(uuid)
  set search_path = 'pg_catalog, public, private, pg_temp';

alter function public.handle_new_user()
  set search_path = 'pg_catalog, public, pg_temp';

alter function public.reserve_event_ticket(uuid, integer)
  set search_path = 'pg_catalog, public, private, pg_temp';
