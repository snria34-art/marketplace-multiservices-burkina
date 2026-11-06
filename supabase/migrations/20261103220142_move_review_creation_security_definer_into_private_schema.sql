alter function public.create_review(uuid,uuid,integer,text,text[]) set schema private;
revoke all on function private.create_review(uuid,uuid,integer,text,text[]) from public,anon;
grant execute on function private.create_review(uuid,uuid,integer,text,text[]) to authenticated;

create or replace function public.create_review(
  p_product_id uuid,p_shop_id uuid,p_rating integer,p_body text default null,
  p_issue_codes text[] default '{}'::text[]
) returns uuid
language sql security invoker set search_path='' as $$
  select private.create_review(p_product_id,p_shop_id,p_rating,p_body,p_issue_codes);
$$;
revoke all on function public.create_review(uuid,uuid,integer,text,text[]) from public,anon;
grant execute on function public.create_review(uuid,uuid,integer,text,text[]) to authenticated;