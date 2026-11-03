do $migration$
declare v_def text; v_old text; v_new text;
begin
  v_def:=pg_get_functiondef('public.set_mechanic_availability(text,timestamptz,timestamptz)'::regprocedure);
  v_def:=replace(v_def,'  limit 1;','  limit 1 for update;');
  v_old:='  if p_ends_at is not null and p_ends_at <= v_start then'||chr(10)||
    '    raise exception ''availability_period_invalid'';'||chr(10)||'  end if;';
  v_new:=v_old||chr(10)||chr(10)||
    '  if v_start < now() then'||chr(10)||
    '    raise exception ''availability_start_in_past'';'||chr(10)||'  end if;';
  if position(v_old in v_def)=0 then raise exception 'mechanic_availability_date_guard_not_found'; end if;
  v_def:=replace(v_def,v_old,v_new);
  v_old:='  update public.mechanic_availability'||chr(10)||
    '  set ends_at = now()'||chr(10)||
    '  where mechanic_id=v_mechanic'||chr(10)||
    '    and ends_at is null'||chr(10)||
    '    and starts_at <= now();';
  v_new:=v_old||chr(10)||chr(10)||
    '  if exists ('||chr(10)||
    '    select 1'||chr(10)||
    '    from public.mechanic_availability ma'||chr(10)||
    '    where ma.mechanic_id = v_mechanic'||chr(10)||
    '      and ma.starts_at < coalesce(p_ends_at, ''infinity''::timestamptz)'||chr(10)||
    '      and coalesce(ma.ends_at, ''infinity''::timestamptz) > v_start'||chr(10)||
    '  ) then'||chr(10)||
    '    raise exception ''availability_period_overlap'';'||chr(10)||
    '  end if;';
  if position(v_old in v_def)=0 then raise exception 'mechanic_availability_lock_patch_not_found'; end if;
  execute replace(v_def,v_old,v_new);
end;
$migration$;