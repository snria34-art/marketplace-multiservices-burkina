# Suivi de déblocage et de sécurisation — 16 novembre 2026

**Dépôt :** `snria34-art/marketplace-multiservices-burkina`  
**Branche de travail :** `maintenance/audit-01-07-2026-11-15`  
**Objectif :** consigner les vérifications complémentaires et l'état exact des blocages après l'audit du 15 novembre 2026.

Ce rapport est un suivi technique basé sur les fichiers GitHub, les runs GitHub Actions consultés et les réponses des connecteurs disponibles. Il ne certifie pas l'environnement Supabase hébergé, le compte Vercel, les paiements réels ni les appareils mobiles.

## 1. État des branches et des contrôles

- `main` : commit `9b70580f322814d6decf9eeac2e5d93aa01e44e9`.
- `maintenance/audit-01-07-2026-11-15` : commit `9891504b09bb077f4de78bf7a4a39ab1ff19620e`.
- Comparaison actuelle : maintenance est en avance de 166 commits et en retard d'un commit sur `main`. Le commit manquant sur maintenance est le verrou Vercel décrit ci-dessous.
- Aucun workflow run ni check run n'est associé aux deux têtes actuelles (`9b70580` et `9891504`). Les validations réussies ci-dessous concernent donc des commits antérieurs, pas ces têtes exactes.

### Dernières validations utiles sur maintenance

| Contrôle | Run / commit testé | Résultat observé | Limite |
|---|---|---|---|
| Flutter CI | #678 — `6dbade55d0724a83c96b1b2c1f6241c6710e7dba` | Succès, 50 tests, analyse sans warning ni erreur, build Web Debug | 376 diagnostics de niveau `info` subsistent ; pas de run sur HEAD `9891504` |
| Android Debug | #289 — même SHA `6dbade55` | APK Debug réussi | iOS Simulator ignoré/non exécuté |
| Supabase Edge Functions CI | #83 — `bf42b629c89efbd2f909941a0a5a74966cb9ee17` | 26 tests Deno réussis ; `deno check` sur 22 points d'entrée | Pas de sandbox Wave/CinetPay ni d'essai hébergé |
| PostgreSQL / pgTAP | #120 — `e0eac2cf7e15019b5cfa95304cffc6f209fe1875` | 200 tests réussis | Le workflow a été modifié ensuite ; sa nouvelle configuration n'a pas encore de run |

Le commit `9891504` ne modifie que `.github/workflows/supabase-db-tests.yml` : déclenchement manuel uniquement, `supabase/setup-cli@v3`, CLI épinglée sur `2.122.1` et vérification de version. La configuration est relue dans GitHub mais n'a pas encore été testée par un nouveau run.

### Derniers échecs visibles sur main

- Flutter CI #645, commit `b3a3d616935727b0ef3adf81745b5f354cb17b44` : échec pendant `flutter analyze` strict. Les extraits du journal montrent des diagnostics de niveau `info`, notamment des imports Geolocator inutiles. La branche maintenance contient déjà la configuration d'analyse qui n'échoue pas sur les `info`, ainsi que des nettoyages ciblés.
- Supabase database tests #103, commit `be9c6407aa384d417f43c20d1492b3b9dcb21cb0` : échec de `security_regression_test.sql` à cause de `pg_get_functiondef('public.get_seller_access_requests()')`, qui transmet un texte là où PostgreSQL attend un OID/référence de routine. La correction `::regprocedure` est présente sur maintenance et le run #120 y passe.
- Ces échecs sont historiques et ne prouvent pas le comportement du dernier commit de `main`. Réciproquement, les succès maintenance ne prouvent pas le déploiement ou le fonctionnement de production.

## 2. Verrouillage Vercel de main

Le commit `9b70580f322814d6decf9eeac2e5d93aa01e44e9` ajoute dans le `vercel.json` de `main` :

```json
"git": {
  "deploymentEnabled": {
    "main": false
  }
}
```

Le fichier a été relu après commit. Cette configuration vise les déploiements Git automatiques depuis `main`. Elle ne remplace pas la vérification du paramètre dans le projet Vercel et ne constitue pas une protection GitHub contre les pushs, merges, déploiements manuels ou changements des paramètres du projet.

L'accès à l'équipe Vercel demeure refusé (HTTP 403, scope `ria-8e4b`). Le contrôle du projet, de ses paramètres et de son historique de déploiement reste donc en attente d'approbation de l'accès à l'équipe.

## 3. Protection de la branche main

Le résultat GitHub de la branche indique `protected: false` et aucun contrôle requis. La lecture de l'endpoint de protection dédié renvoie HTTP 403 à l'intégration, qui ne peut pas configurer la règle. La protection doit être créée par un propriétaire/administrateur du dépôt.

