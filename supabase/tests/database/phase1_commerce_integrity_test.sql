begin;
select plan(20);
select ok(exists(select 1 from information_schema.columns where table_schema='public' and table_name='payment_events' and column_name='provider_event_id'),'event identity column exists');
select ok(exists(select 1 from pg_indexes where schemaname='public' and indexname='uq_payment_events_provider_event_id') and exists(select 1 from pg_indexes where schemaname='public' and indexname='uq_payment_events_legacy_idempotency') and not exists(select 1 from pg_indexes where schemaname='public' and indexname='uq_payment_events_provider_ref'),'event id unique; stable payment reference reusable');
select ok(to_regprocedure('public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb)') is not null and to_regprocedure('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)') is not null and has_function_privilege('service_role','public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb)','EXECUTE') and not has_function_privilege('authenticated','public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb)','EXECUTE') and not has_function_privilege('anon','public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb)','EXECUTE'),'processor overloads and service-only permissions');
select ok(position('p_provider_event_id' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb)'::regprocedure))>0 and position('payment_provider_event_identity_conflict' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,text,jsonb)'::regprocedure))>0,'event id dedupe and conflict validation');
select ok(position('public.process_payment_event' in pg_get_functiondef('public.process_payment_event(uuid,text,public.payment_status,text,numeric,jsonb)'::regprocedure))>0,'legacy overload delegates to event-aware function');
select ok(position('status not in (''CANCELLED'',''DELIVERED'')' in pg_get_functiondef('public.assign_package_to_courier(uuid,uuid)'::regprocedure))>0 and position('COMPLETED' in pg_get_functiondef('public.assign_package_to_courier(uuid,uuid)'::regprocedure))=0,'assignment terminal status is valid');
select ok(position('set status=''DELIVERED''' in pg_get_functiondef('public.sync_after_package_delivery(uuid)'::regprocedure))>0 and position('COMPLETED' in pg_get_functiondef('public.sync_after_package_delivery(uuid)'::regprocedure))=0,'delivery sync writes DELIVERED');
select ok(to_regclass('private.refund_accounting_reconciliations') is not null and (select relrowsecurity from pg_class where oid='private.refund_accounting_reconciliations'::regclass) and not has_table_privilege('anon','private.refund_accounting_reconciliations','SELECT') and not has_table_privilege('authenticated','private.refund_accounting_reconciliations','SELECT'),'refund hold table private');
select ok(exists(select 1 from pg_trigger where tgrelid='public.refunds'::regclass and tgname='trg_sync_refund_accounting_hold' and not tgisinternal),'refund hold trigger installed');
select ok(position('refund_financial_reconciliation_required' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure))>0 and position('ar.refund_id<>p_refund_id' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure))>0 and position('prior.status in (''PENDING'',''PROCESSING'',''COMPLETED'',''FAILED'')' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure))>0,'subsequent provider refund is blocked only after an earlier attempt has started');
select ok(
  position('where p.id=v_payment_id' in lower(pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure))) > 0
  and position('for update' in lower(substring(
    pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)
    from position('where p.id=v_payment_id' in lower(pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)))
  ))) > 0
  and position('refund_financial_reconciliation_required' in lower(pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)))
      > position('where p.id=v_payment_id' in lower(pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure))),
  'refund attempts lock their payment before reconciliation checks to prevent concurrent double starts'
);
select ok(position('seller_payout_blocked_by_refund_reconciliation' in pg_get_functiondef('public.request_seller_payout_secure(uuid,numeric,text)'::regprocedure))>0,'seller payout blocked while allocation pending');
select ok(position('public.seller_ledger' in pg_get_functiondef('public.complete_refund(uuid,text)'::regprocedure))=0 and position('update public.payments' in pg_get_functiondef('public.complete_refund(uuid,text)'::regprocedure))>0,'refund finalizer does not invent seller ledger debits');
select ok(position('accounting_status' in pg_get_functiondef('public.get_admin_refunds()'::regprocedure))>0 and position('accounting_note' in pg_get_functiondef('public.get_admin_refunds()'::regprocedure))>0,'admin refund list exposes hold information');
select ok((select prosecdef from pg_proc where oid='private.sync_refund_accounting_hold()'::regprocedure) and not has_function_privilege('authenticated','private.sync_refund_accounting_hold()','EXECUTE'),'refund trigger helper stays privileged');
select ok(position('PENDING_ALLOCATION' in pg_get_functiondef('public.request_seller_payout_secure(uuid,numeric,text)'::regprocedure))>0 and position('PENDING_ALLOCATION' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure))>0,'financial holds gate payout and next provider refund');

select ok(
  position('payment_checkout_reference_conflict' in pg_get_functiondef('public.prepare_payment_processing(uuid,text,jsonb)'::regprocedure)) > 0
  and position('trim(v_payment.provider_reference) <> trim(p_provider_reference)' in pg_get_functiondef('public.prepare_payment_processing(uuid,text,jsonb)'::regprocedure)) > 0
  and position('v_payment.status::text = ''SUCCEEDED''' in pg_get_functiondef('public.prepare_payment_processing(uuid,text,jsonb)'::regprocedure)) > 0
  and position('private.require_active_account()' in pg_get_functiondef('public.prepare_payment_processing(uuid,text,jsonb)'::regprocedure)) > 0,
  'one provider checkout reference wins; conflicting sessions are rejected and a settled matching session is idempotent'
);

select ok(
  position('currency' in pg_get_triggerdef((
    select oid from pg_trigger
    where tgrelid='public.refunds'::regclass
      and tgname='trg_sync_refund_accounting_hold'
      and not tgisinternal
  ))) > 0,
  'refund accounting hold refreshes when the refund currency changes'
);

select ok(
  position('r.amount=trunc(r.amount)' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0,
  'provider refund claim rejects fractional XOF before moving the refund to processing'
);

select ok(
  position('p_amount <> trunc(p_amount)' in pg_get_functiondef('public.request_refund(uuid,numeric,text)'::regprocedure)) > 0
  and position('private.require_active_account()' in pg_get_functiondef('public.request_refund(uuid,numeric,text)'::regprocedure)) > 0
  and position('refund_currency_not_supported' in pg_get_functiondef('public.request_refund(uuid,numeric,text)'::regprocedure)) > 0,
  'customer refund requests reject fractional XOF and preserve the active-account guard'
);
select * from finish();
rollback;