begin;
select plan(33);
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
select ok(
  position('seller_net_debit' in (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'refund_allocation_funding_balanced' and conrelid = 'public.refund_allocations'::regclass)) > 0
  and position('commission_reversal_amount' in (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'refund_allocation_funding_balanced' and conrelid = 'public.refund_allocations'::regclass)) > 0
  and position('platform_funded_amount' in (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'refund_allocation_funding_balanced' and conrelid = 'public.refund_allocations'::regclass)) > 0
  and position('customer_amount' in (select pg_get_constraintdef(oid) from pg_constraint
    where conname = 'refund_allocation_funding_balanced' and conrelid = 'public.refund_allocations'::regclass)) > 0,
  'customer amount equation separates net seller debit, commission reversal and platform funding');
select ok(position('refund_commission_reversal_exceeds_original'
  in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('refund_commission_ledger_convention_unknown'
  in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0,
  'commission reversal is bounded by a locked posted commission');
select ok(position('''COMMISSION_REVERSAL''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('commission_accounting_mode = ''GROSS_LEDGER''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('-(v_allocation.seller_net_debit + v_allocation.commission_reversal_amount)'
    in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'gross-ledger mode posts refund debit and positive commission reversal separately');
select ok(position('case when c.status = ''POSTED'' then ''REVERSED'' else ''CANCELLED'' end'
    in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('>= c.commission_amount' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'posted commission is reversed and pending commission cancelled only after full cumulative reversal');

select ok(position('ra2.ledger_posted_at is not null'
  in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('from public.commissions' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'commission status waits for posted ledger reversals and locks commission rows');

select ok(position('refund_not_eligible_for_allocation' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('v_refund.status not in (''APPROVED'',''PROCESSING'',''COMPLETED'')'
    in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0,
  'allocation can be frozen after approval or attached to an in-flight/completed recovery');

select ok(exists (select 1 from information_schema.columns where table_schema='public'
  and table_name='refund_allocations' and column_name='commission_accounting_mode'),
  'allocation records the original commission accounting convention');
select ok(position('v_commission_mode := ''GROSS_LEDGER''' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0
  and position('v_commission_mode := ''NET_SALE''' in pg_get_functiondef('public.set_refund_allocations(uuid,jsonb)'::regprocedure)) > 0,
  'allocation detects gross-ledger and net-sale commission conventions from actual ledger rows');
select ok(position('commission_accounting_mode = ''GROSS_LEDGER''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0
  and position('commission_accounting_mode = ''NET_SALE''' in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'reconciliation uses distinct ledger treatment for gross-sale and net-sale conventions');

select ok(to_regprocedure('public.get_refund_allocation_candidates(uuid)') is not null
  and to_regprocedure('public.get_refund_allocation_status(uuid)') is not null,
  'admin allocation review RPCs exist');
select ok(position('refund_allocations_required_or_unbalanced'
  in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0
  and position('r.status = ''APPROVED''' in pg_get_functiondef('public.admin_begin_refund(uuid)'::regprocedure)) > 0,
  'provider execution requires an approved refund and exact allocation');
select ok(position('perform public.reconcile_refund_accounting(p_refund_id)'
  in pg_get_functiondef('public.admin_complete_manual_refund(uuid,text)'::regprocedure)) > 0
  and position('refund_allocations_required_or_unbalanced'
  in pg_get_functiondef('public.admin_complete_manual_refund(uuid,text)'::regprocedure)) > 0,
  'manual provider confirmation reconciles only after balanced allocation');
select ok(has_function_privilege('authenticated','public.get_refund_allocation_candidates(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.get_refund_allocation_candidates(uuid)','EXECUTE')
  and has_function_privilege('authenticated','public.get_refund_allocation_status(uuid)','EXECUTE')
  and not has_function_privilege('anon','public.get_refund_allocation_status(uuid)','EXECUTE'),
  'allocation review RPCs are admin-only authenticated functions');

select ok(position('private.is_admin()' in pg_get_functiondef('public.get_refund_allocation_candidates(uuid)'::regprocedure)) > 0
  and position('private.is_admin()' in pg_get_functiondef('public.get_refund_allocation_status(uuid)'::regprocedure)) > 0,
  'allocation review functions enforce administrator authorization');

select ok(position('insert into public.seller_ledger' in
  pg_get_functiondef('public.complete_refund(uuid,text)'::regprocedure)) = 0,
  'provider completion does not write prorated seller ledger debits');
select ok(has_function_privilege('service_role','public.complete_refund(uuid,text)','EXECUTE')
  and not has_function_privilege('authenticated','public.complete_refund(uuid,text)','EXECUTE')
  and not has_function_privilege('anon','public.complete_refund(uuid,text)','EXECUTE'),
  'provider completion remains restricted to service role');
select ok(position('refund_legacy_ledger_entries_present'
  in pg_get_functiondef('public.reconcile_refund_accounting(uuid)'::regprocedure)) > 0,
  'legacy seller refund ledger entries block duplicate allocation posting');

select * from finish();
rollback;

