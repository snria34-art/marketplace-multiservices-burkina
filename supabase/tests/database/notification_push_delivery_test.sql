begin;
select plan(6);

select has_table(
  'public',
  'notification_push_deliveries',
  'per-device push delivery state table exists'
);
select has_column(
  'public',
  'notification_push_deliveries',
  'notification_id',
  'delivery rows reference a notification'
);
select has_column(
  'public',
  'notification_push_deliveries',
  'device_id',
  'delivery rows reference a registered device'
);
select has_index(
  'public',
  'notification_push_deliveries',
  'notification_push_deliveries_notification_device_key',
  'one delivery state exists per notification and device'
);
select ok(
  not has_table_privilege('anon', 'public.notification_push_deliveries', 'SELECT')
  and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'SELECT'),
  'push delivery internals are not readable by client roles'
);
select ok(
  not has_table_privilege('anon', 'public.notification_push_deliveries', 'INSERT')
  and not has_table_privilege('authenticated', 'public.notification_push_deliveries', 'INSERT'),
  'push delivery internals are not writable by client roles'
);

select * from finish();
rollback;
