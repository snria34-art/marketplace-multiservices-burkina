create or replace function public.admin_reconcile_wave_refund(
  p_refund_id uuid,
  p_provider_refund_reference text,
  p_confirmation_note text
)
returns boolean
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_refund public.refunds%rowtype;
  v_payment public.payments%rowtype;
  v_note text := trim(coalesce(p_confirmation_note,''));
  v_provider_ref text := trim(coalesce(p_provider_refund_reference,''));
begin
  if not private.is_admin() then
    raise exception 'ADMIN_REQUIRED' using errcode='42501';
  end if;

  if p_refund_id is null
     or length(v_provider_ref)=0
     or length(v_provider_ref)>200
     or length(v_note)<10
     or length(v_note)>500 then
    raise exception 'refund_reconciliation_input_invalid';
  end if;

  -- Lock order matches complete_refund: refund first, then payment.
  select * into v_refund
  from public.refunds
  where id=p_refund_id
  for update;
  if not found then raise exception 'refund_not_found'; end if;

  if v_refund.status<>'PROCESSING' then
    raise exception 'refund_not_in_processing';
  end if;

  select * into v_payment
  from public.payments
  where id=v_refund.payment_id
  for update;
  if not found then raise exception 'payment_not_found'; end if;

  if v_payment.provider<>'WAVE' then
    raise exception 'wave_payment_required';
  end if;

  update public.refunds
  set reason=left(coalesce(reason,'') || ' | Admin reconciliation: ' || v_note,1000)
  where id=p_refund_id;

  insert into public.admin_change_log(
    actor_id,entity_type,entity_id,action,before_data,after_data
  )
  values(
    auth.uid(),
    'refund',
    p_refund_id,
    'RECONCILE_WAVE_REFUND',
    jsonb_build_object(
      'status',v_refund.status,
      'provider',v_payment.provider,
      'amount',v_refund.amount
    ),
    jsonb_build_object(
      'provider_refund_reference',v_provider_ref,
      'confirmation_note',v_note,
      'status','COMPLETED'
    )
  );

  return public.complete_refund(
    p_refund_id,
    'WAVE_REFUND:' || v_provider_ref
  );
end;
$function$;

revoke all on function public.admin_reconcile_wave_refund(uuid,text,text) from public,anon;
grant execute on function public.admin_reconcile_wave_refund(uuid,text,text) to authenticated,service_role;
