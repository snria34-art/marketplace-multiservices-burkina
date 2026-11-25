-- Return closure workflow: admin-only state transitions, audit events and verified refund linkage.
begin;

alter table public.returns
  add column if not exists refund_id uuid references public.refunds(id);

create index if not exists returns_refund_id_idx
  on public.returns(refund_id)
  where refund_id is not null;

-- Keep the request RPC's delivery-window and ownership checks, but use the
-- statuses actually permitted by public.returns and serialize duplicate checks.
create or replace function public.open_return(
  p_order_id uuid,
  p_order_item_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_category_id uuid;
  v_delivered_at timestamptz;
  v_window integer;
  v_item_key text := coalesce(p_order_item_id::text, '00000000-0000-0000-0000-000000000000');
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_order_id is null then raise exception 'order_id_required'; end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason_required'; end if;
  if length(trim(p_reason)) > 2000 then raise exception 'reason_too_long'; end if;

  if not exists (
    select 1 from public.orders
    where id = p_order_id and customer_id = v_user
  ) then
    raise exception 'order_not_owned';
  end if;

  -- Prevent two concurrent requests for the same order/item from both passing
  -- the active-return check.
  perform pg_advisory_xact_lock(
    hashtextextended(p_order_id::text || ':' || v_item_key, 0)
  );

  select p.category_id, op.delivered_at
    into v_category_id, v_delivered_at
  from public.order_items oi
  join public.order_groups og on og.id = oi.order_group_id
  join public.order_packages op on op.order_group_id = og.id
  join public.products p on p.id = oi.product_id
  where oi.id = p_order_item_id
    and og.order_id = p_order_id
    and op.status::text = 'DELIVERED'
    and op.delivered_at is not null
  order by op.delivered_at desc
  limit 1;

  if v_delivered_at is null then
    raise exception 'delivered_item_not_found';
  end if;

  select coalesce(
    (select r.return_window_hours
       from private.return_policy_rules r
      where r.category_id = v_category_id),
    (select r.return_window_hours
       from private.return_policy_rules r
      where r.category_id = '00000000-0000-0000-0000-000000000000'::uuid),
    72
  ) into v_window;

  if now() > v_delivered_at + make_interval(hours => v_window) then
    raise exception 'standard_return_window_expired';
  end if;

  if exists (
    select 1
    from public.returns r
    where r.order_id = p_order_id
      and coalesce(r.order_item_id::text, '00000000-0000-0000-0000-000000000000') = v_item_key
      and r.status not in ('REJECTED', 'CLOSED', 'REFUNDED')
  ) then
    raise exception 'return_already_open';
  end if;

  insert into public.returns(order_id, order_item_id, customer_id, reason, status)
  values (p_order_id, p_order_item_id, v_user, trim(p_reason), 'REQUESTED')
  returning id into v_id;

  insert into public.return_events(return_id, actor_id, event_type, metadata)
  values (
    v_id, v_user, 'REQUESTED',
    jsonb_build_object('reason', trim(p_reason), 'return_window_hours', v_window)
  );
  return v_id;
end;
$function$;

revoke all on function public.open_return(uuid, uuid, text) from public, anon;
grant execute on function public.open_return(uuid, uuid, text) to authenticated;

create or replace function public.admin_list_returns()
returns table (
  return_id uuid,
  order_id uuid,
  order_item_id uuid,
  customer_id uuid,
  reason text,
  return_status text,
  resolution text,
  refund_id uuid,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;

  return query
  select r.id, r.order_id, r.order_item_id, r.customer_id, r.reason,
         r.status, r.resolution, r.refund_id, r.created_at, r.updated_at
  from public.returns r
  order by
    case when r.status = 'REQUESTED' then 0
         when r.status in ('APPROVED','PICKUP','RECEIVED') then 1
         else 2 end,
    r.created_at desc;
end;
$function$;

revoke all on function public.admin_list_returns() from public, anon;
grant execute on function public.admin_list_returns() to authenticated;

create or replace function public.admin_transition_return(
  p_return_id uuid,
  p_new_status text,
  p_resolution text default null,
  p_refund_id uuid default null,
  p_note text default null
)
returns public.returns
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_return public.returns%rowtype;
  v_resolution text;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_refund_order_id uuid;
  v_refund_status text;
  v_previous_status text;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'admin_access_required' using errcode = '42501';
  end if;
  if p_return_id is null or p_new_status is null then
    raise exception 'return_and_status_required';
  end if;
  if p_new_status not in ('APPROVED','REJECTED','PICKUP','RECEIVED','REFUNDED','CLOSED') then
    raise exception 'invalid_return_status';
  end if;
  if p_resolution is not null and p_resolution not in ('REFUND','REPLACEMENT','CREDIT') then
    raise exception 'invalid_return_resolution';
  end if;

  select r.* into v_return
  from public.returns r
  where r.id = p_return_id
  for update;
  if not found then raise exception 'return_not_found'; end if;

  v_previous_status := v_return.status;
  v_resolution := coalesce(p_resolution, v_return.resolution);

  if not (
    (v_return.status = 'REQUESTED' and p_new_status in ('APPROVED','REJECTED'))
    or (v_return.status = 'APPROVED' and p_new_status = 'PICKUP')
    or (v_return.status = 'PICKUP' and p_new_status = 'RECEIVED')
    or (v_return.status = 'RECEIVED' and p_new_status in ('REFUNDED','CLOSED'))
    or (v_return.status = 'REFUNDED' and p_new_status = 'CLOSED')
  ) then
    raise exception 'invalid_return_transition:%->%', v_return.status, p_new_status;
  end if;

  if p_new_status = 'APPROVED' and v_resolution is null then
    raise exception 'resolution_required_for_approval';
  end if;

  if p_new_status = 'CLOSED' then
    if v_resolution not in ('REPLACEMENT','CREDIT') and v_return.status <> 'REFUNDED' then
      raise exception 'closure_requires_replacement_credit_or_completed_refund';
    end if;
    if v_return.status = 'RECEIVED' and v_note is null then
      raise exception 'closure_confirmation_note_required';
    end if;
  end if;

  if p_new_status = 'REFUNDED' or v_return.status = 'REFUNDED' then
    if p_refund_id is not null then
      v_return.refund_id := p_refund_id;
    end if;
    if v_return.refund_id is null then
      raise exception 'completed_refund_link_required';
    end if;

    select rf.order_id, rf.status
      into v_refund_order_id, v_refund_status
    from public.refunds rf
    where rf.id = v_return.refund_id
    for update;

    if not found or v_refund_order_id <> v_return.order_id then
      raise exception 'refund_not_found_or_order_mismatch';
    end if;
    if v_refund_status <> 'COMPLETED' then
      raise exception 'refund_must_be_completed';
    end if;

    if v_return.order_item_id is not null then
      if not exists (
        select 1
        from public.refund_allocations ra
        where ra.refund_id = v_return.refund_id
          and ra.order_item_id = v_return.order_item_id
          and ra.allocation_type = 'ITEM'
          and ra.customer_amount > 0
      ) then
        raise exception 'refund_allocation_does_not_cover_return_item';
      end if;
    elsif not exists (
      select 1
      from public.refund_allocations ra
      where ra.refund_id = v_return.refund_id
        and ra.customer_amount > 0
    ) then
      raise exception 'refund_allocation_required';
    end if;
  end if;

  update public.returns r
  set status = p_new_status,
      resolution = v_resolution,
      refund_id = case
        when p_new_status = 'REFUNDED' or v_return.status = 'REFUNDED'
          then v_return.refund_id
        else r.refund_id
      end,
      updated_at = now()
  where r.id = p_return_id
  returning r.* into v_return;

  insert into public.return_events(return_id, actor_id, event_type, metadata)
  values (
    v_return.id,
    auth.uid(),
    p_new_status,
    jsonb_build_object(
      'previous_status', v_previous_status,
      'resolution', v_resolution,
      'refund_id', v_return.refund_id,
      'note', v_note
    )
  );

  return v_return;
end;
$function$;

revoke all on function public.admin_transition_return(uuid, text, text, uuid, text) from public, anon;
grant execute on function public.admin_transition_return(uuid, text, text, uuid, text) to authenticated;

commit;
