-- Configure the existing financial finalizer's source of truth to 10%.
-- finalize_seller_group_financials reads this setting at settlement time.
-- This changes no existing commissions, ledger entries, orders, or payouts.
insert into public.platform_settings(key, value, updated_at)
values (
  'default_commission_rate',
  jsonb_build_object('rate', 10),
  now()
)
on conflict (key) do update
set value = jsonb_set(
      coalesce(public.platform_settings.value, '{}'::jsonb),
      '{rate}',
      '10'::jsonb,
      true
    ),
    updated_at = now();
