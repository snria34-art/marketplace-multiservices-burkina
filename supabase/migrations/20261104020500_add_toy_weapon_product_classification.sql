create or replace function private.scan_toy_weapon_products()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer := 0;
begin
  with toy_products as (
    select p.id,
      array(
        select term from unnest(array[
          'toy gun','toy pistol','toy rifle','water gun','plastic gun',
          'jouet pistolet','pistolet jouet','jouet arme','arme jouet',
          'faux pistolet','pistolet a eau','pistolet en plastique'
        ]) term
        where position(term in lower(coalesce(p.name,'')||' '||coalesce(p.description,'')))>0
      ) as matches
    from public.products p
    where p.status in ('DRAFT','PENDING_REVIEW','ACTIVE','INACTIVE')
  ),
  inserted as (
    insert into private.catalog_moderation_findings(
      product_id,rule_code,severity,matched_terms,explanation
    )
    select id,'TOY_WEAPON_REPRESENTATION','REVIEW',matches,
      'Article présenté comme jouet représentant une arme : vérifier que le produit est clairement un jouet non fonctionnel et que les images/description ne le présentent pas comme une arme réelle.'
    from toy_products where cardinality(matches)>0
    on conflict(product_id,rule_code) do update
      set matched_terms=excluded.matched_terms,explanation=excluded.explanation
      where private.catalog_moderation_findings.status in ('OPEN','UNDER_REVIEW')
    returning id
  )
  select count(*) into v_count from inserted;
  insert into private.platform_agent_runs(agent_code,status,findings_count,details,finished_at)
  values ('TOY_WEAPON_CLASSIFIER',case when v_count>0 then 'DEGRADED' else 'OK' end,
    v_count,jsonb_build_object('mode','deterministic_rules','automatic_product_blocking',false),now());
  return v_count;
end;
$function$;
revoke all on function private.scan_toy_weapon_products() from public,anon,authenticated;
select cron.schedule('toy-weapon-classifier','*/10 * * * *',
  $$select private.scan_toy_weapon_products();$$);
