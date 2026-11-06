do $policy$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='product_variant_inventory'
      and policyname='product_variant_inventory_deny_client_access'
  ) then
    create policy product_variant_inventory_deny_client_access
      on public.product_variant_inventory for all to anon, authenticated
      using (false) with check (false);
  end if;
end;
$policy$;