
create or replace function public.submit_seller_access_request(
  p_shop_id uuid,
  p_target_user_id uuid,
  p_scopes text[],
  p_reason text,
  p_owner_message text
) returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner uuid := auth.uid();
  v_request_id uuid;
  v_conversation_id uuid;
  v_message_id uuid;
  v_admin_count integer;
  v_allowed constant text[] := array[
    'shop_profile','products','inventory_read','orders_read','financial_read'
  ];
begin
  if v_owner is null or not private.is_active_account() then
    raise exception 'Compte actif requis' using errcode='42501';
  end if;
  if p_target_user_id is null or p_target_user_id = v_owner then
    raise exception 'Destinataire invalide';
  end if;
  if p_scopes is null or cardinality(p_scopes)=0
     or exists (select 1 from unnest(p_scopes) s where not (s = any(v_allowed))) then
    raise exception 'Périmètre demandé invalide ou pas encore disponible';
  end if;
  if length(btrim(coalesce(p_reason,''))) < 10
     or length(btrim(coalesce(p_owner_message,''))) < 10 then
    raise exception 'Motif et message à l’administration obligatoires (10 caractères minimum)';
  end if;
  if not exists (
    select 1 from public.shops sh
    join public.sellers se on se.id=sh.seller_id
    where sh.id=p_shop_id and se.user_id=v_owner
  ) then
    raise exception 'Vous ne possédez pas cette boutique' using errcode='42501';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id=p_target_user_id and p.status='ACTIVE'::public.account_status
  ) then
    raise exception 'Le compte destinataire est introuvable ou inactif';
  end if;
  if exists (
    select 1 from private.seller_access_requests r
    where r.owner_user_id=v_owner and r.owner_shop_id=p_shop_id
      and r.target_user_id=p_target_user_id
      and r.status in ('PENDING_ADMIN_CALL','APPROVED')
      and (r.expires_at is null or r.expires_at > now())
  ) then
    raise exception 'Une demande active existe déjà';
  end if;

  select count(*) into v_admin_count
  from public.user_roles ur
  join public.profiles p on p.id=ur.user_id
  where ur.role in ('ADMIN'::public.user_role,'SUPER_ADMIN'::public.user_role)
    and p.status='ACTIVE'::public.account_status;
  if v_admin_count=0 then
    raise exception 'Aucun administrateur actif : demande non créée. Contactez le support de la plateforme.';
  end if;

  insert into private.seller_access_requests(
    owner_user_id,owner_shop_id,target_user_id,requested_scopes,reason,owner_message
  ) values (
    v_owner,p_shop_id,p_target_user_id,
    array(select distinct unnest(p_scopes)),btrim(p_reason),btrim(p_owner_message)
  ) returning id into v_request_id;

  insert into public.conversations(type) values ('SELLER_ACCESS')
  returning id into v_conversation_id;

  insert into public.conversation_members(conversation_id,user_id)
  values (v_conversation_id,v_owner);

  insert into public.conversation_members(conversation_id,user_id)
  select v_conversation_id,ur.user_id
  from public.user_roles ur
  join public.profiles p on p.id=ur.user_id
  where ur.role in ('ADMIN'::public.user_role,'SUPER_ADMIN'::public.user_role)
    and p.status='ACTIVE'::public.account_status
  on conflict do nothing;

  insert into public.messages(conversation_id,sender_id,body)
  values (
    v_conversation_id,v_owner,
    'Demande de partage de boutique #'||v_request_id::text||E'\nMotif : '||btrim(p_reason)
      ||E'\nPérimètre demandé : '||array_to_string(array(select distinct unnest(p_scopes)),', ')
      ||E'\nMessage du propriétaire : '||btrim(p_owner_message)
  ) returning id into v_message_id;

  update private.seller_access_requests
  set conversation_id=v_conversation_id, initial_message_id=v_message_id
  where id=v_request_id;

  insert into private.seller_access_audit(request_id,actor_user_id,event_type,event_details)
  values (
    v_request_id,v_owner,'REQUEST_SUBMITTED',
    jsonb_build_object(
      'shop_id',p_shop_id,'target_user_id',p_target_user_id,
      'scopes',p_scopes,'conversation_id',v_conversation_id,
      'initial_message_id',v_message_id
    )
  );
  return v_request_id;
end;
$function$;

revoke all on function public.submit_seller_access_request(uuid,uuid,text[],text,text) from public, anon;
grant execute on function public.submit_seller_access_request(uuid,uuid,text[],text,text) to authenticated;
