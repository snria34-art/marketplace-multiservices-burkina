-- Disable shared financial visibility until financial records are isolated per shop.
-- Preserve the seller-owner and admin read policies.

drop policy if exists commissions_shared_access_read on public.commissions;
drop policy if exists seller_ledger_shared_access_read on public.seller_ledger;
drop policy if exists seller_payouts_shared_access_read on public.seller_payouts;
