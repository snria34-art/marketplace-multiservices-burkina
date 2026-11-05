-- Bind delivery evidence to an assignment for the exact package being delivered.
-- Fail closed if the expected live function source has drifted.
do $migration$
declare
  v_definition text;
  v_old text := E'\n     and da.courier_id=(select auth.uid()) and da.status=''IN_TRANSIT''';
  v_new text := E'\n     and da.courier_id=(select auth.uid()) and da.package_id=p_package_id and da.status=''IN_TRANSIT''';
  v_count integer;
begin
  v_definition := pg_get_functiondef('public.confirm_package_delivery(uuid,text)'::regprocedure);
  v_count := (length(v_definition) - length(replace(v_definition, v_old, ''))) / length(v_old);
  if v_count <> 1 then
    raise exception 'delivery_evidence_assignment_guard_expected_once_got_%', v_count;
  end if;
  v_definition := replace(v_definition, v_old, v_new);
  if position(v_new in v_definition) = 0 then
    raise exception 'delivery_evidence_assignment_guard_patch_failed';
  end if;
  execute v_definition;
end
$migration$;
