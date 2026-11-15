# Audit du workflow de remboursements administrateur — 16 novembre 2026

## Périmètre

Revue statique de :
- `lib/features/admin/presentation/admin_refunds_page.dart` ;
- `supabase/functions/execute-payment-refund/index.ts` ;
- `public.admin_begin_refund`, `public.admin_complete_manual_refund`, `public.complete_refund`, `public.get_admin_refunds` ;
- `private.refund_accounting_reconciliations` et son trigger dans `20261115191336_phase1_commerce_integrity_final.sql`.

## Correction de l'interface admin

L'écran affichait l'action « Exécuter » pour les remboursements `APPROVED`, `FAILED` et `PROCESSING`, sans distinguer les fournisseurs.

Or le contrat SQL de `admin_begin_refund` n'autorise le démarrage que depuis `REQUESTED` ou `APPROVED`. Un remboursement `FAILED` ou `PROCESSING` doit être rapproché avant une nouvelle tentative : l'interface ne doit pas proposer de relance automatique.

Par ailleurs, `execute-payment-refund` :
- exécute automatiquement le remboursement Wave uniquement ;
- renvoie les autres fournisseurs vers un parcours manuel ;
- garde un état `PROCESSING` en cas de résultat Wave inconnu (connexion/5xx), précisément pour empêcher un nouvel appel fournisseur aveugle.

Correction sur la branche :
- l'action « Exécuter » n'est désormais affichée que pour `provider = WAVE` et `status = APPROVED` ;
- pour les états `FAILED` ou `PROCESSING`, l'écran affiche un avertissement demandant de vérifier le statut chez le fournisseur ;
- le parcours manuel CinetPay reste distinct via `admin_complete_manual_refund`, qui exige un administrateur actif et une référence fournisseur.

Aucun appel de remboursement n'a été effectué pendant cette correction.

## Gel de rapprochement comptable

La migration `20261115191336_phase1_commerce_integrity_final.sql` crée une ligne privée de rapprochement pour chaque remboursement et garde les vendeurs de la commande en `PENDING_ALLOCATION`, sauf lorsqu'une demande est `REJECTED` ou `CANCELLED`.

La liste administrateur expose `accounting_status` et `accounting_note`, mais l'écran ne présente aucune action d'allocation ou de rapprochement pour passer un remboursement terminé à `RECONCILED`. La table est privée et les rôles `anon`/ `authenticated` n'ont aucun accès direct. Les RPC examinées ne montrent pas de procédure métier qui enregistre les allocations vendeur/article/quantité puis libère ce gel.

**Conséquence actuelle :** un remboursement exécuté/terminé continue de bloquer les retraits des vendeurs concernés tant que le rapprochement n'est pas traité par un mécanisme privilégié hors écran, ou tant qu'une fonctionnalité de rapprochement n'est pas construite. C'est une protection volontaire contre un débit erroné, mais aussi un blocage opérationnel à résoudre avant une utilisation financière complète.

Ne pas ajouter un bouton qui mettrait simplement `RECONCILED` sans allocations auditées. La résolution doit vérifier les articles, quantités, remises, frais de livraison, commissions et écritures, et doit être idempotente.

## Validation et limites

- Le fichier Flutter a été relu après modification.
- Aucun test widget dédié à `AdminRefundsPage` n'a été trouvé pendant cette passe.
- Aucun `flutter analyze`, `flutter test`, Deno test ou test pgTAP n'a été lancé dans cette passe.
- Aucune migration distante, aucun déploiement, aucun paiement ou remboursement réel, et aucune modification de `main` n'ont été effectués.
