# AUD-22 — Revue des fonctions SECURITY DEFINER

**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**PostgreSQL :** 17.6.1  
**Date :** 7 novembre 2026  
**État :** fonctions applicatives examinées ; 14 chemins renforcés ; aucun REVOKE global.

## 1. Inventaire confirmé

Le catalogue PostgreSQL retourne 166 fonctions `SECURITY DEFINER` dans les schémas `public` et `private`.

| Mesure | Valeur |
|---|---:|
| Total SECURITY DEFINER | 166 |
| Fonctions applicatives détenues par `postgres` | 163 |
| Fonctions natives PostGIS détenues par `supabase_admin` | 3 |
| Exécutables par `authenticated` | 107 |
| Exécutables par `anon` | 6 |
| Chemins explicites vides (`search_path = ''`) | 48 |
| Fonctions applicatives sans `search_path` explicite après correction | 0 |
| Fonctions avec `pg_temp` explicitement dernier | 14 |

Les 3 fonctions natives sans `search_path` :
- `public.st_estimatedextent(text,text)`
- `public.st_estimatedextent(text,text,text)`
- `public.st_estimatedextent(text,text,text,boolean)`

Ce sont des fonctions C PostGIS appartenant à `supabase_admin`, pas des fonctions PL/pgSQL de l'application. Elles ne doivent pas être modifiées par le rôle de projet. Elles restent liées au traitement AUD-01 (déplacement PostGIS par Supabase Support).

## 2. Fonctions accessibles à anon

Les six fonctions SECURITY DEFINER exécutables par `anon` ont été examinées :

1. `private.can_read_published_review_media(text)` — booléen qui retourne vrai uniquement si le chemin désigne un média lié à un avis `PUBLISHED`.
2. `private.get_public_review_media(uuid)` — retourne le chemin, le type de média, la durée et la date uniquement pour les médias d'un avis `PUBLISHED`.
3. `private.is_admin()` — vérifie l'utilisateur courant dans `admin_users`, son statut `active=true` et le profil `ACTIVE`. Pour une requête anon sans `auth.uid()`, le résultat est faux.
4–6. Les trois fonctions PostGIS C `ST_EstimatedExtent` ci-dessus.

Les deux helpers média sont requis par les fonctions publiques de lecture et les contrôles de Storage. Le helper admin ne fournit aucun privilège à une requête sans utilisateur authentifié. Ne pas appliquer un `REVOKE EXECUTE ON ALL FUNCTIONS` : cela casserait les lectures publiques d'avis et d'autres RPC contrôlées.

## 3. Analyse des search_path

- 48 fonctions applicatives ont déjà un chemin vide. Leurs objets sont qualifiés par schéma.
- Les fonctions restantes possèdent toutes un chemin explicite.
- Un inventaire des références SQL non qualifiées `FROM`, `JOIN`, `UPDATE`, `INSERT INTO` et `DELETE FROM` dans les fonctions applicatives qui utilisent un chemin non vide n'a identifié aucune référence non qualifiée à une relation PostgreSQL existante dans `public`, `private`, `auth`, `storage`, `vault`, `extensions` ou `net`.
- Une vérification des types personnalisés a identifié trois types réellement non qualifiés dans les déclarations PL/pgSQL : `verification_status` dans les deux fonctions de réservation, et `payment_status` dans le traitement des événements fournisseur.
- Les autres résultats du scan étaient des noms de colonnes/alias ou des tables déjà qualifiées, et non des types de déclaration à risque.

PostgreSQL peut rechercher le schéma temporaire d'une session avant les autres schémas pour les noms de relations et de types lorsqu'il n'est pas explicitement placé dans le chemin. Comme les rôles `anon` et `authenticated` ont le privilège `TEMP` sur la base, placer explicitement `pg_temp` en dernier est une défense supplémentaire pour les fonctions qui utilisent des noms de types non qualifiés.

## 4. Corrections de configuration appliquées

Deux migrations ont été appliquées avec `apply_migration` et sont présentes dans GitHub.

### Migration `20261106220518_harden_security_definer_search_paths.sql`

Treize fonctions ont été réglées sans changer leur corps, leur propriétaire ni leurs ACL :

- 12 RPC applicatives d'inscription/réservation/commande/transport : `search_path = pg_catalog, public, private, pg_temp`.
- `public.handle_new_user()` : `search_path = pg_catalog, public, pg_temp`.

Ces 12 RPC conservent l'absence d'EXECUTE pour `anon` ; les 12 restent accessibles à `authenticated` et `service_role`. Le trigger `handle_new_user()` reste non exécutable par `anon` et `authenticated`, et demeure réservé au serveur.

### Migration `20261106220850_harden_payment_provider_event_search_path.sql`

- `public.process_payment_provider_event(uuid,text,text,jsonb)` : `search_path = pg_catalog, public, pg_temp`.
- La fonction reste `SECURITY DEFINER`, détenue par `postgres`, exécutable seulement par `service_role` (pas par `anon` ni `authenticated`).

Au total, 14 fonctions ont `pg_temp` en dernier. Aucun corps métier, rôle, propriétaire, privilège d'exécution, donnée financière, paiement, commande ou stock n'a été modifié.

## 5. Vérification post-migration

Les catalogues Supabase ont confirmé :
- 13 fonctions de la première migration présentes ;
- les 13 chemins exacts attendus ;
- les 13 restent SECURITY DEFINER et détenues par `postgres` ;
- zéro EXECUTE anon sur les 12 RPC ; les permissions authenticated/service_role restent inchangées ;
- `handle_new_user` reste réservé au service_role ;
- `process_payment_provider_event` a le chemin exact, demeure détenue par postgres et reste service_role-only ;
- aucun ancien chemin `public` ou `public, private` seul ne subsiste dans le lot corrigé ;
- aucune fonction applicative SECURITY DEFINER ne reste sans `search_path` explicite.
- Les trois fonctions PostGIS C restent sans chemin ; elles sont hors du périmètre de modification du rôle `postgres`.

Deux assertions pgTAP supplémentaires ont été ajoutées pour les 13 fonctions et le trigger. Une troisième assertion couvre `process_payment_provider_event`. Le fichier `security_regression_test.sql` compte maintenant 56 assertions.

## 6. État des tests

Les prédicats correspondant aux nouveaux tests ont été exécutés séparément en lecture seule sur la base live et sont vrais (12 RPC + trigger + provider-event RPC). Le fichier pgTAP complet n'a pas été exécuté par GitHub Actions : les jobs récents échouent sans étapes ou logs récupérables. Ne pas annoncer que l'ensemble de la suite pgTAP est passé.

## 7. État AUD-22

- Revue fonction par fonction des chemins exposés à anon, des helpers médias et admin ; pas de REVOKE global.
- 163 fonctions applicatives possèdent un `search_path` explicite.
- 14 chemins applicatifs les plus sensibles ont maintenant `pg_temp` en dernier.
- 3 fonctions PostGIS natives restent gérées par `supabase_admin` et sont suivies dans AUD-01.
- Aucune modification des rôles, ACL, données ou logique métier.
- Les alertes Security Advisor sur les fonctions PostGIS natives doivent être réexaminées après le déplacement de l'extension par Supabase Support.
