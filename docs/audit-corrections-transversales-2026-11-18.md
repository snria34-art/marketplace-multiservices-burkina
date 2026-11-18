# AUD-04 — Corrections transversales et écarts restants

**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Périmètre :** remboursements, finance/retraits, notifications, messagerie, administration, verticales métier, portefeuille client et applications natives.

## Corrections versionnées dans cette passe

### Notifications
- Ajout de `public.notification_push_deliveries`, état par notification et appareil.
- La fonction `dispatch-push-notifications` ne renvoie pas les appareils déjà confirmés `SENT` quand un autre appareil doit être retenté.
- Les jetons invalides sont terminés et désactivés lorsque FCM renvoie `UNREGISTERED`.
- Le statut global `push_sent_at` n'est écrit qu'après un état terminal pour tous les appareils actifs ciblés.
- Test pgTAP de schéma et d'ACL ajouté.
- Runbook : `docs/runbooks/aud-03-notification-delivery.md`.

Limite : sémantique au moins une fois si la réponse FCM ou l'écriture SQL est perdue après acceptation du message ; un doublon reste possible dans ce cas. Les notifications historiques déjà marquées envoyées après un envoi partiel ne sont pas réouvertes automatiquement.

### Finance vendeur et retraits
- Écran vendeur : demande de retrait en XOF entier via `request_seller_payout_secure`, avec sélection Orange Money/Wave/Moov Money et affichage des erreurs de blocage de remboursement.
- Écran administrateur : file des retraits, confirmation manuelle avec référence du prestataire, ou déclaration d'échec via les RPC protégées existantes.
- Route `/admin/seller-payouts` ajoutée au routeur protégé et lien depuis le tableau de bord.
- Aucun paiement prestataire n'est déclenché par ces écrans : l'administrateur ne confirme qu'un paiement déjà exécuté hors de l'application.

**Blocage comptable non résolu :** deux fonctions de finalisation vendeur existent avec des conventions différentes, et aucun appelant interne n'a été trouvé. Le checkout conserve `orders.discount_total` au niveau commande sans ventilation immuable par groupe/article. Il serait dangereux de déclencher automatiquement le crédit `SALE` sur la base du subtotal brut ou de choisir une ventilation arbitraire. La règle de financement des remises doit être décidée, figée au checkout et testée avant d'automatiser les commissions et soldes.

### Messagerie
- L'écran de liste affiche maintenant un état d'erreur et un bouton de reprise au lieu de confondre erreur de lecture et absence de conversations.
- Le fil utilise déjà Realtime avec actualisation périodique de secours et marque les conversations lues via RPC.

Limites : pas de preuve d'essai multi-comptes, pièces jointes, modération, blocage utilisateur, accusés de lecture ou reprise hors ligne.

### Administration
- Ajout d'une interface de traitement des retraits vendeurs.
- Les actions utilisent les RPC administratives existantes et exigent une référence prestataire pour confirmer un retrait payé.

Limites : audit détaillé des rôles et tests des parcours de modération, comptes, partenaires, remboursements et réparations à poursuivre.

## Fonctionnalités encore incomplètes ou à certifier

| Domaine | État du code | Reste à faire |
|---|---|---|
| Remboursements | Allocation immuable, rapprochement, garde anti-double écriture et reprise Wave présents | Tests pgTAP réels, scénario provider inconnu, parcours client par article/quantité, retour partiel et remise/livraison |
| Finance vendeur | Solde ledger, demande de retrait, blocage sur remboursement et UI admin présents | Déclenchement de vente/commission après livraison avec règle de remise approuvée |
| Notifications | Push FCM, préférences, tokens et reprise par appareil présents | Migration + pgTAP, FCM/APNs réel, tests multi-appareils et appareil hors ligne |
| Messagerie | Conversations, messages, RPC de lecture, Realtime/polling présents | Tests RLS multi-comptes, pièces jointes, signalement, pagination et offline |
| Administration | Dashboard, comptes, catalogue, retours, remboursements, retraits, santé plateforme présents | Vérification exhaustive des permissions et journalisation des opérations sensibles |
| Restaurants | Consultation des restaurants, menus et plats présents | Panier/commande restaurant, paiement, suivi et disponibilité réelle |
| Transport | Liste des départs, réservation, billets et historique présents | Paiement, annulation/remboursement, validation réelle du billet et tests de concurrence |
| Mécaniciens | Recherche, demande, disponibilité, devis et acceptation présents | Cycle complet de mission, paiement, preuve d'intervention et litige |
| Achats groupés | Liste active et adhésion transactionnelle présentes | Paiement, seuil atteint/non atteint, expiration, annulation et remboursement automatique contrôlé |
| Portefeuille client | Page volontairement désactivée | Modèle de compte, ledger client, dépôts confirmés, paiement par solde, remboursement, limites et rapprochement |
| Android | Manifest, permissions, deep links et build Debug disponibles | Tests appareils, notification, GPS arrière-plan et build signé |
| iOS | Projet, AppDelegate, permissions, deep links et modes arrière-plan présents | Build iOS Simulator, tests iPhone/APNs/GPS et signature de distribution |

## Validation

- Les corrections Edge ont un run Supabase Edge Functions CI réussi sur le commit `fdfd68e`.
- Une première Flutter CI a échoué à cause d'un callback `onRetry` manquant dans la liste des conversations ; le raccordement a été corrigé dans un commit ultérieur.
- Les nouvelles exécutions Flutter et Android sur la tête la plus récente doivent être consultées avant de déclarer le code validé.
- Le test pgTAP des notifications et les tests de remboursement restent non exécutés ici.
- Aucune migration distante, aucun déploiement, aucun paiement réel, aucun appel FCM/APNs et aucune publication native n'ont été effectués.

## Prochain ordre de correction

1. Vérifier les derniers runs Flutter et Android, puis corriger tous les diagnostics introduits par ces changements.
2. Finaliser la politique comptable de remise et connecter la finalisation vendeur après livraison sans double écriture.
3. Étendre les tests de remboursements et les parcours client par article/quantité.
4. Ajouter commande restaurant et paiement/annulation pour transport, mécaniciens et achats groupés.
5. Concevoir le portefeuille client comme un ledger séparé, sans jamais réutiliser le solde vendeur.
6. Exécuter les tests iOS/Android sur environnements de test et appareils physiques.
