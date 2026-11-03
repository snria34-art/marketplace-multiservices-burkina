alter table private.product_listing_restrictions
  alter column applied_by drop not null,
  add column if not exists applied_source text not null default 'ADMIN';
do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='private.product_listing_restrictions'::regclass and conname='product_listing_restrictions_source_check') then
    alter table private.product_listing_restrictions
      add constraint product_listing_restrictions_source_check
      check (applied_source in ('ADMIN','AUTOMATED_GUARD'));
  end if;
end $$;

create or replace function private.auto_suppress_high_risk_listing()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_seller_user uuid; v_previous_status text; v_inserted integer;
begin
  if new.status <> 'OPEN' or new.severity not in ('HIGH','CRITICAL') then return new; end if;
  select p.status::text,s.user_id into v_previous_status,v_seller_user
  from public.products p
  join public.shops sh on sh.id=p.shop_id
  join public.sellers s on s.id=sh.seller_id
  where p.id=new.product_id
  for update of p;
  if v_seller_user is null then return new; end if;
  insert into private.product_listing_restrictions(
    product_id,finding_id,previous_status,reason,applied_by,applied_source
  ) values (
    new.product_id,new.id,v_previous_status,
    left(coalesce(new.explanation,'Risque élevé détecté; contrôle administratif requis.'),2000),
    null,'AUTOMATED_GUARD'
  )
  on conflict (product_id) where active do nothing;
  get diagnostics v_inserted = row_count;
  if v_inserted > 0 then
    update public.products set status='INACTIVE',updated_at=now()
    where id=new.product_id and status<>'INACTIVE';
    insert into public.notifications(user_id,type,title,body,data)
    values(
      v_seller_user,'CATALOG_MODERATION','Annonce temporairement masquée pour vérification',
      'Une vérification est nécessaire avant la remise en vente de cet article. Votre boutique, vos commandes, vos données et votre solde ne sont pas supprimés ni bloqués. Motif : ' || left(coalesce(new.explanation,''),500),
      jsonb_build_object('finding_id',new.id,'product_id',new.product_id,'action','AUTO_LISTING_SUPPRESSED')
    );
  end if;
  return new;
end;
$$;
revoke all on function private.auto_suppress_high_risk_listing() from public,anon,authenticated;

drop trigger if exists auto_suppress_high_risk_catalog_listing on private.catalog_moderation_findings;
create trigger auto_suppress_high_risk_catalog_listing
after insert or update of severity,status on private.catalog_moderation_findings
for each row execute function private.auto_suppress_high_risk_listing();