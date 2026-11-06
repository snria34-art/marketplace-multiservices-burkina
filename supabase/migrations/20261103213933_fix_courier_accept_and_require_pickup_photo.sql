alter type public.delivery_status add value if not exists 'ACCEPTED' before 'PICKED_UP';
create or replace function public.confirm_package_pickup(p_package_id uuid, p_pickup_code text)
returns uuid
language plpgsql
security definer
set search_path='pg_catalog','public'
as $$
declare
 v_assignment public.delivery_assignments%rowtype;
 v_package public.order_packages%rowtype;
begin
 perform private.require_active_account();
 if not private.has_role('COURIER'::public.user_role) then
   raise exception 'courier_role_required' using errcode='42501';
 end if;
 if p_pickup_code is null or length(trim(p_pickup_code)) < 4 then raise exception 'pickup_code_required'; end if;
 select * into v_assignment from public.delivery_assignments
 where package_id=p_package_id and courier_id=(select auth.uid()) and status='ACCEPTED' for update;
 if not found then raise exception 'assignment_not_found'; end if;
 select * into v_package from public.order_packages where id=p_package_id for update;
 if not found then raise exception 'package_not_found'; end if;
 if v_package.status <> 'READY_FOR_PICKUP' then raise exception 'package_not_ready'; end if;
 if v_package.pickup_code_hash is null or encode(digest(trim(p_pickup_code),'sha256'),'hex') <> v_package.pickup_code_hash then
   raise exception 'pickup_code_invalid';
 end if;
 if not exists (
   select 1 from public.delivery_evidence de
   where de.package_id=p_package_id and de.assignment_id=v_assignment.id
     and de.courier_id=(select auth.uid()) and de.evidence_type='PICKUP'
 ) then raise exception 'pickup_photo_required'; end if;
 perform public.consume_package_inventory(p_package_id);
 update public.order_packages set status='PICKED_UP',picked_up_at=now(),updated_at=now()
 where id=p_package_id;
 update public.delivery_assignments set status='PICKED_UP',accepted_at=coalesce(accepted_at,now())
 where id=v_assignment.id;
 insert into public.delivery_assignment_events(assignment_id,actor_id,event_type,metadata)
 values(v_assignment.id,(select auth.uid()),'PACKAGE_PICKED_UP',jsonb_build_object('package_id',p_package_id));
 return v_assignment.id;
end;
$$;
