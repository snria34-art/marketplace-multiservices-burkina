create or replace function public.get_seller_access_requests()
returns setof jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_user uuid := auth.uid();
  v_admin boolean;
begin
  if v_user is null or not private.is_active_account() then
    raise exception 'Compte actif requis' using errcode='42501';
  end if;
  v_admin := public.is_admin_actor();
  return query
  select jsonb_build_object(
    'id',r.id,
    'owner_user_id',r.owner_user_id,
    'shop_id',r.owner_shop_id,
    'target_user_id',r.target_user_id,
    'scopes',r.requested_scopes,
    'reason',r.reason,
    'owner_message',r.owner_message,
    'status',r.status,
    'submitted_at',r.submitted_at,
    'reviewed_by',r.reviewed_by,
    'reviewed_at',r.reviewed_at,
    'phone_confirmed',r.admin_call_confirmed,
    'phone_confirmed_at',r.admin_call_confirmed_at,
    'admin_confirmation_notes',case when v_admin then r.admin_confirmation_notes else null end,
    'expires_at',r.expires_at,
    'revoked_at',r.revoked_at,
    'conversation_id',r.conversation_id,
    'initial_message_id',r.initial_message_id
  )
  from private.seller_access_requests r
  where v_admin or r.owner_user_id=v_user or r.target_user_id=v_user
  order by r.submitted_at desc;
end;
$function$;

revoke all on function public.get_seller_access_requests() from public, anon;
grant execute on function public.get_seller_access_requests() to authenticated;
