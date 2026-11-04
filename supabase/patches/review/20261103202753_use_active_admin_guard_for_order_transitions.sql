do $migration$
declare v_def text; v_old text;
begin
  v_def:=pg_get_functiondef('public.transition_order_status(uuid,public.order_status,text)'::regprocedure);
  v_old:='v_is_admin := exists ('||chr(10)||
         '    select 1 from public.admin_users au'||chr(10)||
         '    where au.user_id = v_user and au.active = true'||chr(10)||
         '  );';
  if position(v_old in v_def)=0 then raise exception 'transition_order_status_admin_check_not_found'; end if;
  execute replace(v_def,v_old,'v_is_admin := private.is_admin();');
end;
$migration$;