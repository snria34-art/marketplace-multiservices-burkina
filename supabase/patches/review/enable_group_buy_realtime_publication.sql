-- REVIEW PATCH ONLY — do not execute manually against production.
-- This publication entry is required for the customer group-buy page to receive
-- current_quantity changes through Supabase Postgres Changes / Realtime.
-- Before deployment, generate a numbered migration with:
--   supabase migration new enable_group_buy_realtime
-- Copy this guarded block into the generated migration, run the isolated
-- database tests, then apply only through the approved migration workflow.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'group_buys'
  ) then
    alter publication supabase_realtime add table public.group_buys;
  end if;
end
$$;
