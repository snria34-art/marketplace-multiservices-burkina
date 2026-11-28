begin;

create or replace function public.admin_list_pending_provider_applications()
returns table (
  provider_id uuid,
  user_id uuid,
  provider_type text,
  display_name text,
  description text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = 'pg_catalog, public, private, pg_temp'
as $function$
begin
  if not (select private.is_admin()) then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  return query
  select sp.id, sp.user_id, sp.provider_type, sp.display_name,
         sp.description, sp.created_at
  from public.service_providers sp
  where sp.verification_status = 'PENDING'::public.verification_status
  order by sp.created_at asc
  limit 200;
end;
$function$;

create or replace function public.admin_review_provider_application(
  p_provider_id uuid,
  p_decision text,
  p_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = 'pg_catalog, public, private, pg_temp'
as $function$
declare
  v_user uuid := (select auth.uid());
  v_decision text := upper(pg_catalog.btrim(coalesce(p_decision, '')));
  v_note text := nullif(pg_catalog.btrim(p_note), '');
  v_provider public.service_providers%rowtype;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if not (select private.is_admin()) then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  if p_provider_id is null or v_decision not in ('APPROVE','REJECT') then
    raise exception 'invalid_provider_review' using errcode = '22023';
  end if;
  if v_decision = 'REJECT'
     and (v_note is null or pg_catalog.char_length(v_note) < 5
          or pg_catalog.char_length(v_note) > 1000) then
    raise exception 'rejection_reason_required' using errcode = '22023';
  end if;
  if v_decision = 'APPROVE' and v_note is not null
     and pg_catalog.char_length(v_note) > 1000 then
    raise exception 'review_note_too_long' using errcode = '22023';
  end if;

  select * into v_provider
  from public.service_providers
  where id = p_provider_id
  for update;

  if not found then
    raise exception 'provider_application_not_found' using errcode = 'P0002';
  end if;
  if v_provider.verification_status <> 'PENDING'::public.verification_status then
    raise exception 'provider_application_already_reviewed' using errcode = '23505';
  end if;

  -- Fail closed until private KYC document upload and administrative
  -- document verification are implemented. Self-declared application fields
  -- alone must never activate a mobility or logistics provider.
  if v_decision = 'APPROVE' then
    raise exception 'provider_kyc_documents_required'
      using errcode = '42501';
  end if;

  update public.service_providers
  set verification_status = case
        when v_decision = 'APPROVE'
          then 'VERIFIED'::public.verification_status
        else 'REJECTED'::public.verification_status
      end,
      active = (v_decision = 'APPROVE')
  where id = p_provider_id;

  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  values (
    v_user,
    case when v_decision = 'APPROVE'
      then 'ADMIN_PROVIDER_APPLICATION_APPROVED'
      else 'ADMIN_PROVIDER_APPLICATION_REJECTED'
    end,
    'service_provider',
    p_provider_id,
    pg_catalog.jsonb_build_object(
      'provider_type', v_provider.provider_type,
      'decision', v_decision,
      'note', v_note
    )
  );

  return true;
end;
$function$;

revoke all on function public.admin_list_pending_provider_applications()
  from public, anon;
revoke all on function public.admin_review_provider_application(uuid,text,text)
  from public, anon;
grant execute on function public.admin_list_pending_provider_applications()
  to authenticated;
grant execute on function public.admin_review_provider_application(uuid,text,text)
  to authenticated;

commit;
