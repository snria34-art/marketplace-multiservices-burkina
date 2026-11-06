create table if not exists private.return_policy_audit (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null,
  previous_window_hours integer,
  new_window_hours integer not null check (new_window_hours in (24,48,72)),
  actor_id uuid not null,
  created_at timestamptz not null default now()
);
alter table private.return_policy_audit enable row level security;
revoke all on private.return_policy_audit from public,anon,authenticated;

create or replace function private.admin_set_return_window(p_category_id uuid,p_hours integer)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_actor uuid := (select auth.uid()); v_category uuid; v_previous integer;
begin
  if v_actor is null or not private.is_active_account() or not public.is_admin_actor() then raise exception 'admin_access_required'; end if;
  if p_hours not in (24,48,72) then raise exception 'return_window_must_be_24_48_or_72_hours'; end if;
  v_category := coalesce(p_category_id,'00000000-0000-0000-0000-000000000000'::uuid);
  select return_window_hours into v_previous from private.return_policy_rules where category_id=v_category for update;
  insert into private.return_policy_rules(category_id,return_window_hours,updated_at,updated_by)
  values(v_category,p_hours,now(),v_actor)
  on conflict(category_id) do update set return_window_hours=excluded.return_window_hours,updated_at=now(),updated_by=v_actor;
  insert into private.return_policy_audit(category_id,previous_window_hours,new_window_hours,actor_id)
  values(v_category,v_previous,p_hours,v_actor);
  return true;
end;
$$;
revoke all on function private.admin_set_return_window(uuid,integer) from public,anon,authenticated;
create or replace function public.admin_set_return_window(p_category_id uuid,p_hours integer)
returns boolean language sql security invoker set search_path='' as $$
  select private.admin_set_return_window(p_category_id,p_hours);
$$;
revoke all on function public.admin_set_return_window(uuid,integer) from public,anon;
grant execute on function public.admin_set_return_window(uuid,integer) to authenticated;

with delivered_orders as (
  select og.order_id,max(op.delivered_at) as latest_delivery
  from public.order_groups og join public.order_packages op on op.order_group_id=og.id
  group by og.order_id
  having count(*)>0 and count(*)=count(*) filter(where op.status::text='DELIVERED') and max(op.delivered_at) is not null
)
update public.orders o
set review_deadline_at=d.latest_delivery + interval '7 days',
    completed_at=case when d.latest_delivery + interval '7 days'<=now() then d.latest_delivery + interval '7 days' else null end,
    updated_at=now()
from delivered_orders d where o.id=d.order_id and o.review_deadline_at is null;