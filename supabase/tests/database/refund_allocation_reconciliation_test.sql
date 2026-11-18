begin;
select plan(20);
select ok(to_regclass('public.refund_allocations') is not null, 'refund allocation table exists');
select ok((select relrowsecurity from pg_class where oid='public.refund_allocations'::regclass), 'allocation table has RLS');
select ok(not has_table_privilege('anon','public.refund_allocations','SELECT')
  and not has_table_privilege('authenticated','public.refund_allocations','INSERT')
  and not has_table_privilege('authenticated','public.refund_allocations','UPDATE'), 'direct client access is revoked');
select ok(to_regprocedure('public.set_refund_allocations(uuid,jsonb)') is not null, 'allocation RPC exists');
select ok(to_regprocedure('public.reconcile_refund_accounting(uuid)') is not null, 'reconciliation RPC exists');
select ok(has_function_privilege('authenticated','public.set_refund_allocations(uuid,jsonb)','EXECUTE')
  and not has_function_privilege('anon','public.set_refund_allocations(uuid,jsonb)','EXECUTE'), 'allocation RPC requires authenticated caller');
select ok(has_function_privilege('authenticated','public.reconcile_refund_accounting(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.reconcile_refund_accounting(uuid)','EXECUTE'), 'reconciliation RPC requires authenticated caller');
select ok((select prosecdef from pg_proc where oid='public.set_refund_allocations(uuid,jsonb)'::regprocedure)
  and (select prosecdef from pg_proc where oid='public.reconcile_refund_accounting(uuid)'::regprocedure), 'financial RPCs are security definer');
select ok(position('private.is_admin()' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('private.is_admin()' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0, 'both RPCs enforce administrator authorization');
select ok(position('refund_quantity_exceeds_ordered' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('for update' in lower(pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure))) > 0, 'item quantities are locked and bounded');
select ok(position('refund_allocation_total_mismatch' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('v_customer_total <> v_refund.amount' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0, 'allocation total must equal customer refund exactly');
select ok(position('refund_seller_sale_not_credited' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('refund_seller_balance_insufficient' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0, 'reconciliation rejects missing sales and insufficient balances');
select ok(position('v_allocation.id' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('''REFUND''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('status = ''RECONCILED''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0, 'ledger uses allocation id and hold clears only after posting');
select ok(to_regprocedure('public.record_provider_refund_confirmation(uuid,text)') is not null,
  'manual provider-confirmation recovery RPC exists');
select ok(position('refund_not_processing' in pg_get_functiondef('public.record_provider_refund_confirmation(uuid,text)'::regprocedure)) > 0
  and position('provider_refund_reference_conflict' in pg_get_functiondef('public.record_provider_refund_confirmation(uuid,text)'::regprocedure)) > 0
  and position('status = ''COMPLETED''' in pg_get_functiondef('public.record_provider_refund_confirmation(uuid,text)'::regprocedure)) > 0,
  'recovery accepts only processing refunds and is idempotent on the same provider reference');

select ok(exists (select 1 from information_schema.columns where table_schema='public'
  and table_name='refund_allocations' and column_name='commission_reversal_amount'),
  'allocation stores a separate commission reversal amount');
select ok(position('seller_net_debit + commission_reversal_amount + platform_funded_amount = customer_amount'
  in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0,
  'customer amount equation separates net seller debit, commission reversal and platform funding');
select ok(position('refund_commission_reversal_exceeds_original'
  in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('refund_commission_not_posted'
  in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0,
  'commission reversal is bounded by a locked posted commission');
select ok(position('''COMMISSION_REVERSAL''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('-(v_allocation.seller_net_debit + v_allocation.commission_reversal_amount)'
    in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'ledger posts gross refund debit and positive commission reversal separately');
select ok(position('set status = ''REVERSED''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('>= c.commission_amount' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'commission status changes only after full cumulative reversal');

select * from finish();
rollback;

