alter table public.orders
  add column if not exists review_deadline_at timestamptz,
  add column if not exists completed_at timestamptz;

create table if not exists private.return_policy_rules (
  category_id uuid primary key,
  return_window_hours integer not null check (return_window_hours in (24,48,72)),
  updated_at timestamptz not null default now(),
  updated_by uuid
);
alter table private.return_policy_rules enable row level security;
revoke all on private.return_policy_rules from public,anon,authenticated;

insert into private.return_policy_rules(category_id,return_window_hours)
values ('00000000-0000-0000-0000-000000000000',72)
on conflict(category_id) do nothing;

create or replace function private.set_order_review_deadline_after_delivery()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_order_id uuid; v_total integer; v_delivered integer; v_latest_delivery timestamptz;
begin
  if new.status::text <> 'DELIVERED'
     or (tg_op='UPDATE' and old.status is not distinct from new.status) then return new; end if;
  select og.order_id into v_order_id from public.order_groups og where og.id=new.order_group_id;
  if v_order_id is null then return new; end if;
  select count(*),count(*) filter(where op.status::text='DELIVERED'),max(op.delivered_at)
    into v_total,v_delivered,v_latest_delivery
  from public.order_packages op join public.order_groups og on og.id=op.order_group_id
  where og.order_id=v_order_id;
  if v_total>0 and v_total=v_delivered and v_latest_delivery is not null then
    update public.orders set review_deadline_at=v_latest_delivery + interval '7 days',
      completed_at=null,updated_at=now() where id=v_order_id;
  end if;
  return new;
end;
$$;
revoke all on function private.set_order_review_deadline_after_delivery() from public,anon,authenticated;
drop trigger if exists set_order_review_deadline_after_delivery on public.order_packages;
create trigger set_order_review_deadline_after_delivery
after insert or update of status,delivered_at on public.order_packages
for each row execute function private.set_order_review_deadline_after_delivery();

create or replace function private.expire_order_review_windows()
returns integer language plpgsql security definer set search_path='' as $$
declare v_count integer;
begin
  update public.orders set completed_at=review_deadline_at,updated_at=now()
  where review_deadline_at is not null and review_deadline_at<=now()
    and completed_at is null and status='DELIVERED';
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;
revoke all on function private.expire_order_review_windows() from public,anon,authenticated;
select cron.unschedule(jobid) from cron.job where jobname='complete-orders-after-review-window';
select cron.schedule('complete-orders-after-review-window','*/5 * * * *',
  $job$select private.expire_order_review_windows();$job$);

create or replace function public.open_return(p_order_id uuid,p_order_item_id uuid,p_reason text)
returns uuid language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_user uuid := (select auth.uid()); v_id uuid; v_category_id uuid; v_delivered_at timestamptz; v_window integer;
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if nullif(trim(p_reason),'') is null then raise exception 'reason_required'; end if;
  if not exists(select 1 from public.orders where id=p_order_id and customer_id=v_user) then raise exception 'order_not_owned'; end if;
  select p.category_id,op.delivered_at into v_category_id,v_delivered_at
  from public.order_items oi join public.order_groups og on og.id=oi.order_group_id
  join public.order_packages op on op.order_group_id=og.id
  join public.products p on p.id=oi.product_id
  where oi.id=p_order_item_id and og.order_id=p_order_id
    and op.status::text='DELIVERED' and op.delivered_at is not null
  order by op.delivered_at desc limit 1;
  if v_delivered_at is null then raise exception 'delivered_item_not_found'; end if;
  select coalesce(
    (select r.return_window_hours from private.return_policy_rules r where r.category_id=v_category_id),
    (select r.return_window_hours from private.return_policy_rules r where r.category_id='00000000-0000-0000-0000-000000000000'::uuid),72
  ) into v_window;
  if now()>v_delivered_at + make_interval(hours=>v_window) then raise exception 'standard_return_window_expired'; end if;
  if exists(select 1 from public.returns where order_id=p_order_id
    and coalesce(order_item_id,'00000000-0000-0000-0000-000000000000')=coalesce(p_order_item_id,'00000000-0000-0000-0000-000000000000')
    and status not in ('REJECTED','CANCELLED','COMPLETED')) then raise exception 'return_already_open'; end if;
  insert into public.returns(order_id,order_item_id,customer_id,reason,status)
  values(p_order_id,p_order_item_id,v_user,trim(p_reason),'REQUESTED') returning id into v_id;
  insert into public.return_events(return_id,actor_id,event_type,metadata)
  values(v_id,v_user,'REQUESTED',jsonb_build_object('reason',trim(p_reason),'return_window_hours',v_window));
  return v_id;
end;
$$;

create or replace function private.create_review(p_product_id uuid,p_shop_id uuid,p_rating integer,
  p_body text default null,p_issue_codes text[] default '{}'::text[])
returns uuid language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_user uuid := (select auth.uid()); v_review uuid; v_issue_codes text[] := coalesce(p_issue_codes,'{}'::text[]);
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_rating is null or p_rating<1 or p_rating>5 then raise exception 'invalid_rating'; end if;
  if length(coalesce(p_body,''))>2000 then raise exception 'review_too_long'; end if;
  if cardinality(v_issue_codes)>5 or not (v_issue_codes <@ array[
    'NOT_AS_DESCRIBED','DAMAGED','WRONG_ITEM','MISSING_PARTS','QUALITY_ISSUE','PACKAGING_ISSUE','OTHER'
  ]::text[]) then raise exception 'invalid_review_issue_codes'; end if;
  if not exists(
    select 1 from public.order_items oi
    join public.order_groups og on og.id=oi.order_group_id
    join public.orders o on o.id=og.order_id
    join public.order_packages op on op.order_group_id=og.id
    where o.customer_id=v_user and o.review_deadline_at is not null
      and now()<=o.review_deadline_at and op.status::text='DELIVERED'
      and op.delivered_at is not null and op.delivered_at>=now()-interval '7 days'
      and oi.product_id=p_product_id and og.shop_id=p_shop_id
  ) then raise exception 'review_window_expired_or_product_not_delivered'; end if;
  insert into public.reviews(customer_id,product_id,shop_id,rating,body,status,issue_codes)
  values(v_user,p_product_id,p_shop_id,p_rating,nullif(trim(p_body),''),'PENDING',v_issue_codes)
  returning id into v_review;
  return v_review;
exception when unique_violation then raise exception 'review_already_exists';
end;
$$;
revoke all on function private.create_review(uuid,uuid,integer,text,text[]) from public,anon;
grant execute on function private.create_review(uuid,uuid,integer,text,text[]) to authenticated;
create or replace function public.create_review(p_product_id uuid,p_shop_id uuid,p_rating integer,
  p_body text default null,p_issue_codes text[] default '{}'::text[])
returns uuid language sql security invoker set search_path='' as $$
  select private.create_review(p_product_id,p_shop_id,p_rating,p_body,p_issue_codes);
$$;
revoke all on function public.create_review(uuid,uuid,integer,text,text[]) from public,anon;
grant execute on function public.create_review(uuid,uuid,integer,text,text[]) to authenticated;