## Addendum — validations du 15 novembre 2026

Cette mise à jour prévaut sur les sections historiques ci-dessous qui décrivent encore les premiers échecs de runner du 7 novembre comme dernier état connu.

### Validations réellement réussies

- **Flutter CI**, run [43717217145](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43717217145) : Flutter 3.47.2, résolution verrouillée, analyse sans erreur ni avertissement bloquant, **29 tests Flutter réussis**, build Web **Debug** réussi avec des valeurs Supabase fictives. Les diagnostics de niveau info restent visibles.
- **Supabase Edge Functions**, run [43717824685](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43717824685) : `deno check` réussi sur les **22 points d'entrée** Edge Function.
- **pgTAP** : contrôle statique des 8 fichiers de tests. Les plans déclarés et les appels d'assertion recensés concordent dans chaque fichier ; total déclaré : **179**. Les tests n'ont pas été exécutés sur PostgreSQL local.
- **Android/iOS natifs** : les workflows de validation Debug non signés existent, mais aucun build natif n'a été lancé dans cette passe. Aucun AAB/IPA Release ni publication n'est autorisé.

### Sécurisation du workflow SQL

Le workflow `.github/workflows/supabase-db-tests.yml` a été renforcé sur la branche de maintenance (commit `aa2700f58057cf57416937e09b8c54c54d6862f2`) :

- déclenchement manuel uniquement et job limité à `maintenance/audit-01-07-2026-11-15` ;
- runner épinglé `ubuntu-24.04`, permissions de contenu en lecture seule et checkout sans identifiants persistants ;
- Supabase CLI épinglée à `2.122.1` ;
- stack Supabase locale éphémère, `supabase db reset --local` pour reconstruire depuis zéro puis `supabase test db --local` explicite ;
- aucune connexion, aucun secret et aucune commande de mutation distante dans ce workflow.

Après vérification de la documentation CLI, le workflow conserve bien `supabase db reset --local` après `supabase start` : cette commande recrée la base PostgreSQL locale, applique toutes les migrations et charge le seed de test configuré. La suite pgTAP est ensuite exécutée explicitement contre cette base locale. Le reset reste strictement local ; aucun `--remote`, `--linked`, DB URL ou secret distant n'est configuré.

### Verrou Vercel — déploiements Git suspendus

Le fichier `vercel.json` contient désormais :

```json
"git": {
  "deploymentEnabled": false
}
```

Ce paramètre désactive les déploiements Git automatiques pour toutes les branches, y compris la branche de production, tant qu'il reste en place. Il ne supprime pas un déploiement déjà créé et ne garantit pas l'annulation d'un build déjà en cours. La réactivation devra être faite séparément après autorisation et fin de maintenance.

Des statuts GitHub `Vercel: failure` sont présents sur les commits Flutter `5428bc9` et Edge `f2384db`. L'API Vercel refuse actuellement l'accès en lecture au scope `ridiastore` (403) et aucune équipe n'est retournée par la découverte de contexte ; le détail des déploiements et leurs journaux ne sont donc pas vérifiables depuis cette session. Aucun outil de création, promotion, annulation ou suppression de déploiement n'a été appelé.

### Limites qui restent ouvertes

L'environnement de travail courant ne contient ni Docker, ni Supabase CLI, ni PostgreSQL ; le connecteur Supabase ne retourne aucun projet accessible. Le workflow SQL n'a donc pas été exécuté dans cette passe. Les éléments suivants restent non certifiés :

1. reconstruction complète des 347 migrations et exécution des 179 assertions pgTAP sur une base locale isolée ;
2. builds Android APK Debug et iOS Simulator Debug, puis essais GPS en arrière-plan sur appareils ;
3. scénarios E2E de commande, paiement simulé, webhook signé/idempotent, retour/remboursement et concurrence ;
4. modèle financier d'allocation des remboursements, à valider avant toute modification de `complete_refund` ou du ledger ;
5. intervention Supabase Support et vérifications PostGIS ;
6. rapprochement de l'historique distant des migrations, opération volontairement non exécutée.

### Garde-fous inchangés

Les validations Flutter et Deno ne constituent pas une certification de l'ensemble du dépôt. Aucun déploiement GitHub/Vercel, aucun Preview/Production, aucun merge vers `main`, aucune migration ou requête SQL distante, aucun accès ou changement de données métier, aucun paiement/remboursement réel et aucun build Release n'ont été effectués.

