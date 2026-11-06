# AUD-01 — Déplacement sûr de PostGIS vers `extensions`

**Projet :** Marketplace Multiservices Burkina  
**Référence Supabase :** `dzhhsoikzxibmngjzcch`  
**État au 7 novembre 2026 :** PostGIS 3.3.7 dans `public`, propriétaire `supabase_admin`.  
**Statut :** préflight terminé ; fonctions préparées et vérifiées dans Supabase ; déplacement non destructif de l'extension en attente de Supabase Support.

## 1. Diagnostic vérifié

Les contrôles SQL en lecture seule ont confirmé :

- `public.spatial_ref_sys` : propriétaire `supabase_admin`, RLS désactivé, 8 500 lignes.
- Les rôles `anon` et `authenticated` ont INSERT, UPDATE, DELETE et TRUNCATE sur cette table.
- Trois colonnes spatiales métier existent :
  - `public.courier_locations.location geography`
  - `public.provider_locations.location geography`
  - `public.shops.location geography`
- Les trois tables contiennent actuellement zéro ligne.
- Deux index GiST existent : `idx_courier_locations_geo` et `idx_shops_location`.
- Aucune extension supplémentaire dépendante de PostGIS n'a été recensée.
- Aucun objet géospatial métier en dehors des vues standard `geometry_columns` et `geography_columns` n'a été trouvé.
- Aucun autre appel PostGIS direct depuis Flutter n'a été trouvé. Les deux RPC métier ci-dessous sont les seuls routines applicatives identifiées avec des appels PostGIS explicites.

**Interprétation de sécurité :** `spatial_ref_sys` contient des définitions publiques de systèmes de coordonnées ; ce n'est pas une table contenant les coordonnées privées des clients. Le risque est qu'un client modifie/supprime des SRID et casse des calculs PostGIS. Les statistiques consultées indiquent zéro UPDATE et zéro DELETE depuis la dernière remise à zéro. Les logs Data API du 6 au 7 novembre ne montrent aucune tentative POST/PATCH/PUT/DELETE vers cette table ; cela ne couvre pas toute la durée de vie de la base.

## 2. Pourquoi la correction SQL directe est refusée

Ne pas exécuter les opérations suivantes :

```sql
ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.spatial_ref_sys FROM anon, authenticated;
CREATE TRIGGER ... ON public.spatial_ref_sys ...;
ALTER EXTENSION postgis SET SCHEMA extensions;
```

Motifs :
- seul le propriétaire `supabase_admin` peut activer RLS ou retirer les privilèges qu'il a accordés ;
- les `REVOKE` exécutés par le rôle de projet ne retirent pas les grants du propriétaire PostGIS ;
- un trigger bloquant n'est pas une solution durable et ne peut pas être retiré par le rôle de projet ;
- PostGIS ne supporte pas `ALTER EXTENSION ... SET SCHEMA`.

## 3. Message à transmettre à Supabase Support

Ouvrir un ticket depuis le tableau de bord Supabase, pour le projet `dzhhsoikzxibmngjzcch`, et envoyer ce texte :

> Bonjour,
>
> Nous souhaitons déplacer l'extension PostGIS existante de `public` vers le schéma `extensions` sur le projet `dzhhsoikzxibmngjzcch`.
>
> L'extension est en version 3.3.7 et appartient à `supabase_admin`. Le projet possède trois colonnes `geography` :
> - `public.courier_locations.location`
> - `public.provider_locations.location`
> - `public.shops.location`
>
> Deux index GiST sont présents sur `courier_locations.location` et `shops.location`. Les tables sont actuellement vides, mais nous souhaitons préserver leur schéma, types, index, vues, fonctions, données et définitions SRID.
>
> Merci d'effectuer le déplacement non destructif de PostGIS vers `extensions` avec votre procédure Support, sans DROP/CREATE CASCADE côté projet. Merci de confirmer que les colonnes geography, leurs index GiST, les vues PostGIS et les données `spatial_ref_sys` sont conservés, puis de nous indiquer quand nous pouvons exécuter les ajustements de fonctions applicatives ci-dessous.
>
> Nous avons déjà préparé les deux fonctions applicatives avant votre intervention : elles utilisent désormais `search_path = pg_catalog, extensions, public` et des références PostGIS non qualifiées. Elles fonctionnent donc actuellement avec PostGIS dans `public` et sont prêtes à résoudre les objets dans `extensions` après votre déplacement.
>
> Merci de confirmer le déplacement non destructif et de nous indiquer lorsqu'il est terminé afin que nous exécutions les vérifications post-migration.
>
> Merci.

Le support ne doit pas être remplacé par un essai de migration destructive exécuté depuis SQL Editor.

## 4. Préparation des fonctions métier — déjà appliquée

Les deux RPC applicatives ont été préparées **avant** le déplacement PostGIS dans la migration :

`supabase/migrations/20261106195420_aud01_prepare_postgis_functions_schema_fallback.sql`

Le correctif a été appliqué sur Supabase le 6 novembre 2026 à 19:54:20 UTC, puis relu et vérifié.

Les deux fonctions sont :

- `public.calculate_delivery_fee(uuid,jsonb)`
- `public.record_courier_location(double precision,double precision,numeric)`

Elles utilisent maintenant :