Configuration recommandée : exiger une pull request, une approbation, les contrôles CI sélectionnés, résoudre les conversations, interdire force-push et suppression, limiter les bypass aux administrateurs explicitement choisis. Ne pas prétendre que cette règle est active avant de la relire dans GitHub.

## 4. Supabase, PostGIS et historique distant

La liste de projets Supabase accessible à la connexion est vide. Une lecture directe du projet documenté `dzhhsoikzxibmngjzcch` est refusée par permission. Aucun test SQL distant, aucune migration hébergée et aucune modification de données n'ont été effectués.

- **PostGIS :** le runbook AUD-01 rapporte l'extension 3.3.7 dans `public`, propriété `supabase_admin`, et des permissions sensibles sur `public.spatial_ref_sys`. Les fonctions applicatives sont préparées avec `search_path = pg_catalog, extensions, public`. Le déplacement doit être effectué par Supabase Support ; ne pas tenter un `DROP EXTENSION`, un déplacement forcé ou une révocation supposée suffisante.
- **Historique des migrations :** la divergence précédemment rapportée autour de `20261104020500` demeure non vérifiée aujourd'hui. Exécuter seulement un rapprochement en lecture seule lorsque l'accès au projet est autorisé. Ne jamais réparer l'historique distant sans snapshot, comparaison et validation du propriétaire.
- **Reconstructions locales :** le run #120 a validé 200 tests sur sa révision antérieure. Le workflow révisé est manuel et utilise explicitement les commandes locales ; attendre son premier run avant de déclarer sa configuration CI validée.

## 5. Remboursements et paiements

- Le modèle d'allocation multi-vendeurs reste bloqué par une décision métier/comptable : financement des remises (plateforme, vendeur, cofinancement), frais de livraison, commission, lignes et quantités retournées, arrondis XOF et vendeur déjà payé.
- La protection technique en place empêche le prorata arbitraire et crée un rapprochement privé `PENDING_ALLOCATION`. Les payouts vendeurs et les remboursements additionnels concernés restent bloqués tant que cette allocation n'est pas validée.
- Ne pas lever ce gel, modifier les soldes ou ledger, ni relancer un remboursement fournisseur après un résultat inconnu sans rapprochement.
- Les webhooks Wave/CinetPay contrôlent la signature, la référence, les montants et la devise avant traitement ; les événements ont une identité idempotente. L'exécution Wave du remboursement est limitée au montant intégral du checkout ; les autres fournisseurs restent en traitement manuel dans le code examiné.
- Les secrets Wave/CinetPay et les scénarios sandbox ne sont pas vérifiés. Le dernier état de santé documenté indiquait des secrets marchands manquants ; ce statut reste à confirmer depuis le compte propriétaire. Aucun paiement réel ne doit être utilisé comme test.

## 6. Vérifications opérationnelles restantes

1. Obtenir l'accès administrateur GitHub et activer/relire la règle de protection de `main`.
2. Faire approuver l'accès Vercel, relire le paramètre de déploiement Git du projet et l'historique des environnements Production/Preview.
3. Ouvrir le ticket Supabase Support AUD-01 pour le déplacement non destructif PostGIS ; exécuter ensuite les contrôles d'extension, colonnes geography, index GiST, fonctions RPC et Security Advisor.
4. Autoriser la lecture Supabase puis comparer l'historique distant à toutes les migrations du dépôt, sans écriture.
5. Valider le modèle d'allocation avec le responsable métier/comptable ; construire et tester les allocations sur une base isolée avant toute migration.
6. Configurer les secrets marchands uniquement dans les coffres du projet et exécuter les parcours sandbox signés, retries et rapprochements.
7. Exécuter les tests E2E de commande, stock, livraison, paiement, remboursement, notifications et accès par rôle avec comptes de test.
8. Exécuter les tests GPS en arrière-plan/écran verrouillé sur appareils Android et iOS ; définir la rétention et la purge des positions.
9. Faire un build iOS Debug sur macOS ; aucun build Release ni publication n'est autorisé par ce rapport.
10. Nettoyer les 376 diagnostics Flutter `info` de façon progressive, sans changements massifs non testés.

## 7. Décision de disponibilité

**Statut : NON CERTIFIÉ POUR PRODUCTION / PAIEMENTS RÉELS.**

La base Flutter, plusieurs tests unitaires, les fonctions Edge et les tests PostgreSQL ont des validations positives sur des commits antérieurs de maintenance. Mais la tête actuelle n'a pas de run CI, la protection de `main` n'est pas active, le projet Vercel et Supabase ne sont pas vérifiés depuis les connecteurs, PostGIS nécessite Support, les secrets et sandboxes marchands ne sont pas validés, et les parcours terrain/E2E/iOS restent incomplets.

Aucune migration distante, aucun paiement réel, aucune opération sur les soldes ou remboursements, aucun déploiement, aucune publication ni aucun merge vers `main` n'a été effectué dans cette passe.
