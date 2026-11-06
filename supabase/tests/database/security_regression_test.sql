begin;
select plan(45);

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
  and not exists (
    select 1 from pg_policies
    where schemaname='storage' and tablename='objects'
      and cmd='SELECT' and roles::text in ('{anon}','{public}','{anon,authenticated}')
      and qual like '%documents%'
  ),
  'seller documents bucket remains private'
);


select ok(
  position('private.is_admin()' in pg_get_functiondef('public.admin_mark_seller_payout_paid(uuid,text)'::regprocedure)) > 0
  and position('public.is_admin_actor()' in pg_get_functiondef('public.admin_mark_seller_payout_paid(uuid,text)'::regprocedure)) = 0
  and position('private.is_admin()' in pg_get_functiondef('public.admin_mark_seller_payout_failed(uuid,text)'::regprocedure)) > 0
  and position('public.is_admin_actor()' in pg_get_functiondef('public.admin_mark_seller_payout_failed(uuid,text)'::regprocedure)) = 0
  and position('private.is_admin()' in pg_get_functiondef('public.admin_set_account_status(uuid,public.account_status,text)'::regprocedure)) > 0
  and position('public.is_admin_actor()' in pg_get_functiondef('public.admin_set_account_status(uuid,public.account_status,text)'::regprocedure)) = 0,
  'payout and account suspension mutations require an active explicitly registered admin'
);

select ok(
  position('private.is_admin()' in pg_get_functiondef('public.admin_review_seller_access_request(uuid,boolean,text,integer)'::regprocedure)) > 0
  and position('private.is_admin()' in pg_get_functiondef('public.admin_review_seller_access_request_v2(uuid,boolean,text,text)'::regprocedure)) > 0
  and position('private.is_admin()' in pg_get_functiondef('public.revoke_seller_access_request(uuid,text)'::regprocedure)) > 0
  and position('case when private.is_admin() then r.admin_confirmation_notes else null end' in pg_get_functiondef('public.get_seller_access_requests()')) > 0,
  'seller access approvals and internal admin notes require an active explicitly registered admin'
);

select ok(
  position('da.package_id=p_package_id' in replace(pg_get_functiondef('public.confirm_package_delivery(uuid,text)'::regprocedure),' ','')) > 0,
  'delivery evidence assignment must belong to the exact package being confirmed'
);

