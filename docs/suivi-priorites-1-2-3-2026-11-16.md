# Suivi des priorités 1 à 3 — 16 novembre 2026

**Dépôt :** `snria34-art/marketplace-multiservices-burkina`  
**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Tête examinée :** `a61064cf7d07f419c9c68a764cb3d8ad2a6a6ef4`  
**Périmètre :** préparation et vérifications sans opérations financières réelles ni changement de production.

## Résumé

| Priorité | Travail fait aujourd'hui | État réel |
|---|---|---|
| 1. Allocation des remboursements | Migration de protection, table privée de rapprochement, gel des payouts et absence de prorata ledger ; suite pgTAP passée sur base locale | **Protection en place dans la branche ; règles comptables finales et déploiement distant en attente** |
| 2. PostGIS | Vérification de la documentation Supabase actuelle et runbook/ticket prêts | **Demande Support non envoyée ; accès projet absent** |
| 3. Wave/CinetPay | Code v3 relu, CI Edge vérifiée, secrets requis et matrice de tests documentés | **Sandbox non exécutée ; comptes/identifiants inaccessibles** |

## 1. Remboursements — mitigation confirmée, modèle final encore bloqué

La migration `supabase/migrations/20261115191336_phase1_commerce_integrity_final.sql` :
- conserve les rapprochements dans `private.refund_accounting_reconciliations` ;
- place les remboursements non rejetés/annulés en `PENDING_ALLOCATION` ;
- garde les fonds vendeurs concernés bloqués et bloque un second remboursement fournisseur avant résolution ;
- retire de `complete_refund` le débit vendeur arbitraire au prorata de tous les groupes.

Le run [43754031145](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43754031145), commit `e0eac2cf7e15019b5cfa95304cffc6f209fe1875`, a réussi la reconstruction locale par migrations et la suite pgTAP (« All tests successful »).

Non terminés : snapshots financiers au checkout, allocation par article/quantité, prise en charge coupons/remises et livraison, convention SALE/COMMISSION, retour partiel, vendeur déjà payé, procédure de rapprochement autorisée. Ces règles demandent une décision métier/comptable ; aucune règle n'a été inventée. La migration n'a pas été appliquée à la base hébergée.

## 2. PostGIS — ticket prêt, intervention attendue

Le diagnostic du runbook AUD-01 décrit PostGIS 3.3.7 possédé par `supabase_admin`, trois colonnes geography et deux index GiST. La documentation Supabase actuelle confirme que Support peut déplacer l'extension vers `extensions` sans DROP/CREATE CASCADE et dans une transaction.

Le ticket à copier est dans `docs/runbooks/aud-01-postgis-schema-move.md` ; le formulaire direct est :
https://supabase.com/dashboard/support/new?projectRef=dzhhsoikzxibmngjzcch

Le connecteur Supabase retourne `projects: []`. Aucun ticket n'a été soumis et aucun SQL distant n'a été exécuté. Ne pas tenter de déplacer/supprimer l'extension soi-même.

## 3. Paiements — préparation sandbox

La CI Edge [run 43753543111](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43753543111) est verte sur le commit `bf42b629c89efbd2f909941a0a5a74966cb9ee17`. Aucun fichier Edge n'a changé entre ce commit et la tête `a61064c`.

Les secrets documentés sont `WAVE_API_KEY`, `WAVE_WEBHOOK_SECRET`, et `CINETPAY_API_KEY`, `CINETPAY_SITE_ID`, `CINETPAY_SECRET_KEY`. Leur présence n'a pas été vérifiée et aucun test marchand n'a été lancé. La disponibilité d'un environnement non financier Wave doit être confirmée avec le responsable de compte ; le mode sandbox CinetPay doit être confirmé pour la version d'API actuellement intégrée.

La matrice est documentée dans `docs/runbooks/aud-26-payment-sandbox-validation.md`. Les remboursements Wave partiels restent bloqués hors automatisation et CinetPay n'a pas de chemin automatique de remboursement validé.

## Aucun changement de production

Aucune migration Supabase distante, aucun ticket Support, aucune clé/secret, aucun appel Wave/CinetPay, aucun paiement/remboursement réel, aucun payout, aucun déploiement et aucun merge sur `main` n'ont été effectués. Les changements documentaires et la tête de branche sont limités à la branche de maintenance.

## Reprise suivante

Les trois chantiers ont été préparés au maximum possible avec les accès disponibles. La suite du projet peut reprendre avec les parcours GPS, iOS, notifications, E2E et les autres domaines restants, après obtention des accès et décisions nécessaires.