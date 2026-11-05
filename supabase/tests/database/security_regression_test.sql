begin;
select plan(26);

select ok(
  not has_table_privilege('anon','private.catalog_moderation_findings','SELECT')
  and not has_table_privilege('authenticated','private.catalog_moderation_findings','SELECT'),
  'catalog moderation findings are not directly readable by API client roles'
);

select ok(
  not has_table_privilege('anon','private.platform_agent_runs','SELECT')
  and not has_table_privilege('authenticated','private.platform_agent_runs','SELECT'),
  'platform agent run logs are not directly readable by API client roles'
);

select ok(
  not has_table_privilege('anon','private.seller_access_requests','SELECT')
  and not has_table_privilege('authenticated','private.seller_access_requests','SELECT'),
  'seller access requests are not directly readable by API client roles'
);

select ok(
  not has_table_privilege('anon','public.delivery_evidence','SELECT')
  and not has_table_privilege('authenticated','public.delivery_evidence','SELECT'),
  'delivery evidence is not directly readable by API client roles'
);

select ok(
  not has_function_privilege('anon','private.notify_mechanic_request()','EXECUTE')
  and not has_function_privilege('authenticated','private.notify_mechanic_request()','EXECUTE'),
  'mechanic notification trigger cannot be called directly by clients'
);

select ok(
  not has_function_privilege('anon','private.trigger_push_notification()','EXECUTE')
  and not has_function_privilege('authenticated','private.trigger_push_notification()','EXECUTE'),
  'push notification trigger cannot be called directly by clients'
);

select ok(
  not has_function_privilege('anon','public.claim_notification_for_push(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.claim_notification_for_push(uuid)','EXECUTE'),
  'push queue claim is not executable by client roles'
);

select ok(
  has_function_privilege('service_role','public.claim_notification_for_push(uuid)','EXECUTE'),
  'push queue claim is executable by the trusted service role'
);

select ok(
  not has_function_privilege('anon','public.admin_send_test_notification(text,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_send_test_notification(text,text)','EXECUTE'),
  'admin push test RPC is signed-in only and enforces admin authorization internally'
);

select ok(
  not has_function_privilege('anon','public.deactivate_notification_device(text)','EXECUTE')
  and has_function_privilege('authenticated','public.deactivate_notification_device(text)','EXECUTE'),
  'device deactivation RPC is signed-in only'
);

select ok(
  not has_function_privilege('anon','public.register_notification_device(text,text)','EXECUTE')
  and has_function_privilege('authenticated','public.register_notification_device(text,text)','EXECUTE'),
  'device registration RPC is signed-in only'
);

select ok(
  not has_function_privilege('anon','public.verify_push_dispatch_secret(text)','EXECUTE')
  and not has_function_privilege('authenticated','public.verify_push_dispatch_secret(text)','EXECUTE')
  and has_function_privilege('service_role','public.verify_push_dispatch_secret(text)','EXECUTE'),
  'push dispatch secret verification is service-role only'
);


select ok(
  has_function_privilege('authenticated','public.checkout_cart(uuid,jsonb,numeric,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.checkout_cart(uuid,jsonb,numeric,text,text)','EXECUTE'),
  'checkout is available to signed-in customers but not anonymous clients'
);

select ok(
  has_function_privilege('authenticated','public.create_transport_booking_secure(uuid,integer,jsonb)','EXECUTE')
  and not has_function_privilege('anon','public.create_transport_booking_secure(uuid,integer,jsonb)','EXECUTE'),
  'transport booking is signed-in only'
);

select ok(
  has_function_privilege('authenticated','public.accept_mechanic_quote(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.accept_mechanic_quote(uuid)','EXECUTE'),
  'mechanic quote acceptance is signed-in only'
);

select ok(
  has_function_privilege('authenticated','public.set_cart_item_quantity(uuid,integer)','EXECUTE')
  and not has_function_privilege('anon','public.set_cart_item_quantity(uuid,integer)','EXECUTE'),
  'cart quantity mutation is signed-in only'
);

select ok(
  has_function_privilege('authenticated','private.has_active_seller_access(uuid,text)','EXECUTE')
  and not has_function_privilege('anon','private.has_active_seller_access(uuid,text)','EXECUTE'),
  'seller shared-access helper is available only to authenticated policy evaluation'
);

select ok(
  not has_function_privilege('anon','public.create_order_message(uuid,text,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.create_order_message(uuid,text,text)','EXECUTE')
  and has_function_privilege('service_role','public.create_order_message(uuid,text,text)','EXECUTE'),
  'server-only order messaging RPC cannot be called directly by clients'
);

select ok(
  position('financial_read' in pg_get_functiondef('public.submit_seller_access_request(uuid,uuid,text[],text,text)'::regprocedure)) = 0,
  'seller access request RPC no longer accepts financial_read'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname='public'
      and policyname in (
        'commissions_shared_access_read',
        'seller_ledger_shared_access_read',
        'seller_payouts_shared_access_read'
      )
  ),
  'shared financial read policies are absent'
);

select ok(
  exists (select 1 from pg_policies where schemaname='public' and tablename='commissions' and policyname='commissions_seller_read')
  and exists (select 1 from pg_policies where schemaname='public' and tablename='seller_ledger' and policyname='seller_ledger_seller_read')
  and exists (select 1 from pg_policies where schemaname='public' and tablename='seller_payouts' and policyname='seller_payouts_owner_or_admin_read'),
  'seller owners and administrators retain their financial read policies'
);


select ok(
  not has_function_privilege('anon','public.complete_refund(uuid,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.complete_refund(uuid,text)','EXECUTE')
  and has_function_privilege('service_role','public.complete_refund(uuid,text)','EXECUTE'),
  'refund completion is restricted to the trusted service role'
);

select ok(
  not has_function_privilege('anon','public.process_payment_event(uuid,text,payment_status,text,numeric,jsonb)','EXECUTE')
  and not has_function_privilege('authenticated','public.process_payment_event(uuid,text,payment_status,text,numeric,jsonb)','EXECUTE')
  and has_function_privilege('service_role','public.process_payment_event(uuid,text,payment_status,text,numeric,jsonb)','EXECUTE'),
  'payment event processing is restricted to the trusted service role'
);

select ok(
  not has_function_privilege('anon','public.admin_mark_seller_payout_paid(uuid,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_mark_seller_payout_paid(uuid,text)','EXECUTE')
  and not has_function_privilege('anon','public.admin_mark_seller_payout_failed(uuid,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_mark_seller_payout_failed(uuid,text)','EXECUTE'),
  'seller payout admin RPCs require authentication and perform internal admin checks'
);

select ok(
  not has_function_privilege('anon','public.admin_begin_refund(uuid)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_begin_refund(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.admin_complete_manual_refund(uuid,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_complete_manual_refund(uuid,text)','EXECUTE'),
  'refund administration RPCs require authentication and perform internal admin checks'
);

select ok(
  has_function_privilege('authenticated','public.request_seller_payout_secure(uuid,numeric,text)','EXECUTE')
  and not has_function_privilege('anon','public.request_seller_payout_secure(uuid,numeric,text)','EXECUTE'),
  'seller payout requests are signed-in only'
);

select ok(
  not (select public from storage.buckets where id='documents')
  and not has_function_privilege('anon','public.complete_refund(uuid,text)','EXECUTE'),
  'seller documents bucket remains private'
);

select * from finish();
rollback;
