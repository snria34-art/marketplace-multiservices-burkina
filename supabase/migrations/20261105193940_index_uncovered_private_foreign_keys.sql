create index if not exists idx_platform_repair_backups_restored_by_fk
  on private.platform_repair_backups(restored_by);

create index if not exists idx_review_moderation_audit_actor_id_fk
  on private.review_moderation_audit(actor_id);

create index if not exists idx_seller_access_audit_actor_user_id_fk
  on private.seller_access_audit(actor_user_id);

create index if not exists idx_seller_access_requests_conversation_id_fk
  on private.seller_access_requests(conversation_id);

create index if not exists idx_seller_access_requests_initial_message_id_fk
  on private.seller_access_requests(initial_message_id);

create index if not exists idx_seller_access_requests_owner_shop_id_fk
  on private.seller_access_requests(owner_shop_id);

create index if not exists idx_seller_access_requests_reviewed_by_fk
  on private.seller_access_requests(reviewed_by);

create index if not exists idx_seller_access_requests_revoked_by_fk
  on private.seller_access_requests(revoked_by);
