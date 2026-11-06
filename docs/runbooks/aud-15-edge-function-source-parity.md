# AUD-15 — Synchronisation des sources Edge Functions

**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina` — `main`  
**État au 7 novembre 2026 :** sources restaurées et trois fonctions redéployées/vérifiées.

## 1. État découvert

Supabase avait 21 Edge Functions actives alors que GitHub ne contenait que 18 dossiers sources. Trois fonctions n'étaient pas présentes dans le dépôt :

| Fonction | Version avant | Vérification JWT | Code |
|---|---:|---|---|
| `expire-products` | v2 | true | Déclassification des produits périmés après vérification admin |
| `admin-health-check` | v2 | true | Vérification d'accès aux tables principales |
| `payment-webhook-gateway` | v3 | false | Endpoint historique retiré, répond HTTP 410 |

Aucune référence entrante n'a été trouvée dans le code Flutter/GitHub ou les fonctions SQL examinées pour les anciens endpoints. Aucun job Cron ne les appelle directement. Le gateway ne doit pas être supprimé sans inventaire externe final, mais il est explicitement retiré et ne doit pas être réactivé.

## 2. Sources restaurées dans GitHub

### expire-products

Fichiers :
- `supabase/functions/expire-products/index.ts`
- `supabase/functions/expire-products/deno.json`

Comportement :
- POST seulement ;
- token Bearer exigé et validé via `supabase.auth.getUser(token)` ;
- vérifie en parallèle `admin_users.active=true` et `profiles.status='ACTIVE'` pour le même utilisateur ;
- fail-closed en cas d'erreur de lecture des droits ;
- désactive uniquement les produits expirables, de statut ACTIVE, avec `expiry_date < today` ;
- ne supprime aucune ligne ni commande.

### admin-health-check

Fichiers :
- `supabase/functions/admin-health-check/index.ts`
- `supabase/functions/admin-health-check/deno.json`

Comportement :
- GET seulement ;
- token Bearer exigé et validé via Supabase Auth ;
- exige un enregistrement `admin_users.active=true` et un profil `ACTIVE` ;
- refuse en cas d'erreur d'autorisation ;
- vérifie par HEAD/count l'accès service-role aux tables principales ;
- n'écrit pas de données métier.

### payment-webhook-gateway

Fichiers :
- `supabase/functions/payment-webhook-gateway/index.ts`
- `supabase/functions/payment-webhook-gateway/deno.json`

Le code continue de répondre `410 legacy_endpoint_retired`. `verify_jwt=false` est conservé car l'endpoint est public historiquement ; il n'effectue aucune action, ne reçoit aucun paiement et n'accède pas à la base.

## 3. Vérification de la production Supabase

Après déploiement, `list_edge_functions` et `get_edge_function` ont confirmé :

| Fonction | Version actuelle | verify_jwt | Contrôle de code |
|---|---:|---|---|
| `expire-products` | v3 | true | JWT + admin actif + profil ACTIVE confirmés |
| `admin-health-check` | v3 | true | JWT + admin actif + profil ACTIVE confirmés |
| `payment-webhook-gateway` | v4 | false | `legacy_endpoint_retired` + HTTP 410 confirmés |

Le projet expose toujours 21 fonctions et le dépôt contient maintenant les 21 dossiers sources correspondants. Aucun endpoint n'a été désactivé ou supprimé.

## 4. Secrets et données

- Les fonctions utilisent uniquement `SUPABASE_URL` et `SUPABASE_SERVICE_ROLE_KEY` côté serveur.
- Aucun secret n'a été lu, copié dans GitHub, changé ou exposé.
- Aucun compte administrateur, produit ou paiement n'a été créé/modifié pendant la vérification.
- La table produits ne contenait aucun produit et aucune ligne expirée au moment du contrôle.

## 5. CI et limites

Le workflow `.github/workflows/supabase-functions-ci.yml` se déclenche sur les changements de `supabase/functions/**` et exécute `deno check` sur tous les fichiers `index.ts`.

Les runs associés aux fichiers restaurés ont échoué avant d'enregistrer une étape de job (liste des étapes vide ; journaux non disponibles via le connecteur). Cela ne prouve pas un défaut Deno du code, mais signifie que le contrôle statique CI n'est pas confirmé. La vérification manuelle du code déployé est positive, mais ne remplace pas `deno check`.

À faire au prochain CI fonctionnel :
1. vérifier que les trois répertoires et tous les autres passent `deno check` ;
2. exécuter des tests d'autorisation avec administrateur actif, compte suspendu, token invalide et utilisateur standard ;
3. tester `expire-products` sur un produit factice en environnement de test, jamais sur des données de production ;
4. confirmer que le gateway retourne 410 à toutes les méthodes HTTP et qu'aucun client ne l'appelle.

## 6. État

- Parité des sources : restaurée, 21/21.
- Production : trois fonctions mises à jour aux versions v3/v3/v4 et contenus relus après déploiement.
- Pas de suppression ou de désactivation destructive.
- CI Deno : non confirmé, faute d'étapes/journaux.
