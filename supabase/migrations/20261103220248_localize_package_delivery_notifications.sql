create or replace function private.notify_package_status()
returns trigger language plpgsql security definer set search_path='pg_catalog','public' as $$
declare v_customer uuid; v_title text; v_body text;
begin
  if tg_op='UPDATE' and old.status is not distinct from new.status then return new; end if;
  select o.customer_id into v_customer
  from public.order_groups og join public.orders o on o.id=og.order_id
  where og.id=new.order_group_id;
  if v_customer is null then return new; end if;
  v_title := case new.status::text
    when 'CREATED' then 'Colis enregistré'
    when 'READY_FOR_PICKUP' then 'Colis prêt chez le vendeur'
    when 'ASSIGNED' then 'Livreur affecté'
    when 'ACCEPTED' then 'Livreur confirmé'
    when 'PICKED_UP' then 'Colis récupéré'
    when 'IN_TRANSIT' then 'Colis en cours de livraison'
    when 'DELIVERED' then 'Colis livré'
    when 'RETURNED' then 'Colis retourné'
    when 'DAMAGED' then 'Problème sur le colis'
    when 'LOST' then 'Colis introuvable'
    when 'CANCELLED' then 'Livraison annulée'
    else 'Mise à jour de la livraison'
  end;
  v_body := case new.status::text
    when 'CREATED' then 'Votre colis a été enregistré.'
    when 'READY_FOR_PICKUP' then 'Votre colis est prêt à être récupéré chez le vendeur.'
    when 'ASSIGNED' then 'Un livreur a été affecté à votre colis.'
    when 'ACCEPTED' then 'Le livreur a accepté la prise en charge de votre colis.'
    when 'PICKED_UP' then 'Le livreur a récupéré votre colis chez le vendeur.'
    when 'IN_TRANSIT' then 'Votre colis est en cours de livraison.'
    when 'DELIVERED' then 'Votre colis a été livré. Vous pouvez consulter la preuve de livraison et noter votre article.'
    when 'RETURNED' then 'Votre colis a été retourné.'
    when 'DAMAGED' then 'Un problème a été signalé sur votre colis. Consultez le suivi ou contactez le support.'
    when 'LOST' then 'Un problème de localisation a été signalé pour votre colis. Contactez le support.'
    when 'CANCELLED' then 'La livraison de votre colis a été annulée.'
    else 'Le statut de votre colis a changé.'
  end;
  insert into public.notifications(user_id,type,title,body,data)
  values(v_customer,'delivery_update',v_title,v_body,
    jsonb_build_object('package_id',new.id::text,'type','delivery_update','status',new.status::text));
  return new;
exception when others then return new;
end;
$$;