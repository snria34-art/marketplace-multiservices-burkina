# AUD-21 — Tables RLS sans policy : justification et contrôles

**Projet :** Marketplace Multiservices Burkina  
**Supabase :** `dzhhsoikzxibmngjzcch`  
**Date :** 7 novembre 2026  
**État :** 17 tables examinées ; aucun accès direct anon/authenticated ; aucune policy permissive ajoutée.

## 1. Résultat du contrôle

17 tables ont `relrowsecurity=true` et aucune policy RLS :

### 15 tables private

- `private.catalog_ai_product_scan_locks`
- `private.catalog_ai_product_scans`
- `private.catalog_moderation_audit`
- `private.catalog_moderation_findings`
- `private.catalog_moderation_responses`
- `private.platform_agent_runs`
- `private.platform_health_checks`
- `private.platform_repair_audit`
- `private.platform_repair_backups`
- `private.product_listing_restrictions`
- `private.return_policy_audit`
- `private.return_policy_rules`
- `private.review_moderation_audit`
- `private.seller_access_audit`
- `private.seller_access_requests`

Leur ACL est limitée à `postgres`. Aucun privilège SELECT/INSERT/UPDATE/DELETE n'est accordé à `anon`, `authenticated` ou `service_role`. Les opérations métier nécessaires passent par des fonctions contrôlées, souvent SECURITY DEFINER avec search_path fixé et vérification de l'identité, de l'activité du compte, de la propriété ou du rôle.

### 2 tables publiques de médias

- `public.delivery_evidence`
- `public.review_media`

Leurs ACL sont limitées à `postgres` et `service_role`. Aucun privilège direct n'est accordé à `anon` ou `authenticated`.

Les fonctions serveur attachent les médias après validation de l'utilisateur, du chemin Storage, du type de fichier, du consentement éventuel à l'image d'une personne, du colis/avis associé et de la propriété :
- `private.attach_delivery_evidence(...)` ;
- `private.attach_review_media(...)`.

## 2. Chemins de lecture légitimes

### Médias d'avis publiés

- `public.get_public_review_media(uuid)` est exécutable par `anon` et `authenticated`.
- Il appelle `private.get_public_review_media(uuid)`, SECURITY DEFINER, qui filtre explicitement `reviews.status = PUBLISHED`.
- Les avis non publiés ne peuvent pas faire apparaître leurs médias par cette fonction.
- `authenticated` et `anon` n'ont toujours pas de SELECT direct sur `public.review_media`.

### Preuves de livraison du client

- `public.get_customer_delivery_evidence(uuid)` est exécutable par `authenticated`, mais pas par `anon`.
- Il appelle `private.get_customer_delivery_evidence(uuid)`, SECURITY DEFINER.
- Le helper exige un compte actif, vérifie que `orders.customer_id = auth.uid()`, puis retourne uniquement les preuves DELIVERY de cette commande.
- Aucune lecture directe de `public.delivery_evidence` n'est accordée au client.

### Médias Storage

Les policies du bucket et les helpers de lecture doivent rester alignés sur ces règles d'accès. L'existence d'une RPC ne doit pas être utilisée pour ouvrir largement `storage.objects`.

## 3. Vérification SQL réalisée

Le contrôle live a vérifié toutes les 17 tables par `has_table_privilege` :
- relations présentes : 17/17 ;
- privilèges directs anon : 0/17 ;
- privilèges directs authenticated : 0/17 ;
- aucune lecture/écriture CRUD directe accordée.

Le contrôle de fonction a également confirmé :
- EXECUTE anon sur le helper public d'avis uniquement, pour avis publiés ;
- aucun EXECUTE anon sur la lecture des preuves de livraison ;
- EXECUTE authenticated sur la lecture des preuves de livraison ;
- propriété de commande explicitement vérifiée dans le helper.

## 4. Tests de régression ajoutés

Deux assertions supplémentaires sont ajoutées dans `supabase/tests/database/security_regression_test.sql` :
1. les 17 tables doivent rester sans privilèges CRUD directs pour `anon` et `authenticated` ;
2. les deux fonctions média doivent conserver leurs chemins d'accès différenciés, avec avis publiés et preuves de commande appartenant au client.

Le plan du fichier est maintenant 53 assertions. Le fichier complet pgTAP n'a pas encore été exécuté par CI.

## 5. Décision

Ne pas ajouter de policy RLS permissive et ne pas accorder de privilèges SELECT généraux afin de faire disparaître l'advisor. Un état RLS activé sans policy refuse l'accès direct, ce qui est approprié pour les données internes et les preuves médias. Si une nouvelle fonctionnalité doit lire une de ces tables, créer une RPC étroite, vérifier la propriété et les états métier et ajouter des tests négatifs.

Aucune table, policy, ACL ou donnée métier n'a été modifiée dans l'environnement de production au titre de cet audit ; seules les deux assertions de test versionnées ont été ajoutées.
