begin;

-- Durable per-device push state: a partial send must not mark the whole
-- notification complete or cause already successful devices to receive
-- duplicates on the next scheduled dispatch.
create table if not exists public.notification_push_deliveries (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  device_id uuid not null references public.notification_devices(id) on delete cascade,
  status text not null default 'PENDING'
    check (status in ('PENDING','SENT','INVALID')),
  last_attempt_at timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint notification_push_deliveries_notification_device_key
    unique (notification_id, device_id),
  constraint notification_push_deliveries_sent_state_check
    check ((status = 'SENT') = (sent_at is not null))
);

create index if not exists idx_notification_push_deliveries_pending
  on public.notification_push_deliveries(notification_id, status);

alter table public.notification_push_deliveries enable row level security;
revoke all on public.notification_push_deliveries from public, anon, authenticated;
grant all on public.notification_push_deliveries to service_role;

commit;
