create table if not exists private.catalog_moderation_findings (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  rule_code text not null,
  severity text not null check (severity in ('REVIEW','HIGH','CRITICAL')),
  matched_terms text[] not null default '{}',
  explanation text not null,
  status text not null default 'OPEN' check (status in ('OPEN','UNDER_REVIEW','CLEARED','REJECTED')),
  detected_at timestamptz not null default now(),
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_notes text,
  unique(product_id,rule_code)
);
create index if not exists catalog_moderation_findings_status_idx
  on private.catalog_moderation_findings(status,severity,detected_at desc);
alter table private.catalog_moderation_findings enable row level security;
revoke all on private.catalog_moderation_findings from public,anon,authenticated;

create table if not exists private.platform_agent_runs (
  id uuid primary key default gen_random_uuid(),
  agent_code text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  status text not null check(status in ('OK','DEGRADED','ERROR')),
  findings_count integer not null default 0,
  details jsonb not null default '{}'::jsonb
);
create index if not exists platform_agent_runs_recent_idx
  on private.platform_agent_runs(agent_code,started_at desc);
alter table private.platform_agent_runs enable row level security;
revoke all on private.platform_agent_runs from public,anon,authenticated;

create or replace function private.scan_catalog_for_restricted_items()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer := 0;
begin
  with source as (
    select p.id,lower(coalesce(p.name,'') || ' ' || coalesce(p.description,'')) as text_value
    from public.products p
    where p.status in ('DRAFT','PENDING_REVIEW','ACTIVE','INACTIVE')
  ),
  classified as (
    select s.id,rules.rule_code,rules.severity,rules.explanation,
      array(select distinct term from unnest(rules.terms) term
            where position(term in s.text_value)>0) as matches
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
    where exists (select 1 from unnest(rules.terms) term where position(term in s.text_value)>0)
    and not (
      rules.rule_code='FIREARM_REAL'
      and s.text_value ~ '(toy|jouet|water gun|pistolet a eau|en plastique|plastic gun|pistolet jouet|faux pistolet)'
    )
  ),
  inserted as (
    insert into private.catalog_moderation_findings(product_id,rule_code,severity,matched_terms,explanation)
    select id,rule_code,severity,matches,explanation from classified
    on conflict(product_id,rule_code) do update
      set matched_terms=excluded.matched_terms,explanation=excluded.explanation
      where private.catalog_moderation_findings.status in ('OPEN','UNDER_REVIEW')
    returning id
  )
  select count(*) into v_count from inserted;

  insert into private.platform_agent_runs(agent_code,status,findings_count,details,finished_at)
  values ('CATALOG_GUARD',case when v_count>0 then 'DEGRADED' else 'OK' end,v_count,
    jsonb_build_object('mode','deterministic_rules','automatic_product_blocking',false),now());
  return v_count;
end;
$function$;
revoke all on function private.scan_catalog_for_restricted_items() from public,anon,authenticated;

create or replace function private.run_platform_health_checks()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare v_failed text[] := '{}'; v_checks integer := 0;
begin
  v_checks:=v_checks+1; if to_regclass('public.products') is null then v_failed:=array_append(v_failed,'products_table_missing'); end if;
  v_checks:=v_checks+1; if to_regclass('public.orders') is null then v_failed:=array_append(v_failed,'orders_table_missing'); end if;
  v_checks:=v_checks+1; if to_regclass('public.messages') is null then v_failed:=array_append(v_failed,'messages_table_missing'); end if;
  v_checks:=v_checks+1; if to_regclass('private.seller_access_requests') is null then v_failed:=array_append(v_failed,'seller_access_requests_missing'); end if;
  v_checks:=v_checks+1; if to_regclass('private.catalog_moderation_findings') is null then v_failed:=array_append(v_failed,'catalog_moderation_findings_missing'); end if;
  insert into private.platform_agent_runs(agent_code,status,findings_count,details,finished_at)
  values ('PLATFORM_WATCHDOG',case when cardinality(v_failed)=0 then 'OK' else 'DEGRADED' end,
    cardinality(v_failed),jsonb_build_object('checks_run',v_checks,'failed_checks',v_failed,'auto_repair',false),now());
  return cardinality(v_failed);
end;
$function$;
revoke all on function private.run_platform_health_checks() from public,anon,authenticated;

select cron.schedule('catalog-guard-scan','*/10 * * * *',
  $$select private.scan_catalog_for_restricted_items();$$);
select cron.schedule('platform-watchdog-check','*/5 * * * *',
  $$select private.run_platform_health_checks();$$);