```sql
SET search_path = pg_catalog, extensions, public
```

Les références explicites `public.st_distance`, `public.st_setsrid`, `public.st_makepoint` et `::public.geography` ont été remplacées par les noms non qualifiés `st_distance`, `st_setsrid`, `st_makepoint` et `::geography`.

Cette stratégie est volontaire :

- **Avant le déplacement**, aucun de ces objets n'existe dans `extensions`, donc PostgreSQL les résout dans `public`.
- **Après le déplacement**, `extensions` est prioritaire dans le `search_path`, donc les mêmes appels résolvent les objets PostGIS déplacés, sans modifier une deuxième fois le corps des fonctions.
- `anon`, `authenticated` et `service_role` n'ont pas le droit `CREATE` sur `public` ni `extensions`, ce qui évite qu'un client puisse y injecter un objet qui détournerait cette résolution.

Contrôles réussis après application :

- les deux fonctions restent détenues par `postgres` et sont toujours `SECURITY DEFINER` ;
- leur `search_path` vaut `pg_catalog, extensions, public` ;
- aucune référence PostGIS explicite vers `public.*` ne subsiste dans les deux corps ;
- `anon` ne peut pas exécuter les deux RPC ; `authenticated` et `service_role` le peuvent ;
- un calcul réel `ST_Distance` a réussi et a retourné 10,88 mètres pour deux points de test ;
- aucune table, colonne, ligne métier, index ou extension n'a été supprimé ou déplacé par cette migration.

**Conséquence :** il n'est pas nécessaire de réécrire les deux fonctions après le déplacement. Il restera à vérifier qu'elles résolvent correctement les objets dans `extensions` une fois l'opération Support terminée.

## 5. Vérifications après déplacement et migration

### 5.1 Vérifier le schéma de l'extension

```sql
select extversion, extnamespace::regnamespace as postgis_schema
from pg_extension
where extname = 'postgis';
```

Résultat attendu : version `3.3.7`, schéma `extensions`.

### 5.2 Vérifier les colonnes, index et vues conservés

```sql
select table_name, column_name, udt_name
from information_schema.columns
where table_schema = 'public'
  and (table_name, column_name) in (
    ('courier_locations', 'location'),
    ('provider_locations', 'location'),
    ('shops', 'location')
  )
order by table_name;
```

Résultat attendu : les trois colonnes existent et leur type est `geography`.

```sql
select tablename, indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename in ('courier_locations', 'shops')
  and indexname in ('idx_courier_locations_geo', 'idx_shops_location')
order by tablename, indexname;
```

Résultat attendu : les deux index GiST existent.

### 5.3 Vérifier un calcul PostGIS sans écrire de données métier

```sql
select extensions.st_distance(
  extensions.st_setsrid(extensions.st_makepoint(-1.5197, 12.3714), 4326)::extensions.geography,
  extensions.st_setsrid(extensions.st_makepoint(-1.5300, 12.3600), 4326)::extensions.geography,
  true
) as distance_meters;
```

Résultat attendu : une distance positive en mètres, sans erreur SRID/type.

### 5.4 Vérifier les fonctions applicatives

- Contrôler `pg_get_functiondef` et vérifier qu'aucun appel `public.st_*` ni cast `::public.geography` n'est présent ; vérifier que le `search_path` contient `pg_catalog, extensions, public` dans cet ordre.
- Contrôler les privilèges `EXECUTE` des deux RPC.
- Exécuter `calculate_delivery_fee` avec une session client de test et un panier contrôlé.
- Exécuter `record_courier_location` avec un compte coursier de test autorisé, puis vérifier l'enregistrement dans `courier_locations` et le nettoyage du jeu de test.
- Rejouer les tests de checkout/livraison/coursier.
- Redémarrer les applications et reconnecter les pools pour qu'aucune connexion ne conserve l'ancien schéma PostGIS.

### 5.5 Vérifier les alertes Supabase

- Relancer Security Advisor : les alertes PostGIS dans `public` doivent disparaître après le déplacement.
- Supabase précise qu'après un déplacement effectué par Support, `has_table_privilege('anon', 'extensions.spatial_ref_sys', ...)` peut rester vrai parce que les grants sont conservés ; ce n'est pas un échec tant que `extensions` n'est pas exposé par la Data API.
- Ne pas exposer le schéma `extensions` dans les paramètres Data API.

## 6. État et limites

- **Préparation applicative : terminée et vérifiée.** La migration `20261106195420_aud01_prepare_postgis_functions_schema_fallback.sql` est présente dans GitHub et dans l'historique Supabase.
- **Déplacement de PostGIS : non effectué.** PostGIS 3.3.7 se trouve toujours dans `public`, propriété de `supabase_admin`, et `extrelocatable=false`.
- Le déplacement sans perte des trois colonnes `geography`, des index GiST, des vues et des données de référence nécessite toujours l'intervention Supabase Support.
- Aucun compte propriétaire n'a été créé. Aucun paiement ou secret Firebase n'a été touché.
- Après confirmation du Support, vérifier le schéma de l'extension, les trois colonnes, les deux index GiST, le calcul spatial, les fonctions RPC et Security Advisor. Ne pas déclarer AUD-01 terminé avant ces contrôles.

