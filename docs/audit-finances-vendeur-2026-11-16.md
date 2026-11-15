# Audit du solde vendeur, des commissions et des retraits — 16 novembre 2026

## Périmètre

Revue statique de la branche `maintenance/audit-01-07-2026-11-15` :
- RPC `request_seller_payout_secure` et fonctions d'administration du cycle de vie des retraits ;
- migrations de registre vendeur et de commission ;
- migration `20261115191336_phase1_commerce_integrity_final.sql` ;
- `SellerRepository`, `SellerDashboardPage`, `SellerFinancePage` et `CustomerWalletPage` ;
- contrats pgTAP de sécurité et d'intégrité commerciale.

## Contrôles satisfaisants

### Demande de retrait vendeur

La définition la plus récente de `request_seller_payout_secure` :
- exige un compte actif ;
- vérifie que le vendeur appartient à l'utilisateur et que son statut est `VERIFIED` ;
- verrouille la ligne vendeur avec `FOR UPDATE`, ce qui sérialise les demandes concurrentes de ce vendeur ;
- valide un montant strictement positif et un opérateur dans la liste autorisée ;
- bloque tout retrait lorsqu'un rapprochement de remboursement lié à ce vendeur reste `PENDING_ALLOCATION` ;
- recalcule le solde avec `sum(seller_ledger.amount)`, refuse un retrait supérieur au solde, puis crée la demande `PENDING` et l'écriture négative `PAYOUT` dans la même transaction.

Le contrôle côté serveur est donc plus strict que le simple montant affiché par Flutter. Le client ne peut pas augmenter lui-même le solde ou contourner le plafond du retrait par une valeur manipulée.

### Cycle administratif du retrait

Les RPC `admin_mark_seller_payout_paid` et `admin_mark_seller_payout_failed` verrouillent le retrait et contrôlent son statut. Le marquage payé exige une référence fournisseur ; le marquage échoué écrit une contrepassation `PAYOUT_REVERSAL`. La migration `20261105192629_restrict_sensitive_admin_actions_to_active_admin_users.sql` remplace le contrôle générique de modérateur par `private.is_admin()` pour ces opérations financières.

### Remboursements et gel comptable

La migration `20261115191336_phase1_commerce_integrity_final.sql` améliore le traitement des remboursements :
- le rapprochement `private.refund_accounting_reconciliations` est dans un schéma privé, protégé par RLS et sans accès direct des rôles clients ;
- le trigger `trg_sync_refund_accounting_hold` crée ou actualise l'état de rapprochement ;
- un remboursement non rejeté/non annulé reste `PENDING_ALLOCATION` tant que les vendeurs, articles, quantités, remises et commissions ne sont pas ventilés ;
- `complete_refund` ne crée plus de débit vendeur arbitraire dans `seller_ledger` ;
- les retraits des vendeurs concernés et un autre départ de remboursement fournisseur sur le même paiement sont bloqués tant que le rapprochement est en attente ;
- les demandes rejetées ou annulées passent à `RECONCILED`.

Le contrat `phase1_commerce_integrity_test.sql` annonce 20 assertions, notamment sur le caractère privé du gel, le blocage des retraits et l'absence d'écritures vendeur inventées par `complete_refund`. Il s'agit d'assertions présentes dans le dépôt ; leur présence n'est pas une preuve de réussite sur le dernier commit.

## Blocage fonctionnel à résoudre : comptabilisation des ventes livrées

Deux fonctions historiques de finalisation existent, avec des conventions comptables différentes :

1. `finalize_seller_group(uuid,numeric)` : après vérification que le groupe est `DELIVERED`, inscrit le `SALE` brut et une écriture `COMMISSION` négative séparée ; la commission passe à `POSTED`.
2. `finalize_seller_group_financials(uuid)` : après la même vérification, lit `platform_settings.default_commission_rate`, inscrit le `SALE` net et conserve la commission séparément avec le statut `PENDING`.

Les deux fonctions sont réservées à `service_role`. Elles ne doivent pas être appelées toutes les deux pour le même groupe : leurs conventions de solde sont différentes.

Dans les sources vérifiées :
- la migration de livraison `20261115191336_phase1_commerce_integrity_final.sql` ne contient aucune référence à l'une ou l'autre des deux finalisations ;
- `sync_after_package_delivery` met à jour l'affectation du livreur puis appelle `sync_parent_order_status` ; il ne poste pas de vente ni de commission ;
- aucune référence d'appel dans les sources Flutter/Edge ou dans les migrations récentes n'a été identifiée pendant cette revue.

**Conséquence possible :** si aucun orchestrateur externe non versionné n'appelle une de ces fonctions après livraison, les groupes livrés n'alimentent pas automatiquement `seller_ledger`. Le solde vendeur et le montant disponible au retrait peuvent alors rester nuls ou incomplets malgré des commandes livrées. La présence d'un solde vendeur positif ne doit pas être supposée à partir du seul statut `DELIVERED`.

Cette absence d'appel dans le dépôt n'exclut pas un appel externe hors dépôt. Il faut confirmer le backend réellement déployé avant d'ajouter un appel automatique ou de modifier le calcul des commissions.

## Interface Flutter observée

- Le tableau de bord vendeur affiche le solde et permet de demander un retrait via Orange Money, Wave ou Moov Money.
- `SellerFinancePage` montre le solde, les demandes de retrait et un extrait du registre.
- `SellerRepository.balance` lit le registre par pages et calcule un total pour l'affichage. La décision d'autoriser le retrait reste correctement recalculée dans la RPC.
- `CustomerWalletPage` indique explicitement que le portefeuille client n'est pas activé et qu'aucun dépôt, retrait ou transfert n'est disponible. Il ne confond pas le solde vendeur avec un portefeuille client.

## Décisions nécessaires avant activation financière complète

1. Confirmer si un système serveur hors dépôt déclenche déjà la finalisation des commissions à la livraison.
2. Retenir une convention comptable unique : `SALE` brut + `COMMISSION` négative, ou `SALE` net avec commission conservée à part.
3. Définir le traitement des commissions à taux nul, des remises et des frais de livraison.
4. Ajouter un test transactionnel de livraison répétée garantissant une seule comptabilisation par groupe.
5. Tester une commande multi-boutiques, livraison partielle, annulation, remboursement en attente, puis retrait vendeur.
6. Vérifier que le parcours d'administration du retrait correspond à une confirmation réelle du fournisseur, sans considérer la simple action `PAID` comme une preuve de virement externe.

Aucune écriture financière, demande de retrait ou opération fournisseur n'a été déclenchée pendant cet audit. Aucun correctif applicatif de comptabilisation n'a été ajouté, car choisir entre les deux conventions sans validation comptable ni traçage du backend actif pourrait produire un double crédit ou un solde erroné.

## Validation

- Les définitions SQL et fichiers Flutter ont été relus depuis la branche de maintenance.
- Le test pgTAP contient 20 assertions déclarées dans le fichier, mais il n'a pas été exécuté dans cette passe.
- Aucun `flutter analyze`, test Flutter, Deno test ou scénario de paiement réel n'a été exécuté.
- Aucun déploiement, aucune migration Supabase distante et aucune modification de `main` n'ont été effectués.
