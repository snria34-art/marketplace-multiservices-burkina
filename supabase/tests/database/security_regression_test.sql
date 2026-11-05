begin;
select plan(12);

select ok(
  not has_table_privilege('anon','private.catalog_moderation_findings','SELECT')
  and not has_table_privilege('authenticated','private.catalog_moderation_findings','SELECT'),
  'catalog moderation findings are not directly readable by API client roles'
);

select ok(
  not has_table_privilege('anon','private.platform_agent_runs','SELECT')
  and not has_table_privilege('authenticated','private.platform_agent_runs','SELECT'),
  'platform agent run logs are not directly readable by API client roles'
);

select ok(
  not has_table_privilege('anon','private.seller_access_requests','SELECT')
  and not has_table_privilege('authenticated','private.seller_access_requests','SELECT'),
  'seller access requests are not directly readable by API client roles'
);

select ok(
  not has_table_privilege('anon','public.delivery_evidence','SELECT')
  and not has_table_privilege('authenticated','public.delivery_evidence','SELECT'),
  'delivery evidence is not directly readable by API client roles'
);

select ok(
  not has_function_privilege('anon','private.notify_mechanic_request()','EXECUTE')
  and not has_function_privilege('authenticated','private.notify_mechanic_request()','EXECUTE'),
  'mechanic notification trigger cannot be called directly by clients'
);

select ok(
  not has_function_privilege('anon','private.trigger_push_notification()','EXECUTE')
  and not has_function_privilege('authenticated','private.trigger_push_notification()','EXECUTE'),
  'push notification trigger cannot be called directly by clients'
);

select ok(
  not has_function_privilege('anon','public.claim_notification_for_push(uuid)','EXECUTE')
  and not has_function_privilege('authenticated','public.claim_notification_for_push(uuid)','EXECUTE'),
  'push queue claim is not executable by client roles'
);

select ok(
  has_function_privilege('service_role','public.claim_notification_for_push(uuid)','EXECUTE'),
  'push queue claim is executable by the trusted service role'
);

select ok(
  not has_function_privilege('anon','public.admin_send_test_notification(text,text)','EXECUTE')
  and has_function_privilege('authenticated','public.admin_send_test_notification(text,text)','EXECUTE'),
  'admin push test RPC is signed-in only and enforces admin authorization internally'
);

select ok(
  not has_function_privilege('anon','public.deactivate_notification_device(text)','EXECUTE')
  and has_function_privilege('authenticated','public.deactivate_notification_device(text)','EXECUTE'),
  'device deactivation RPC is signed-in only'
);

select ok(
  not has_function_privilege('anon','public.register_notification_device(text,text)','EXECUTE')
  and has_function_privilege('authenticated','public.register_notification_device(text,text)','EXECUTE'),
  'device registration RPC is signed-in only'
);

select ok(
  not has_function_privilege('anon','public.verify_push_dispatch_secret(text)','EXECUTE')
  and not has_function_privilege('authenticated','public.verify_push_dispatch_secret(text)','EXECUTE')
  and has_function_privilege('service_role','public.verify_push_dispatch_secret(text)','EXECUTE'),
  'push dispatch secret verification is service-role only'
);

select * from finish();
rollback;
