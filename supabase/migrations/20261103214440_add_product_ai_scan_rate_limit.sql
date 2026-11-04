
create table if not exists private.catalog_ai_product_scan_locks (
  product_id uuid primary key references public.products(id) on delete cascade,
  locked_until timestamptz not null,
  requested_at timestamptz not null default now()
);
alter table private.catalog_ai_product_scan_locks enable row level security;
revoke all on private.catalog_ai_product_scan_locks from public,anon,authenticated;

create or replace function private.claim_ai_product_scan(p_product_id uuid)
returns boolean
language plpgsql
security definer
set search_path=''
as $$
declare v_claimed integer;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role_required'; end if;
  if exists(
    select 1 from private.catalog_ai_product_scans
    where product_id=p_product_id and scanned_at > now()-interval '10 minutes'
  ) then return false; end if;
  insert into private.catalog_ai_product_scan_locks(product_id,locked_until,requested_at)
  values(p_product_id,now()+interval '5 minutes',now())
  on conflict(product_id) do update
    set locked_until=excluded.locked_until,requested_at=excluded.requested_at
    where private.catalog_ai_product_scan_locks.locked_until < now();
  get diagnostics v_claimed = row_count;
  return v_claimed > 0;
end;
$$;
revoke all on function private.claim_ai_product_scan(uuid) from public,anon,authenticated;
grant execute on function private.claim_ai_product_scan(uuid) to service_role;

create or replace function public.claim_ai_product_scan(p_product_id uuid)
returns boolean language sql security invoker set search_path='' as $$
  select private.claim_ai_product_scan(p_product_id);
$$;
revoke all on function public.claim_ai_product_scan(uuid) from public,anon,authenticated;
grant execute on function public.claim_ai_product_scan(uuid) to service_role;
