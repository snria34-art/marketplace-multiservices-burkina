alter table private.catalog_moderation_findings
  add column if not exists product_content_hash text;

create or replace function private.scan_catalog_for_restricted_items()
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer := 0;
begin
  with source as (
    select p.id,lower(coalesce(p.name,'') || ' ' || coalesce(p.description,'')) as text_value,
      md5(lower(coalesce(p.name,'') || ' ' || coalesce(p.description,''))) as content_hash
    from public.products p
    where p.status in ('DRAFT','PENDING_REVIEW','ACTIVE','INACTIVE')
  ),
  classified as (
    select s.id,s.content_hash,rules.rule_code,rules.severity,rules.explanation,
      array(select distinct term from unnest(rules.terms) term where position(term in s.text_value)>0) as matches
    from source s
    cross join lateral (
      values
      ('FIREARM_REAL','CRITICAL','Possible real firearm or ammunition: legal authorization and manual review required.',
       array['firearm','rifle','pistol','revolver','shotgun','ammunition','munitions','arme a feu','fusil','pistolet','revolver','cartouche']),
      ('DRUGS_CONTROLLED','CRITICAL','Possible controlled or recreational drug: prohibited pending compliance review.',
       array['cocaine','heroin','methamphetamine','amphetamine','mdma','ecstasy','cannabis','marijuana','thc','crystal meth','drogue','cannabis thc']),
      ('POISON_TOXIC','CRITICAL','Possible poison or highly toxic substance: prohibited; human safety review required.',
       array['cyanide','arsenic','ricin','strychnine','rat poison','poison mortel','pesticide mortel','toxic for humans']),
      ('APHRODISIAC','HIGH','Possible aphrodisiac or sexual performance product: prohibited by marketplace policy.',
       array['aphrodisiac','aphrodisiaque','sex stimulant','sexual enhancer','libido booster','stimulant sexuel']),
      ('HAZARDOUS_SKIN_PRODUCT','HIGH','Possible hazardous skin/cosmetic ingredient or claim: manual safety review required.',
       array['mercury cream','mercury whitening','mercury skin','clobetasol','clobetasol propionate','skin bleaching injection','cream with mercury','creme au mercure']),
      ('PESTICIDE_REVIEW','REVIEW','Pesticide or insecticide detected: verify product registration, label, safe use and seller authorization.',
       array['insecticide','pesticide','herbicide','rodenticide','fungicide','anti-moustique agricole'])
    ) as rules(rule_code,severity,explanation,terms)
    where exists(select 1 from unnest(rules.terms) term where position(term in s.text_value)>0)
      and not (rules.rule_code='FIREARM_REAL'
        and s.text_value ~ '(toy|jouet|water gun|pistolet a eau|en plastique|plastic gun|pistolet jouet|faux pistolet)')
  ),
  inserted as (
    insert into private.catalog_moderation_findings(
      product_id,rule_code,severity,matched_terms,explanation,product_content_hash
    )
    select id,rule_code,severity,matches,explanation,content_hash from classified
    on conflict(product_id,rule_code) do update
      set matched_terms=excluded.matched_terms,explanation=excluded.explanation,severity=excluded.severity,
          status=case when private.catalog_moderation_findings.product_content_hash is distinct from excluded.product_content_hash
            then 'OPEN' else private.catalog_moderation_findings.status end,
          detected_at=case when private.catalog_moderation_findings.product_content_hash is distinct from excluded.product_content_hash
            then now() else private.catalog_moderation_findings.detected_at end,
          product_content_hash=excluded.product_content_hash
      where private.catalog_moderation_findings.status in ('OPEN','UNDER_REVIEW')
         or (private.catalog_moderation_findings.status in ('CLEARED','REJECTED')
             and private.catalog_moderation_findings.product_content_hash is distinct from excluded.product_content_hash)
    returning id
  )
  select count(*) into v_count from inserted;
  insert into private.platform_agent_runs(agent_code,status,findings_count,details,finished_at)
  values('CATALOG_GUARD',case when v_count>0 then 'DEGRADED' else 'OK' end,v_count,
    jsonb_build_object('mode','deterministic_rules','automatic_high_critical_listing_suppression',true,
      'automatic_account_suspension',false,'automatic_balance_hold',false),now());
  return v_count;
end;
$$;