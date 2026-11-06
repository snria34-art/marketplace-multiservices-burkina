create table if not exists private.review_moderation_audit (
  id uuid primary key default gen_random_uuid(),
  review_id uuid not null references public.reviews(id) on delete restrict,
  actor_id uuid not null references public.profiles(id) on delete restrict,
  decision text not null check (decision in ('PUBLISHED','HIDDEN')),
  note text not null,
  created_at timestamptz not null default now()
);
create index if not exists review_moderation_audit_review_idx
  on private.review_moderation_audit(review_id,created_at desc);
alter table private.review_moderation_audit enable row level security;
revoke all on private.review_moderation_audit from public,anon,authenticated;

create or replace function private.can_read_published_review_media(p_storage_path text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(
    select 1 from public.review_media rm
    join public.reviews r on r.id=rm.review_id
    where rm.storage_path=p_storage_path and r.status='PUBLISHED'::public.review_status
  );
$$;
revoke all on function private.can_read_published_review_media(text) from public;
grant execute on function private.can_read_published_review_media(text) to anon,authenticated;

drop policy if exists order_feedback_media_published_reviews_read on storage.objects;
create policy order_feedback_media_published_reviews_read on storage.objects
for select to anon,authenticated
using (bucket_id='order-feedback-media' and (select private.can_read_published_review_media(name)));

create or replace function private.get_public_review_media(p_review_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'storage_path',rm.storage_path,'media_type',rm.media_type,
    'duration_seconds',rm.duration_seconds,'created_at',rm.created_at
  ) order by rm.created_at),'[]'::jsonb)
  from public.review_media rm
  join public.reviews r on r.id=rm.review_id
  where rm.review_id=p_review_id and r.status='PUBLISHED'::public.review_status;
$$;
revoke all on function private.get_public_review_media(uuid) from public;
grant execute on function private.get_public_review_media(uuid) to anon,authenticated;

create or replace function public.get_public_review_media(p_review_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.get_public_review_media(p_review_id);
$$;
revoke all on function public.get_public_review_media(uuid) from public;
grant execute on function public.get_public_review_media(uuid) to anon,authenticated;

create or replace function private.admin_get_review_moderation_queue(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_result jsonb;
begin
  if auth.uid() is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at),'[]'::jsonb) into v_result
  from (
    select r.id as review_id,r.customer_id,r.product_id,r.shop_id,r.rating,r.body,r.status,r.created_at,
      p.name as product_name,sh.name as shop_name,pr.display_name as customer_name,
      coalesce((select jsonb_agg(jsonb_build_object(
        'storage_path',rm.storage_path,'media_type',rm.media_type,'duration_seconds',rm.duration_seconds
      ) order by rm.created_at)
      from public.review_media rm where rm.review_id=r.id),'[]'::jsonb) as media
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
revoke all on function private.admin_get_review_moderation_queue(integer) from public,anon;
grant execute on function private.admin_get_review_moderation_queue(integer) to authenticated;

create or replace function public.admin_get_review_moderation_queue(p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path='' as $$
  select private.admin_get_review_moderation_queue(p_limit);
$$;
revoke all on function public.admin_get_review_moderation_queue(integer) from public,anon;
grant execute on function public.admin_get_review_moderation_queue(integer) to authenticated;

create or replace function private.admin_decide_review(p_review_id uuid,p_decision text,p_note text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_uid uuid := (select auth.uid()); v_customer uuid; v_decision text := upper(trim(p_decision));
begin
  if v_uid is null or not private.is_active_account() or not public.is_admin_actor() then
    raise exception 'admin_access_required';
  end if;
  if v_decision not in ('PUBLISHED','HIDDEN') then raise exception 'invalid_review_decision'; end if;
  if length(trim(coalesce(p_note,'')))<3 or length(p_note)>1000 then raise exception 'review_decision_note_required'; end if;
  select customer_id into v_customer from public.reviews where id=p_review_id and status='PENDING'::public.review_status for update;
  if v_customer is null then raise exception 'pending_review_not_found'; end if;
  update public.reviews set status=v_decision::public.review_status where id=p_review_id;
  insert into private.review_moderation_audit(review_id,actor_id,decision,note)
  values(p_review_id,v_uid,v_decision,trim(p_note));
  insert into public.notifications(user_id,type,title,body,data)
  values(
    v_customer,'REVIEW_MODERATION',
    case when v_decision='PUBLISHED' then 'Votre avis est publié' else 'Votre avis n’a pas été publié' end,
    trim(p_note),
    jsonb_build_object('review_id',p_review_id,'decision',v_decision)
  );
  return true;
end;
$$;
revoke all on function private.admin_decide_review(uuid,text,text) from public,anon;
grant execute on function private.admin_decide_review(uuid,text,text) to authenticated;

create or replace function public.admin_decide_review(p_review_id uuid,p_decision text,p_note text)
returns boolean language sql security invoker set search_path='' as $$
  select private.admin_decide_review(p_review_id,p_decision,p_note);
$$;
revoke all on function public.admin_decide_review(uuid,text,text) from public,anon;
grant execute on function public.admin_decide_review(uuid,text,text) to authenticated;