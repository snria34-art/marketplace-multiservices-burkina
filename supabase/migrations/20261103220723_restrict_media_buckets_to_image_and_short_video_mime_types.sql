update storage.buckets
set allowed_mime_types = case
  when id='product-media' then array['image/jpeg','image/png','image/webp','image/heic']::text[]
  when id='order-feedback-media' then array['image/jpeg','image/png','image/webp','image/heic','video/mp4','video/quicktime']::text[]
  else allowed_mime_types
end
where id in ('product-media','order-feedback-media');