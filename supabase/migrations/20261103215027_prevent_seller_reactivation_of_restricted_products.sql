create or replace function private.prevent_reactivation_of_restricted_product()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if new.status='ACTIVE' and old.status is distinct from new.status
     and exists(
       select 1 from private.product_listing_restrictions r
       where r.product_id=new.id and r.active=true
     ) then
    raise exception 'product_listing_restricted_pending_admin_clear';
  end if;
  return new;
end;
$$;
revoke all on function private.prevent_reactivation_of_restricted_product() from public,anon,authenticated;

drop trigger if exists prevent_reactivation_of_restricted_product on public.products;
create trigger prevent_reactivation_of_restricted_product
before update of status on public.products
for each row
execute function private.prevent_reactivation_of_restricted_product();