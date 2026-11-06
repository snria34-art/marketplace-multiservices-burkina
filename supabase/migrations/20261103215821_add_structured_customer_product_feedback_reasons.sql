alter table public.reviews
  add column if not exists issue_codes text[] not null default '{}'::text[];
do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.reviews'::regclass and conname='reviews_issue_codes_check') then
    alter table public.reviews add constraint reviews_issue_codes_check
    check (
      cardinality(issue_codes) <= 5
      and issue_codes <@ array[
        'NOT_AS_DESCRIBED','DAMAGED','WRONG_ITEM','MISSING_PARTS',
        'QUALITY_ISSUE','PACKAGING_ISSUE','OTHER'
      ]::text[]
    );
  end if;
end $$;

drop function if exists public.create_review(uuid,uuid,integer,text);

create or replace function public.create_review(
  p_product_id uuid,p_shop_id uuid,p_rating integer,p_body text default null,
  p_issue_codes text[] default '{}'::text[]
) returns uuid
language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_user uuid := (select auth.uid()); v_review uuid; v_issue_codes text[] := coalesce(p_issue_codes,'{}'::text[]);
begin
  perform private.require_active_account();
  if v_user is null then raise exception 'not_authenticated'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;
  if length(coalesce(p_body,'')) > 2000 then raise exception 'review_too_long'; end if;
  if cardinality(v_issue_codes)>5 or not (
    v_issue_codes <@ array[
      'NOT_AS_DESCRIBED','DAMAGED','WRONG_ITEM','MISSING_PARTS',
      'QUALITY_ISSUE','PACKAGING_ISSUE','OTHER'
    ]::text[]
  ) then raise exception 'invalid_review_issue_codes'; end if;
  if not exists (
    select 1
    from public.order_items oi
    join public.order_groups og on og.id=oi.order_group_id
    join public.orders o on o.id=og.order_id
    where o.customer_id=v_user and og.status='DELIVERED'
      and oi.product_id=p_product_id and og.shop_id=p_shop_id
  ) then raise exception 'product_not_delivered_to_customer'; end if;
  insert into public.reviews(customer_id,product_id,shop_id,rating,body,status,issue_codes)
  values(v_user,p_product_id,p_shop_id,p_rating,nullif(trim(p_body),''),'PENDING',v_issue_codes)
  returning id into v_review;
  return v_review;
exception when unique_violation then raise exception 'review_already_exists';
end;
$$;

create or replace function private.admin_get_review_moderation_queue(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at),'[]'::jsonb) into v_result
  from (
    select r.id as review_id,r.customer_id,r.product_id,r.shop_id,r.rating,r.body,r.status,r.created_at,r.issue_codes,
      p.name as product_name,sh.name as shop_name,pr.display_name as customer_name,
      coalesce((select jsonb_agg(jsonb_build_object(
        'storage_path',rm.storage_path,'media_type',rm.media_type,'duration_seconds',rm.duration_seconds
      ) order by rm.created_at) from public.review_media rm where rm.review_id=r.id),'[]'::jsonb) as media
    from public.reviews r
    left join public.products p on p.id=r.product_id
    left join public.shops sh on sh.id=r.shop_id
    left join public.profiles pr on pr.id=r.customer_id
    where r.status='PENDING'::public.review_status
    order by r.created_at
    limit greatest(1,least(coalesce(p_limit,50),100))
  ) q;
  return v_result;
end;
$$;