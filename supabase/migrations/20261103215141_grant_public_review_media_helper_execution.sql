grant usage on schema private to anon;
grant execute on function private.get_public_review_media(uuid) to anon,authenticated;
grant execute on function private.can_read_published_review_media(text) to anon,authenticated;