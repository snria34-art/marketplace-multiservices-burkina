update private.catalog_moderation_findings f
set product_content_hash=md5(lower(coalesce(p.name,'') || ' ' || coalesce(p.description,'')))
from public.products p
where p.id=f.product_id and f.product_content_hash is null;