-- Protect the unqualified public.payment_status variable type from pg_temp shadowing.
alter function public.process_payment_provider_event(uuid, text, text, jsonb)
  set search_path = 'pg_catalog, public, pg_temp';
