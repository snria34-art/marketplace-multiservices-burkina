# AUD-24 — Cohérence du statut terminal des affectations de livraison

**Date de constat :** 15 novembre 2026  
**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Sévérité :** P1 — parcours de livraison / confirmation client  
**Statut :** correction versionnée dans `20261115191336_phase1_commerce_integrity_final.sql` ; tests SQL locaux à exécuter sur le nouveau commit. Aucune base Supabase hébergée modifiée.

## 1. Constat

La migration initiale déclare :

```sql
create type public.delivery_status as enum (
  'CREATED',
  'READY_FOR_PICKUP',
  'ASSIGNED',
  'PICKED_UP',
  'IN_TRANSIT',
  'DELIVERED',
  'RETURNED',
  'DAMAGED',
  'LOST',
  'CANCELLED'
);
```

La migration `20261103213933_fix_courier_accept_and_require_pickup_photo.sql` ajoute `ACCEPTED`. Aucune migration examinée n'ajoute `COMPLETED` à `public.delivery_status`.

La table `public.delivery_assignments.status` utilise le type `public.delivery_status`.

La migration `20260921081745_v15_secure_package_delivery.sql` finalisait l'affectation avec `status='DELIVERED'`, valeur autorisée par l'enum.

Deux autres définitions utilisent cependant la valeur inexistante `COMPLETED` :

1. La migration `20260921084959_v61_delivery_assignment_lifecycle.sql`, puis sa redéfinition dans `20260924010845_fix_cancelled_packages_assignment.sql`, contiennent dans `public.assign_package_to_courier(uuid,uuid)` :

```sql
where package_id = p_package_id
  and status not in ('CANCELLED','DELIVERED')
```

La comparaison d'une colonne `public.delivery_status` à `COMPLETED` peut lever `invalid input value for enum delivery_status: "COMPLETED"` et empêcher l'affectation d'un colis.

2. La migration `20260921085013_v62_delivery_events_and_parent_sync.sql` remplace le finaliseur et définit dans `public.sync_after_package_delivery(uuid)` :

```sql
update public.delivery_assignments
set status = 'DELIVERED', completed_at = now()
where package_id = p_package_id
  and status in ('IN_TRANSIT','PICKED_UP','ACCEPTED');
```

`COMPLETED` n'appartient pas à l'enum. La première utilisation peut donc échouer dans la comparaison de `assign_package_to_courier`, et l'UPDATE de `sync_after_package_delivery` ne peut pas convertir cette valeur dans `delivery_assignments.status`.

## 2. Conséquence

La fonction `public.confirm_package_delivery(uuid,text)` appelle `sync_after_package_delivery` dans la même transaction. Quand l'affectation correspond, l'UPDATE avec la valeur non autorisée peut échouer et faire annuler toute la transaction, y compris la mise à jour du colis et l'événement associé.

Le risque touche donc la confirmation finale d'une livraison. Le statut du colis et celui de l'affectation peuvent ne jamais être enregistrés comme livrés par ce chemin.

Le nouveau tableau de bord partenaires compte les affectations terminées sous le statut réellement défini par l'enum, `DELIVERED`, et non le statut inexistant `COMPLETED`.

## 3. Correction à effectuer dans une nouvelle migration

Ne pas modifier les anciennes migrations déjà appliquées : cela ne corrigerait pas automatiquement les fonctions déjà installées sur le projet hébergé et fausserait la reproductibilité de l'historique.

Créer une nouvelle migration avec la Supabase CLI (`supabase migration new fix_delivery_assignment_terminal_status`) puis :

- redéfinir `public.sync_after_package_delivery(uuid)` pour enregistrer `DELIVERED` au lieu de `COMPLETED` ;
- redéfinir `public.assign_package_to_courier(uuid,uuid)` avec le même contrôle de disponibilité que la version actuellement déployée, mais en traitant `DELIVERED` comme terminal dans la clause d'exclusion : `status not in ('CANCELLED','DELIVERED')` ;
- conserver la validation du chauffeur actif, le verrouillage/conditionnement atomique de l'état du colis et les ACL de chaque fonction.

La correction doit conserver :
- les gardes de propriété et de mission active ;
- le verrouillage de la livraison et de son affectation ;
- l'idempotence de la confirmation ;
- l'événement de livraison et la synchronisation de l'état parent ;
- les ACL actuelles, sans donner l'exécution à `anon` ou `authenticated` si le chemin actuel réserve l'appel à `service_role`.

## 4. Tests exigés avant toute application distante

Sur la base locale reconstruite uniquement :
1. vérifier que `DELIVERED` existe dans `pg_enum` et que `COMPLETED` n'est pas une valeur de `delivery_status` ;
2. vérifier que `assign_package_to_courier` ne compare plus `delivery_status` à `COMPLETED` ;
3. vérifier que `sync_after_package_delivery` n'écrit plus `COMPLETED` dans `delivery_assignments.status` ;
4. exécuter un scénario complet de retrait puis livraison avec une affectation et des preuves factices ;
5. confirmer que le colis et l'affectation passent tous deux à `DELIVERED` ;
6. répéter le callback et vérifier qu'aucune seconde livraison ni double événement financier/logistique n'est créé ;
7. vérifier les refus pour un autre coursier, un code invalide, une mission annulée et une mission sans preuve requise.

Ensuite exécuter `supabase db reset --local` et `supabase test db --local` sur le nouveau commit avant toute discussion de migration distante.

## 5. Correction versionnée

La migration `20261115191336_phase1_commerce_integrity_final.sql` redéfinit `assign_package_to_courier` et `sync_after_package_delivery` afin d'utiliser `DELIVERED`, statut valide de l'enum. Les gardes du chauffeur, des états de commande et des ACL sont conservés.

Les assertions de contrat sont dans `supabase/tests/database/phase1_commerce_integrity_test.sql` et doivent encore être exécutées sur une base locale reconstruite.

## 6. Limites de cette passe

- Le constat provient de la comparaison statique des migrations versionnées ; aucun SQL live n'a été exécuté.
- Aucun projet Supabase n'était disponible via le connecteur durant cette session.
- L'environnement local de travail ne dispose pas de la commande `supabase` ; la création CLI de la migration et ses tests n'ont donc pas été exécutés.
- Aucune fonction hébergée, commande, preuve, donnée ou affectation n'a été modifiée.
- Ne pas annoncer la confirmation de livraison « corrigée » avant l'application contrôlée de la nouvelle migration, la reconstruction locale et les tests pgTAP.