select ok(
  position('private.require_active_account()' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('private.is_admin()' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('release_variant_inventory' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('CANCELLED_BY_SELLER' in pg_get_functiondef('public.transition_order_group_status(uuid,public.order_status,text)'::regprocedure)) > 0,
  'seller group cancellation requires an active owner/admin, releases reserved stock, and records courier assignment cancellation'
);

select ok(
  not has_function_privilege('anon','public.transition_order_group_status(uuid,public.order_status,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.transition_order_group_status(uuid,public.order_status,text)','EXECUTE')
  and has_function_privilege('service_role','public.transition_order_group_status(uuid,public.order_status,text)','EXECUTE'),
  'seller group transition remains restricted to its trusted server-side caller'
);

select ok(
  position('r.status in (''REQUESTED'',''APPROVED'',''FAILED'')' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0
  and position('''PROCESSING''' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) = 0
  and position('private.is_admin()' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0,
  'refund processing cannot be started twice and remains restricted to active admins'
);

select ok(
  position('if v_order.status = ''CANCELLED'' then' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)'::regprocedure)) > 0
  and position('insert into public.refunds' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)'::regprocedure)) > 0
  and position('Payment succeeded after order cancellation; refund required' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)'::regprocedure)) > 0
  and position('v_refund_inflight' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)'::regprocedure)) > 0
  and not has_function_privilege('authenticated','public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)','EXECUTE'),
  'late successful payment after cancellation queues one outstanding refund and stays server-only'
);

select ok(
  position('refund_provider_data_invalid' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0
  and position('nullif(trim(p.provider_reference),'''') is not null' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0
  and position('r.status in (''REQUESTED'',''APPROVED'',''FAILED'')' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0,
  'provider data is validated before refund processing starts'
);

select ok(
  to_regclass('private.idx_platform_repair_backups_restored_by_fk') is not null
  and to_regclass('private.idx_review_moderation_audit_actor_id_fk') is not null
  and to_regclass('private.idx_seller_access_audit_actor_user_id_fk') is not null
  and to_regclass('private.idx_seller_access_requests_conversation_id_fk') is not null
  and to_regclass('private.idx_seller_access_requests_initial_message_id_fk') is not null
  and to_regclass('private.idx_seller_access_requests_owner_shop_id_fk') is not null
  and to_regclass('private.idx_seller_access_requests_reviewed_by_fk') is not null
  and to_regclass('private.idx_seller_access_requests_revoked_by_fk') is not null,
  'all previously uncovered private foreign keys now have covering indexes'
);

select ok(
  not exists (
    select 1 from pg_policies
    where schemaname='public'
      and policyname in (
        'inventory_shared_access_read',
        'inventory_movements_shared_access_read',
        'order_groups_shared_access_read',
        'order_items_shared_access_read',
        'products_shared_access_read',
        'shops_shared_access_read'
      )
  )
  and (
    select count(*) from pg_policies
    where schemaname='public' and tablename='inventory'
      and cmd='SELECT' and 'authenticated'=any(roles)
  )=1
  and (
    select count(*) from pg_policies
    where schemaname='public' and tablename='order_groups'
      and cmd='SELECT' and 'authenticated'=any(roles)
  )=1
  and (
    select count(*) from pg_policies
    where schemaname='public' and tablename='products'
      and cmd='SELECT' and 'authenticated'=any(roles)
  )=1
  and (
    select count(*) from pg_policies
    where schemaname='public' and tablename='shops'
      and cmd='SELECT' and 'authenticated'=any(roles)
  )=1,
  'overlapping read policies are consolidated without removing authenticated access paths'
);

select ok(
  (
    select position('da.status = ANY' in qual)>0
       and position('op.status = ANY' in qual)>0
       and position('og.status <> ''CANCELLED''' in qual)>0
       and position('o.status <> ALL' in qual)>0
    from pg_policies
    where schemaname='public' and tablename='courier_locations'
      and policyname='courier_locations_read'
  ),
  'courier location is visible only for active delivery assignments and non-cancelled orders'
);

select ok(
  has_function_privilege('authenticated','public.start_package_delivery(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.start_package_delivery(uuid)','EXECUTE')
  and position('private.require_active_account()' in pg_get_functiondef('public.start_package_delivery(uuid)'::regprocedure)) > 0
  and position('private.has_role(''COURIER''::public.user_role)' in pg_get_functiondef('public.start_package_delivery(uuid)'::regprocedure)) > 0
  and position('da.courier_id=v_user' in pg_get_functiondef('public.start_package_delivery(uuid)'::regprocedure)) > 0,
  'courier can start only their own picked-up package with an active courier account'
);

select ok(
  has_function_privilege('authenticated','public.admin_reconcile_wave_refund(uuid,text,text)','EXECUTE')
  and not has_function_privilege('anon','public.admin_reconcile_wave_refund(uuid,text,text)','EXECUTE')
  and position('private.is_admin()' in pg_get_functiondef('public.admin_reconcile_wave_refund(uuid,text,text)'::regprocedure)) > 0
  and position('v_refund.status<>''PROCESSING''' in pg_get_functiondef('public.admin_reconcile_wave_refund(uuid,text,text)'::regprocedure)) > 0
  and position('v_payment.provider<>''WAVE''' in pg_get_functiondef('public.admin_reconcile_wave_refund(uuid,text,text)'::regprocedure)) > 0
  and position('RECONCILE_WAVE_REFUND' in pg_get_functiondef('public.admin_reconcile_wave_refund(uuid,text,text)'::regprocedure)) > 0,
  'Wave refund recovery requires admin confirmation and writes an audit record'
);

select ok(
  has_function_privilege('authenticated','public.get_courier_assignments()','EXECUTE')
  and not has_function_privilege('anon','public.get_courier_assignments()','EXECUTE')
  and position('private.require_active_account()' in pg_get_functiondef('public.get_courier_assignments()'::regprocedure)) > 0
  and position('private.has_role(''COURIER''::public.user_role)' in pg_get_functiondef('public.get_courier_assignments()'::regprocedure)) > 0
  and position('da.courier_id=v_user' in pg_get_functiondef('public.get_courier_assignments()'::regprocedure)) > 0
  and position('when da.status in (''ACCEPTED'',''PICKED_UP'',''IN_TRANSIT'') then o.delivery_address->>''phone''' in pg_get_functiondef('public.get_courier_assignments()'::regprocedure)) > 0,
  'courier assignment details expose contact only after acceptance and only to the assigned courier'
);


select ok(
  position('return public.cancel_unpaid_order(p_order_id);' in pg_get_functiondef('public.transition_order_status(uuid,public.order_status,text)'::regprocedure)) > 0
  and position('release_variant_inventory' in pg_get_functiondef('public.transition_order_status(uuid,public.order_status,text)'::regprocedure)) = 0
  and not has_function_privilege('anon','public.transition_order_status(uuid,public.order_status,text)','EXECUTE')
  and has_function_privilege('authenticated','public.transition_order_status(uuid,public.order_status,text)','EXECUTE'),
  'global order cancellation delegates to the unpaid-only workflow and no longer releases stock directly'
);

select ok(
  position('order_payment_already_settled' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('unpaid_order_has_dispatched_package' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('unpaid_order_has_dispatched_assignment' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('unpaid_order_inventory_already_consumed' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('CANCELLED_BY_ORDER' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('released_coupon_usage' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('customer_cancelled_before_payment' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0,
  'unpaid cancellation protects paid/dispatched/consumed orders, cancels pre-dispatch assignments, releases coupon usage, and logs the event'
);


select ok(
  position('v_is_admin := private.is_admin()' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('(customer_id = v_user or v_is_admin)' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('v_order.status <> ''PENDING_PAYMENT''' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0
  and position('order_payment_already_settled' in pg_get_functiondef('public.cancel_unpaid_order(uuid)'::regprocedure)) > 0,
  'active admins may cancel unpaid orders, but the workflow still rejects paid orders'
);


select ok(
  to_regprocedure('public.get_seller_product_variant_inventory(uuid)') is not null
  and has_function_privilege('authenticated','public.get_seller_product_variant_inventory(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.get_seller_product_variant_inventory(uuid)','EXECUTE')
  and not has_table_privilege('authenticated','public.product_variant_inventory','SELECT')
  and not has_table_privilege('anon','public.product_variant_inventory','SELECT')
  and position('private.require_active_account()' in pg_get_functiondef('public.get_seller_product_variant_inventory(uuid)'::regprocedure)) > 0
  and position('se.user_id = v_user' in pg_get_functiondef('public.get_seller_product_variant_inventory(uuid)'::regprocedure)) > 0,
  'seller variant inventory is read only through the owner-checked RPC, never by direct client table access'
);

select * from finish();
rollback;
