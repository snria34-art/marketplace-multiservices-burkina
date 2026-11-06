create or replace function public.get_my_orders_with_completion(
  p_limit integer default 20,
  p_offset integer default 0
) returns table(
  order_id uuid,status public.order_status,total numeric,currency text,
  created_at timestamptz,completed_at timestamptz,review_deadline_at timestamptz
)
language sql stable security invoker set search_path='' as $$
  select o.id,o.status,o.total,o.currency::text,o.created_at,o.completed_at,o.review_deadline_at
  from public.orders o
  where o.customer_id=(select auth.uid())
  order by o.created_at desc
  limit greatest(1,least(coalesce(p_limit,20),100))
  offset greatest(0,coalesce(p_offset,0));
$$;
revoke all on function public.get_my_orders_with_completion(integer,integer) from public,anon;
grant execute on function public.get_my_orders_with_completion(integer,integer) to authenticated;