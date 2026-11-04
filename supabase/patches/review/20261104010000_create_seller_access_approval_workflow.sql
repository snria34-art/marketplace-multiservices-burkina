-- Seller cross-account access: request, mandatory admin phone confirmation, expiry, revocation and audit.
create table if not exists private.seller_access_requests (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete restrict,
  owner_shop_id uuid not null references public.shops(id) on delete restrict,
  target_user_id uuid not null references auth.users(id) on delete restrict,
  requested_scopes text[] not null,
  reason text not null,
  owner_message text not null,
  status text not null default 'PENDING_ADMIN_CALL'
    check (status in ('PENDING_ADMIN_CALL','APPROVED','REJECTED','EXPIRED','REVOKED')),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references auth.users(id) on delete restrict,
  reviewed_at timestamptz,
  admin_call_confirmed boolean not null default false,
  admin_call_confirmed_at timestamptz,
  admin_confirmation_notes text,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  constraint seller_access_request_different_users check (owner_user_id <> target_user_id),
  constraint seller_access_request_scopes_nonempty check (cardinality(requested_scopes) > 0),
  constraint seller_access_request_reason_nonempty check (length(btrim(reason)) > 0),
  constraint seller_access_request_message_nonempty check (length(btrim(owner_message)) > 0),
  constraint seller_access_request_expiry check (expires_at is null or expires_at > submitted_at)
);
create index if not exists seller_access_requests_owner_idx on private.seller_access_requests(owner_user_id, submitted_at desc);
create index if not exists seller_access_requests_target_idx on private.seller_access_requests(target_user_id, status);
create index if not exists seller_access_requests_expiry_idx on private.seller_access_requests(expires_at) where status='APPROVED';

create table if not exists private.seller_access_audit (
  id bigint generated always as identity primary key,
  request_id uuid not null references private.seller_access_requests(id) on delete restrict,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in ('REQUEST_SUBMITTED','PHONE_CONFIRMED','APPROVED','REJECTED','REVOKED','EXPIRED')),
  event_details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists seller_access_audit_request_idx on private.seller_access_audit(request_id, created_at);
alter table private.seller_access_requests enable row level security;
alter table private.seller_access_audit enable row level security;
revoke all on private.seller_access_requests from public, anon, authenticated;
revoke all on private.seller_access_audit from public, anon, authenticated;
revoke all on sequence private.seller_access_audit_id_seq from public, anon, authenticated;

create or replace function public.submit_seller_access_request(p_shop_id uuid,p_target_user_id uuid,p_scopes text[],p_reason text,p_owner_message text)
returns uuid language plpgsql security definer set search_path=''
as $function$
declare v_owner uuid:=auth.uid(); v_request_id uuid;
v_allowed constant text[]:=array['shop_profile','products','inventory_read','orders_read','order_fulfillment','financial_read','documents_read'];
begin
 if v_owner is null or not private.is_active_account() then raise exception 'Compte actif requis' using errcode='42501'; end if;
 if p_target_user_id is null or p_target_user_id=v_owner then raise exception 'Destinataire invalide'; end if;
 if p_scopes is null or cardinality(p_scopes)=0 or exists(select 1 from unnest(p_scopes) s where not(s=any(v_allowed))) then raise exception 'Périmètre demandé invalide'; end if;
 if length(btrim(coalesce(p_reason,'')))<10 or length(btrim(coalesce(p_owner_message,'')))<10 then raise exception 'Motif et message à l’administration obligatoires (10 caractères minimum)'; end if;
 if not exists(select 1 from public.shops sh join public.sellers se on se.id=sh.seller_id where sh.id=p_shop_id and se.user_id=v_owner) then raise exception 'Vous ne possédez pas cette boutique' using errcode='42501'; end if;
 if not exists(select 1 from public.profiles p where p.id=p_target_user_id and p.status='ACTIVE'::public.account_status) then raise exception 'Le compte destinataire est introuvable ou inactif'; end if;
 if exists(select 1 from private.seller_access_requests r where r.owner_user_id=v_owner and r.owner_shop_id=p_shop_id and r.target_user_id=p_target_user_id and r.status in ('PENDING_ADMIN_CALL','APPROVED') and (r.expires_at is null or r.expires_at>now())) then raise exception 'Une demande active existe déjà'; end if;
 insert into private.seller_access_requests(owner_user_id,owner_shop_id,target_user_id,requested_scopes,reason,owner_message)
 values(v_owner,p_shop_id,p_target_user_id,array(select distinct unnest(p_scopes)),btrim(p_reason),btrim(p_owner_message)) returning id into v_request_id;
 insert into private.seller_access_audit(request_id,actor_user_id,event_type,event_details) values(v_request_id,v_owner,'REQUEST_SUBMITTED',jsonb_build_object('shop_id',p_shop_id,'target_user_id',p_target_user_id,'scopes',p_scopes));
 return v_request_id;
end;$function$;