---

# Suivi des corrections prioritaires — 15 novembre 2026

**Dépôt de référence :** `snria34-art/marketplace-multiservices-burkina`  
**Branche de travail :** `maintenance/audit-01-07-2026-11-15`  
**Base d'audit :** `main` au commit `be9c6407aa384d417f43c20d1492b3b9dcb21cb0`  
**Périmètre :** points 1 à 7 de l'audit, contrôle statique et corrections documentaires sûres. Aucun accès ni changement n'a été effectué sur la base Supabase distante.

## Règle de travail

Le projet reste en phase de correction. Aucun déploiement Vercel, aucun déploiement GitHub, aucune publication d'application mobile, aucun build de release et aucune promotion de production ne sont autorisés pendant cette phase. Les correctifs sont isolés sur une branche distincte ; `main` n'est pas modifiée. Les migrations distantes et les opérations de paiement restent interdites sans environnement isolé et validation spécifique.

## État des 7 points

### 1. PostGIS — exposition de `spatial_ref_sys`

**Constat confirmé dans l'audit du 7 novembre 2026.** PostGIS est installé dans `public`, sous le propriétaire `supabase_admin`. Les rôles clients possèdent des privilèges de modification hérités sur `public.spatial_ref_sys`.

**Correction déjà présente :** `20261106195420_aud01_prepare_postgis_functions_schema_fallback.sql` prépare les RPC applicatives à résoudre PostGIS dans `extensions` après déplacement, tout en conservant le fonctionnement actuel dans `public`.

**Ce qui reste :** le rôle du projet ne peut pas corriger seul les privilèges du propriétaire d'extension ; l'audit indique qu'un déplacement non destructif de l'extension doit être réalisé par Supabase Support. Ne pas tenter un `REVOKE`, un trigger, un `DROP EXTENSION` ou un déplacement manuel depuis une migration. Aucun changement distant n'a été effectué.

### 2. Remboursements — allocation entre vendeurs

**Défaut confirmé.** `complete_refund` répartit actuellement certains remboursements sur les groupes vendeurs de la commande sans allocation explicite par article, quantité ou groupe. Le runbook relève aussi le risque de double boutique pour un même vendeur, la capture tardive après annulation et le décalage possible entre confirmation Wave et comptabilisation du ledger.

**Décision de sécurité :** ne pas modifier `complete_refund`, `refunds`, `seller_ledger`, les commissions ou les soldes tant que les règles de financement des coupons, frais de livraison, commissions, retours partiels et rapprochement Wave ne sont pas fixées. Le runbook `docs/runbooks/aud-02-refund-allocation.md` décrit les invariants et les tests transactionnels nécessaires. Un changement improvisé pourrait déplacer de l'argent entre vendeurs.

### 3. Annulation de commande — commandes déjà payées

**Protection serveur déjà présente dans le dépôt.** La transition globale `CANCELLED` délègue à `cancel_unpaid_order`. La fonction refuse les commandes dont le statut n'est pas `PENDING_PAYMENT`, les paiements réglés, les colis/affectations déjà expédiés et les stocks déjà consommés. La migration `20261106201034_aud03_allow_admin_to_cancel_unpaid_orders_safely.sql` autorise aussi un administrateur actif à annuler une commande impayée, sans lui donner le droit d'annuler une commande payée.

**Tests présents :** les contrats SQL vérifient les gardes de statut, paiement, colis, affectations, stock, coupons et droits administrateur. Ils n'ont pas encore été exécutés dans une base isolée. L'annulation d'une commande payée reste bloquée jusqu'à la mise en place d'un flux de retour/remboursement sûr.

### 4. Historique des migrations Supabase

**Écart confirmé par l'audit :** 347 fichiers de migration dans GitHub contre 346 numéros consignés dans l'historique Supabase. Le seul numéro signalé comme absent est `20261104020500`. Le runbook indique que les effets de cette migration — fonction de classification et job cron — existent déjà sur la base distante et correspondent au SQL versionné.

**Correction préparée :** `.github/workflows/repair-aud-07-migration-history.yml` marque uniquement ce numéro comme appliqué avec `supabase migration repair`, sans rejouer le SQL.

