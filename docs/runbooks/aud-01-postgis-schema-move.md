# AUD-01 — Déplacement sûr de PostGIS vers `extensions`

**Projet :** Marketplace Multiservices Burkina  
**Référence Supabase :** `dzhhsoikzxibmngjzcch`  
**État au 7 novembre 2026 :** PostGIS 3.3.7 dans `public`, propriétaire `supabase_admin`.  
**Statut :** préflight terminé ; déplacement en attente d'une intervention Supabase Support.

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
> Nous avons identifié deux fonctions applicatives qui utilisent actuellement `public.st_*` et `public.geography`. Nous mettrons à jour ces fonctions immédiatement après votre intervention.
>
> Merci.

Le support ne doit pas être remplacé par un essai de migration destructive exécuté depuis SQL Editor.

## 4. Fonctions métier à adapter après confirmation du déplacement

Après que Support confirme que `pg_extension.extnamespace` de PostGIS est `extensions`, appliquer les deux définitions suivantes dans une migration versionnée. Elles conservent les mêmes signatures, contrôles de propriété, validations et réponses métier ; seuls les préfixes PostGIS et le `search_path` changent.

### 4.1 `calculate_delivery_fee(uuid,jsonb)`

```sql
CREATE OR REPLACE FUNCTION public.calculate_delivery_fee(
  p_cart_id uuid,
  p_delivery_address jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_user uuid := (select auth.uid());
  v_lat double precision;
  v_lon double precision;
  v_distance numeric := 0;
  v_stop_count integer := 0;
  v_base_fee numeric := 0;
  v_per_km_fee numeric := 0;
  v_per_stop_fee numeric := 0;
  v_customer_fee numeric := 0;
  v_rule_id uuid;
begin
  perform private.require_active_account();
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  if p_cart_id is null then
    raise exception 'cart_required';
  end if;

  perform 1
  from public.carts
  where id = p_cart_id
    and customer_id = v_user
    and status = 'ACTIVE';
  if not found then
    raise exception 'cart_not_active_or_not_owned';
  end if;

  v_lat := nullif(trim(p_delivery_address ->> 'latitude'), '')::double precision;
  v_lon := nullif(trim(p_delivery_address ->> 'longitude'), '')::double precision;

  if v_lat is not null and (v_lat < -90 or v_lat > 90) then
    raise exception 'latitude_invalid';
  end if;

  if v_lon is not null and (v_lon < -180 or v_lon > 180) then
    raise exception 'longitude_invalid';
  end if;

  select count(distinct p.shop_id)::integer
    into v_stop_count
  from public.cart_items ci
  join public.products p on p.id = ci.product_id
  where ci.cart_id = p_cart_id
    and p.status = 'ACTIVE';

  if v_lat is not null and v_lon is not null then
    select coalesce(
      max(
        extensions.st_distance(
          s.location,
          extensions.st_setsrid(
            extensions.st_makepoint(v_lon, v_lat),
            4326
          )::extensions.geography,
          true
        ) / 1000
      ),
      0
    )
    into v_distance
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    join public.shops s on s.id = p.shop_id
    where ci.cart_id = p_cart_id
      and p.status = 'ACTIVE'
      and s.location is not null;
  end if;

  select id, base_fee, per_km_fee, per_stop_fee
    into v_rule_id, v_base_fee, v_per_km_fee, v_per_stop_fee
  from public.delivery_pricing_rules
  where active = true
    and min_distance_km <= v_distance
    and (max_distance_km is null or v_distance <= max_distance_km)
  order by min_distance_km desc
  limit 1;

  if v_rule_id is null then
    raise exception 'delivery_pricing_not_configured';
  end if;

  v_customer_fee := greatest(
    0,
    round(
      v_base_fee
      + (v_distance * v_per_km_fee)
      + greatest(v_stop_count - 1, 0) * v_per_stop_fee,
      0
    )
  );

  return jsonb_build_object(
    'customer_fee', v_customer_fee,
    'distance_km', round(v_distance, 2),
    'stop_count', greatest(v_stop_count, 1),
    'pricing_rule_id', v_rule_id,
    'currency', 'XOF'
  );
end;
$function$;
```

### 4.2 `record_courier_location(double precision,double precision,numeric)`

```sql
CREATE OR REPLACE FUNCTION public.record_courier_location(
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_m numeric DEFAULT NULL::numeric
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
declare
  v_user uuid := auth.uid();
  v_id bigint;
begin
  perform private.require_active_account();
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;

  if not private.has_role('COURIER'::public.user_role) then
    raise exception 'courier_role_required' using errcode = '42501';
  end if;

  if p_latitude is null or p_latitude < -90 or p_latitude > 90 then
    raise exception 'latitude_invalid' using errcode = '22023';
  end if;

  if p_longitude is null or p_longitude < -180 or p_longitude > 180 then
    raise exception 'longitude_invalid' using errcode = '22023';
  end if;

  if p_accuracy_m is not null and p_accuracy_m < 0 then
    raise exception 'accuracy_invalid' using errcode = '22023';
  end if;

  insert into public.courier_locations(
    courier_id,
    location,
    accuracy_m,
    recorded_at
  )
  values(
    v_user,
    extensions.st_setsrid(
      extensions.st_makepoint(p_longitude, p_latitude),
      4326
    )::extensions.geography,
    p_accuracy_m,
    now()
  )
  returning id into v_id;

  return v_id;
end;
$function$;
```

`CREATE OR REPLACE FUNCTION` conserve les privilèges d'exécution existants. Après application, vérifier explicitement que :
- `calculate_delivery_fee(uuid,jsonb)` reste exécutable par `authenticated`, pas par `anon` ni `PUBLIC` ;
- `record_courier_location(double precision,double precision,numeric)` reste exécutable par `authenticated`, pas par `anon` ni `PUBLIC` ;
- les propriétaires et la configuration `SECURITY DEFINER` sont inchangés.

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

- Contrôler les définitions `pg_get_functiondef` et vérifier les références `extensions.st_*` / `extensions.geography`.
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

- Le déplacement PostGIS n'a pas été exécuté, car les colonnes geography métier existent et la méthode support est la seule option non destructive recommandée.
- Aucun privilège, migration, fonction, donnée ou paramètre de production n'a été modifié.
- Les deux nouvelles définitions SQL sont préparées mais **ne doivent pas être appliquées avant la confirmation du déplacement par Supabase Support**.
- Après le retour Support, intégrer ces définitions dans une migration versionnée et la tester avant déploiement.
