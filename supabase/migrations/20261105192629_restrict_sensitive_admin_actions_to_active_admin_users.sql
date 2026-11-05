begin;

do $migration$
declare
  v_signature text;
  v_def text;
  v_old text;
  v_new text;
begin
  foreach v_signature in array array[
    'public.admin_mark_seller_payout_paid(uuid,text)',
    'public.admin_mark_seller_payout_failed(uuid,text)',
    'public.admin_set_account_status(uuid,public.account_status,text)'
  ]
  loop
    v_def := pg_get_functiondef(v_signature::regprocedure);
    v_old := 'if not public.is_admin_actor() then';
    if position(v_old in v_def) = 0 then
      raise exception 'expected_admin_actor_guard_not_found: %', v_signature;
    end if;
    v_new := replace(v_def, v_old, 'if not private.is_admin() then');
    if v_new = v_def then
      raise exception 'admin_guard_replacement_failed: %', v_signature;
    end if;
    execute v_new;
  end loop;

  foreach v_signature in array array[
    'public.admin_review_seller_access_request(uuid,boolean,text,integer)',
    'public.admin_review_seller_access_request_v2(uuid,boolean,text,text)'
  ]
  loop
    v_def := pg_get_functiondef(v_signature::regprocedure);
    v_old := 'v_admin is null or not private.is_active_account() or not public.is_admin_actor()';
    if position(v_old in v_def) = 0 then
      raise exception 'expected_seller_access_admin_guard_not_found: %', v_signature;
    end if;
    execute replace(v_def, v_old, 'v_admin is null or not private.is_admin()');
  end loop;

  v_signature := 'public.expire_seller_access_requests()';
  v_def := pg_get_functiondef(v_signature::regprocedure);
  v_old := 'auth.uid() is null or not private.is_active_account() or not public.is_admin_actor()';
  if position(v_old in v_def) = 0 then
    raise exception 'expected_expiration_admin_guard_not_found';
  end if;
  execute replace(v_def, v_old, 'auth.uid() is null or not private.is_admin()');

  v_signature := 'public.revoke_seller_access_request(uuid,text)';
  v_def := pg_get_functiondef(v_signature::regprocedure);
  v_old := 'v_actor <> v_request.owner_user_id and not public.is_admin_actor()';
  if position(v_old in v_def) = 0 then
    raise exception 'expected_seller_access_revocation_guard_not_found';
  end if;
  execute replace(v_def, v_old, 'v_actor <> v_request.owner_user_id and not private.is_admin()');

  v_signature := 'public.get_seller_access_requests()';
  v_def := pg_get_functiondef(v_signature::regprocedure);
  v_old := 'case when v_admin then r.admin_confirmation_notes else null end';
  if position(v_old in v_def) = 0 then
    raise exception 'expected_admin_notes_guard_not_found';
  end if;
  execute replace(v_def, v_old, 'case when private.is_admin() then r.admin_confirmation_notes else null end');
end;
$migration$;

commit;
