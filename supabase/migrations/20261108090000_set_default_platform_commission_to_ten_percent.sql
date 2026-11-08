-- Establish the requested platform commission default for new settlements.
-- Existing financial rows are intentionally untouched.
insert into public.platform_settings(key, value)
values ('default_commission_rate', jsonb_build_object('rate', 10))
on conflict (key) do nothing;

-- Keep the legacy service-role finalizer's omitted argument aligned with the
-- platform default. Explicit rates remain available to trusted server callers.
create or replace function public.finalize_seller_group(
  p_order_group_id uuid,
  p_commission_rate numeric default 10
) returns boolean
language plpgsql
security definer
set search_path=pg_catalog,public
as $$
declare
 v_group public.order_groups%rowtype;
 v_seller_id uuid;
 v_commission numeric;
begin
 if p_commission_rate is null or p_commission_rate < 0 or p_commission_rate > 100 then
   raise exception 'commission_rate_invalid';
 end if;

 select * into v_group
 from public.order_groups
 where id=p_order_group_id
 for update;
 if not found then raise exception 'order_group_not_found'; end if;
 if v_group.status <> 'DELIVERED' then raise exception 'group_not_delivered'; end if;

 select s.id into v_seller_id
 from public.shops sh
 join public.sellers s on s.id=sh.seller_id
 where sh.id=v_group.shop_id;
 if v_seller_id is null then raise exception 'seller_not_found'; end if;

 v_commission := round(v_group.subtotal * p_commission_rate / 100, 2);

 insert into public.commissions(
   seller_id,order_group_id,rate,base_amount,commission_amount,currency,status
 )
 values(
   v_seller_id,p_order_group_id,p_commission_rate,v_group.subtotal,
   v_commission,'XOF','POSTED'
 )
 on conflict (order_group_id) do nothing;

 if found then
   insert into public.seller_ledger(
     seller_id,order_group_id,entry_type,amount,currency,reference_id
   )
   values(v_seller_id,p_order_group_id,'SALE',v_group.subtotal,'XOF',p_order_group_id);

   if v_commission > 0 then
     insert into public.seller_ledger(
       seller_id,order_group_id,entry_type,amount,currency,reference_id
     )
     values(v_seller_id,p_order_group_id,'COMMISSION',-v_commission,'XOF',p_order_group_id);
   end if;
 end if;

 return true;
end;
$$;

revoke all on function public.finalize_seller_group(uuid,numeric) from public,anon,authenticated;
grant execute on function public.finalize_seller_group(uuid,numeric) to service_role;
