-- Safely cancel a seller order group before dispatch.
-- Release its reserved stock, cancel any pre-dispatch package/assignment,
-- and preserve the parent order's partial-fulfilment state.
create or replace function public.transition_order_group_status(
 p_order_group_id uuid,
 p_next_status public.order_status,
 p_note text default null
) returns public.order_status
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
 v_group public.order_groups%rowtype;
 v_order_id uuid;
 v_shop_owner uuid;
 v_user uuid := (select auth.uid());
 v_current public.order_status;
 v_item record;
 v_parent_status public.order_status;
begin
 perform private.require_active_account();
 if v_user is null then raise exception 'not_authenticated'; end if;
 if p_order_group_id is null or p_next_status is null then
   raise exception 'order_group_transition_invalid';
 end if;

 select og.order_id into v_order_id
 from public.order_groups og
 where og.id=p_order_group_id;
 if v_order_id is null then raise exception 'order_group_not_found'; end if;

 perform 1 from public.orders o where o.id=v_order_id for update;
 if not found then raise exception 'order_not_found'; end if;

 select * into v_group
 from public.order_groups
 where id=p_order_group_id
 for update;
 if not found then raise exception 'order_group_not_found'; end if;
 v_current := v_group.status;

 select s.user_id into v_shop_owner
 from public.shops sh
 join public.sellers s on s.id=sh.seller_id
 where sh.id=v_group.shop_id;

 if not (private.is_admin() or v_shop_owner=v_user) then
   raise exception 'not_authorized' using errcode='42501';
 end if;

 if p_next_status='CONFIRMED' and v_current<>'PAID' then raise exception 'invalid_group_transition'; end if;
 if p_next_status='PREPARING' and v_current<>'CONFIRMED' then raise exception 'invalid_group_transition'; end if;
 if p_next_status='READY_FOR_PICKUP' and v_current<>'PREPARING' then raise exception 'invalid_group_transition'; end if;
 if p_next_status='CANCELLED' and v_current not in ('PAID','CONFIRMED','PREPARING') then raise exception 'invalid_group_transition'; end if;
 if p_next_status not in ('CONFIRMED','PREPARING','READY_FOR_PICKUP','CANCELLED') then raise exception 'unsupported_seller_transition'; end if;

 if p_next_status='CANCELLED' then
   if exists (
     select 1 from public.order_packages op
     where op.order_group_id=p_order_group_id
       and op.status in ('PICKED_UP','IN_TRANSIT','DELIVERED','RETURNED','DAMAGED','LOST')
   ) then
     raise exception 'group_cancellation_after_dispatch_not_allowed';
   end if;

   if exists (
     select 1
     from public.order_packages op
     join public.package_inventory_consumptions pic on pic.package_id=op.id
     where op.order_group_id=p_order_group_id
   ) then
     raise exception 'group_inventory_already_consumed';
   end if;

   for v_item in
     select oi.product_id, oi.variant_id, sum(oi.quantity)::integer as quantity
     from public.order_items oi
     where oi.order_group_id=p_order_group_id
     group by oi.product_id, oi.variant_id
   loop
     if not public.release_variant_inventory(v_item.product_id,v_item.variant_id,v_item.quantity) then
       raise exception 'reserved_inventory_release_failed';
     end if;
   end loop;
 end if;

 update public.order_groups
 set status=p_next_status
 where id=p_order_group_id;

 if p_next_status='CANCELLED' then
   with cancelled_assignments as (
     update public.delivery_assignments da
     set status='CANCELLED'
     where da.package_id in (
       select op.id from public.order_packages op
       where op.order_group_id=p_order_group_id
     )
       and da.status in ('CREATED','ASSIGNED','ACCEPTED','READY_FOR_PICKUP')
     returning da.id
   )
   insert into public.delivery_assignment_events(assignment_id,actor_id,event_type,metadata)
   select id,v_user,'CANCELLED_BY_SELLER',
          jsonb_build_object('order_group_id',p_order_group_id,'reason',p_note)
   from cancelled_assignments;

   update public.order_packages
   set status='CANCELLED',updated_at=now()
   where order_group_id=p_order_group_id
     and status in ('CREATED','READY_FOR_PICKUP','ASSIGNED','ACCEPTED');

   if not exists (
     select 1 from public.order_groups og
     where og.order_id=v_group.order_id and og.status<>'CANCELLED'
   ) then
     v_parent_status := 'CANCELLED';
   else
     v_parent_status := 'PARTIALLY_FULFILLED';
   end if;

   update public.orders
   set status=v_parent_status,updated_at=now()
   where id=v_group.order_id;
 end if;

 insert into public.order_events(order_id,actor_id,status,metadata)
 values(v_group.order_id,v_user,p_next_status,
   jsonb_build_object('scope','order_group','order_group_id',p_order_group_id,'note',p_note));

 return p_next_status;
end;
$function$;

revoke all on function public.transition_order_group_status(uuid,public.order_status,text) from public,anon,authenticated;
grant execute on function public.transition_order_group_status(uuid,public.order_status,text) to service_role;