**Ce qui reste :** cette commande change les métadonnées de migration sur le projet Supabase distant et nécessite des secrets d'accès. Elle n'a pas été exécutée. Ne pas utiliser `db push`, ne pas insérer manuellement dans `schema_migrations` et ne pas lancer ce workflow pendant cette phase de maintenance.

### 5. Paiements et notifications — Wave, CinetPay et FCM

**Garde de paiement déjà présente :** `check-payment-provider-config` vérifie la présence des paramètres Wave/CinetPay côté serveur et ne renvoie que des booléens. Flutter l'appelle avant `checkout_cart` ; si un fournisseur n'est pas configuré, le checkout est bloqué avant la création de commande et la réservation de stock. Les fonctions Wave/CinetPay v3 vérifient leurs propres signatures webhook.

**Ce qui reste :** l'audit indique que les clés marchandes Wave/CinetPay et le compte de service FCM sont absents. Aucun paiement réel, remboursement réel ou push réel ne doit être tenté. Les secrets doivent être configurés directement dans Supabase, jamais dans le dépôt, Flutter ou le chat. La validation doit d'abord se faire avec des comptes sandbox et des notifications simulées signées.

### 6. Tests, CI et validation des applications

**Vérification statique faite sur la branche `main` :**
- 8 fichiers de tests SQL pgTAP ;
- 179 assertions planifiées au total ;
- les 8 valeurs `plan(...)` correspondent exactement au nombre d'appels d'assertion détectés dans chaque fichier ;
- les tests Dart sont présents dans le dépôt.

**Blocage CI observé :** le dernier run Flutter consulté (`42323347582`, 7 novembre 2026) échoue en environ deux secondes, avec `runner_id=0`, `runner_name` vide et aucune étape exécutée. Cela indique un échec avant l'exécution du code ; ce n'est pas une preuve d'erreur de compilation Flutter. Les runs consultés présentent le même symptôme.

**Limite de cette session :** les exécutables Flutter, Dart, Deno, Supabase CLI et PostgreSQL ne sont pas disponibles dans l'environnement local. Aucun test ou build n'est donc déclaré réussi. Ne pas lancer de build de release ni de workflow de déploiement. La suite de validation attend un runner fonctionnel ou un environnement local équipé.

### 7. Propriété du dépôt et références à l'ancien compte

**Propriété actuelle vérifiée par l'API GitHub :** `snria34-art/marketplace-multiservices-burkina`, dépôt privé, branche par défaut `main`. Plusieurs audits et anciens commits mentionnent `adjasanou49-max`.

Ces références historiques ne signifient pas que le dépôt actuel appartient encore à cet ancien compte. Les auteurs de commits ne doivent pas être réécrits pour masquer l'historique. Les documents de maintenance courants doivent pointer vers le dépôt canonique actuel ; les anciens rapports datés restent des traces historiques.

## Opérations réalisées dans cette passe

- Création de la branche de travail `maintenance/audit-01-07-2026-11-15` à partir de `main`.
- Mise à jour du README pour indiquer le dépôt canonique et le gel des déploiements pendant la maintenance.
- Aucun changement de `main`.
- Aucune migration distante, modification de base, transaction financière, action CI, build release ou déploiement n'a été exécuté.

## Critères de clôture avant toute mise en production

1. Intervention Supabase Support validée pour PostGIS et vérifications ACL après déplacement.
2. Modèle d'allocation de remboursement approuvé et couvert par des tests transactionnels.
3. Tests de refus des annulations payées et de synchronisation des colis validés dans une base isolée.
4. Historique local/distant aligné sans rejouer la migration déjà appliquée.
5. Fournisseurs de paiement et FCM configurés en environnement de test ; callbacks signés et idempotents vérifiés.
6. `flutter analyze`, `flutter test`, `deno check` et les suites pgTAP exécutés avec logs lisibles ; tests appareils natifs ensuite.
7. Dépôt, espace de travail et règles d'accès confirmés sous le compte propriétaire actuel.

**Conclusion :** plusieurs protections applicatives sont déjà en place, mais les points PostGIS, allocation financière, historique distant, secrets fournisseurs et validation CI restent ouverts. Les laisser explicitement bloqués est plus sûr que de simuler une correction ou de toucher à la production.
