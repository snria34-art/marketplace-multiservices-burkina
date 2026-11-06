do $migration$
declare v_def text;
begin
  v_def:=pg_get_functiondef('public.accept_delivery_assignment(uuid)'::regprocedure);
  v_def:=replace(v_def,'begin'||chr(10),'begin'||chr(10)||
    '  perform private.require_active_account();'||chr(10)||
    '  if not private.has_role(''COURIER''::public.user_role) then raise exception ''courier_role_required'' using errcode = ''42501''; end if;'||chr(10));
  if v_def not like '%require_active_account%' or v_def not like '%has_role%' then raise exception 'accept_delivery_assignment_guard_patch_failed'; end if;
  execute v_def;

  v_def:=pg_get_functiondef('public.confirm_package_pickup(uuid,text)'::regprocedure);
  v_def:=replace(v_def,'begin'||chr(10),'begin'||chr(10)||' perform private.require_active_account();'||chr(10));
  if v_def not like '%require_active_account%' then raise exception 'confirm_package_pickup_guard_patch_failed'; end if;
  execute v_def;

  v_def:=pg_get_functiondef('public.confirm_package_delivery(uuid,text)'::regprocedure);
  v_def:=replace(v_def,'begin'||chr(10),'begin'||chr(10)||
    ' perform private.require_active_account();'||chr(10)||
    ' if not private.has_role(''COURIER''::public.user_role) then raise exception ''courier_role_required'' using errcode = ''42501''; end if;'||chr(10));
  if v_def not like '%require_active_account%' or v_def not like '%has_role%' then raise exception 'confirm_package_delivery_guard_patch_failed'; end if;
  execute v_def;
end;
$migration$;

grant execute on function public.accept_delivery_assignment(uuid) to authenticated;
grant execute on function public.confirm_package_pickup(uuid,text) to authenticated;
grant execute on function public.confirm_package_delivery(uuid,text) to authenticated;
grant execute on function public.transition_order_status(uuid,public.order_status,text) to authenticated;
grant execute on function public.cancel_unpaid_order(uuid) to authenticated;