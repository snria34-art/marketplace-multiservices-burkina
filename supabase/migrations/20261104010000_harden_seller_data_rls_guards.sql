do $migration$
declare
  v_table text;
  v_tables text[] := array[
    'sellers','shops','products','inventory','inventory_movements',
    'seller_documents','seller_ledger','seller_payouts','commissions',
    'coupons','promotions','order_groups','order_items','orders',
    'conversations','conversation_members','messages',
    'cart_items','carts','shop_followers'
  ];
begin
  foreach v_table in array v_tables loop
    if exists (
      select 1 from pg_policies
      where schemaname='public'
        and tablename=v_table
        and policyname='active_account_guard'
    ) then
      execute format('drop policy active_account_guard on public.%I', v_table);
      execute format(
        'create policy active_account_guard on public.%I as restrictive for all to authenticated using ((select private.is_active_account())) with check ((select private.is_active_account()))',
        v_table
      );
    end if;
  end loop;
end;
$migration$;