create or replace function public.admin_review_seller_access_request(p_request_id uuid,p_approve boolean,p_phone_confirmation_notes text,p_validity_hours integer default 24)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_request private.seller_access_requests%rowtype; v_admin uuid:=auth.uid();
begin
 if v_admin is null or not private.is_active_account() or not public.is_admin_actor() then raise exception 'Accès administrateur requis' using errcode='42501'; end if;
 if length(btrim(coalesce(p_phone_confirmation_notes,'')))<10 then raise exception 'La confirmation téléphonique doit être documentée'; end if;
 if p_approve and (p_validity_hours is null or p_validity_hours<1 or p_validity_hours>168) then raise exception 'Durée autorisée : 1 à 168 heures'; end if;
 select * into v_request from private.seller_access_requests where id=p_request_id for update;
 if not found or v_request.status<>'PENDING_ADMIN_CALL' then raise exception 'Demande introuvable ou déjà traitée'; end if;
 update private.seller_access_requests set status=case when p_approve then 'APPROVED' else 'REJECTED' end,reviewed_by=v_admin,reviewed_at=now(),admin_call_confirmed=true,admin_call_confirmed_at=now(),admin_confirmation_notes=btrim(p_phone_confirmation_notes),expires_at=case when p_approve then now()+make_interval(hours=>p_validity_hours) else null end where id=p_request_id;
 insert into private.seller_access_audit(request_id,actor_user_id,event_type,event_details) values(p_request_id,v_admin,case when p_approve then 'APPROVED' else 'REJECTED' end,jsonb_build_object('phone_confirmed',true,'notes',btrim(p_phone_confirmation_notes),'validity_hours',case when p_approve then p_validity_hours else null end));
end;$function$;

create or replace function public.revoke_seller_access_request(p_request_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=''
as $function$
declare v_actor uuid:=auth.uid(); v_request private.seller_access_requests%rowtype;
begin
 if v_actor is null or not private.is_active_account() then raise exception 'Compte actif requis' using errcode='42501'; end if;
 if length(btrim(coalesce(p_reason,'')))<5 then raise exception 'Motif de révocation obligatoire'; end if;
 select * into v_request from private.seller_access_requests where id=p_request_id for update;
 if not found then raise exception 'Demande introuvable'; end if;
 if v_actor<>v_request.owner_user_id and not public.is_admin_actor() then raise exception 'Seul le propriétaire ou un administrateur peut révoquer' using errcode='42501'; end if;
 if v_request.status<>'APPROVED' then raise exception 'Seule une autorisation active peut être révoquée'; end if;
 update private.seller_access_requests set status='REVOKED',revoked_at=now(),revoked_by=v_actor where id=p_request_id;
 insert into private.seller_access_audit(request_id,actor_user_id,event_type,event_details) values(p_request_id,v_actor,'REVOKED',jsonb_build_object('reason',btrim(p_reason)));
end;$function$;

create or replace function public.expire_seller_access_requests()
returns integer language plpgsql security definer set search_path=''
as $function$
declare v_count integer;
begin
 if not public.is_admin_actor() then raise exception 'Accès administrateur requis' using errcode='42501'; end if;
 with expired as (update private.seller_access_requests set status='EXPIRED' where status='APPROVED' and expires_at<=now() returning id)
 insert into private.seller_access_audit(request_id,event_type,event_details) select id,'EXPIRED','{"reason":"validity_period_elapsed"}'::jsonb from expired;
 get diagnostics v_count=row_count; return v_count;
end;$function$;

create or replace function public.get_seller_access_requests()
returns setof jsonb language plpgsql stable security definer set search_path=''
as $function$
declare v_user uuid:=auth.uid(); v_admin boolean;
begin
 if v_user is null or not private.is_active_account() then raise exception 'Compte actif requis' using errcode='42501'; end if;
 v_admin:=public.is_admin_actor();
 return query select jsonb_build_object('id',r.id,'owner_user_id',r.owner_user_id,'shop_id',r.owner_shop_id,'target_user_id',r.target_user_id,'scopes',r.requested_scopes,'reason',r.reason,'owner_message',r.owner_message,'status',r.status,'submitted_at',r.submitted_at,'reviewed_by',r.reviewed_by,'reviewed_at',r.reviewed_at,'phone_confirmed',r.admin_call_confirmed,'phone_confirmed_at',r.admin_call_confirmed_at,'admin_confirmation_notes',case when v_admin then r.admin_confirmation_notes else null end,'expires_at',r.expires_at,'revoked_at',r.revoked_at)
 from private.seller_access_requests r where v_admin or r.owner_user_id=v_user or r.target_user_id=v_user order by r.submitted_at desc;
end;$function$;

revoke all on function public.submit_seller_access_request(uuid,uuid,text[],text,text) from public,anon;
revoke all on function public.admin_review_seller_access_request(uuid,boolean,text,integer) from public,anon;
revoke all on function public.revoke_seller_access_request(uuid,text) from public,anon;
revoke all on function public.expire_seller_access_requests() from public,anon;
revoke all on function public.get_seller_access_requests() from public,anon;
grant execute on function public.submit_seller_access_request(uuid,uuid,text[],text,text) to authenticated;
grant execute on function public.admin_review_seller_access_request(uuid,boolean,text,integer) to authenticated;
grant execute on function public.revoke_seller_access_request(uuid,text) to authenticated;
grant execute on function public.expire_seller_access_requests() to authenticated;
grant execute on function public.get_seller_access_requests() to authenticated;
