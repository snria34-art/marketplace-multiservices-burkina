begin;
select plan(10);

select ok(
  not has_table_privilege('anon','public.creative_bookings','INSERT')
  and not has_table_privilege('anon','public.creative_bookings','UPDATE')
  and not has_table_privilege('anon','public.creative_bookings','DELETE')
  and not has_table_privilege('authenticated','public.creative_bookings','INSERT')
  and not has_table_privilege('authenticated','public.creative_bookings','UPDATE')
  and not has_table_privilege('authenticated','public.creative_bookings','DELETE'),
  'API client roles cannot directly insert, update, or delete creative bookings'
);

select ok(
  has_table_privilege('authenticated','public.creative_bookings','SELECT')
  and not has_table_privilege('anon','public.creative_bookings','SELECT'),
  'only authenticated customers receive direct read privilege on creative bookings'
);

select ok(
  exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='creative_bookings'
      and policyname='active_account_guard'
      and permissive='RESTRICTIVE'
      and cmd='ALL'
  )
  and exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='creative_bookings'
      and policyname='creative_bookings_customer_read'
      and permissive='PERMISSIVE'
      and cmd='SELECT'
      and roles @> array['authenticated']::name[]
  )
  and not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='creative_bookings'
      and policyname='creative_bookings_own'
  ),
  'customer read is row-scoped and active-account guard remains restrictive'
);

select ok(
  to_regprocedure('public.request_creative_booking(uuid,timestamp with time zone)') is not null
  and to_regprocedure('public.cancel_creative_booking(uuid)') is not null
  and to_regprocedure('public.get_provider_creative_bookings()') is not null
  and to_regprocedure('public.respond_creative_booking(uuid,text,numeric)') is not null,
  'all four creative booking RPCs exist'
);

select ok(
  (
    select count(*) = 4
    from pg_proc p
    where p.oid = any(array[
      'public.request_creative_booking(uuid,timestamp with time zone)'::regprocedure,
      'public.cancel_creative_booking(uuid)'::regprocedure,
      'public.get_provider_creative_bookings()'::regprocedure,
      'public.respond_creative_booking(uuid,text,numeric)'::regprocedure
    ]::regprocedure[])
      and p.prosecdef
      and pg_get_userbyid(p.proowner)='postgres'
      and p.proconfig @> array['search_path=""']::text[]
      and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and not has_function_privilege('anon',p.oid,'EXECUTE')
  ),
  'creative booking RPCs are postgres-owned SECURITY DEFINER functions with empty search_path and authenticated-only execution'
);

select ok(
  position('private.require_active_account()' in pg_get_functiondef('public.request_creative_booking(uuid,timestamp with time zone)'::regprocedure)) > 0
  and position('cs.active = true' in pg_get_functiondef('public.request_creative_booking(uuid,timestamp with time zone)'::regprocedure)) > 0
  and position('sp.active = true' in pg_get_functiondef('public.request_creative_booking(uuid,timestamp with time zone)'::regprocedure)) > 0
  and position('sp.verification_status' in pg_get_functiondef('public.request_creative_booking(uuid,timestamp with time zone)'::regprocedure)) > 0
  and position('''REQUESTED''' in pg_get_functiondef('public.request_creative_booking(uuid,timestamp with time zone)'::regprocedure)) > 0,
  'booking request requires an active account, active service and verified active provider'
);

select ok(
  position('cb.customer_id = v_user' in pg_get_functiondef('public.cancel_creative_booking(uuid)'::regprocedure)) > 0
  and position('cb.status = ''REQUESTED''' in pg_get_functiondef('public.cancel_creative_booking(uuid)'::regprocedure)) > 0
  and position('status = ''CANCELLED''' in pg_get_functiondef('public.cancel_creative_booking(uuid)'::regprocedure)) > 0,
  'customer cancellation is limited to their own pending request'
);

select ok(
  position('sp.user_id = v_user' in pg_get_functiondef('public.get_provider_creative_bookings()'::regprocedure)) > 0
  and position('private.require_active_account()' in pg_get_functiondef('public.get_provider_creative_bookings()'::regprocedure)) > 0,
  'provider booking list is scoped to services owned by the active caller'
);

select ok(
  position('sp.user_id = v_user' in pg_get_functiondef('public.respond_creative_booking(uuid,text,numeric)'::regprocedure)) > 0
  and position('cb.status = ''REQUESTED''' in pg_get_functiondef('public.respond_creative_booking(uuid,text,numeric)'::regprocedure)) > 0
  and position('p_agreed_amount' in pg_get_functiondef('public.respond_creative_booking(uuid,text,numeric)'::regprocedure)) > 0
  and position('sp.verification_status' in pg_get_functiondef('public.respond_creative_booking(uuid,text,numeric)'::regprocedure)) > 0,
  'provider response requires ownership, pending status and a valid agreed amount for confirmation'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='creative_bookings'
      and permissive='PERMISSIVE'
      and cmd in ('INSERT','UPDATE','DELETE','ALL')
  ),
  'no permissive client write policy remains on creative bookings'
);

select * from finish();
rollback;
