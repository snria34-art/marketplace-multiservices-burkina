# Suivi des travaux — GPS, notifications, iOS et E2E — 16 novembre 2026

**Branche de travail :** `maintenance/audit-01-07-2026-11-15`  
**Tête examinée avant ce rapport :** `29872b7e84fe5fbf643911c03be6ac7f336fab44`  
**Branche principale :** `main` au commit `9b70580f322814d6decf9eeac2e5d93aa01e44e9`.

## 1. GPS livreur — correction ajoutée, validation finale en attente

Le commit `dc9a2dd5bd8561a3f97e60da7ee697e718fe3a5e` a ajouté `WidgetsBindingObserver` à `CourierPage` et recharge les affectations lorsque l'application revient à l'état `resumed`. Si aucune mission active ne reste, l'abonnement GPS est annulé ; en cas d'échec réseau, l'interface signale que le serveur continue à vérifier chaque position.

Les premiers tests ont révélé deux problèmes dans le test/rafraîchissement :
- l'événement lifecycle devait être déclenché directement dans le test widget pour être déterministe ;
- un Future déjà terminé passé à `FutureBuilder` après l'`await` ne rafraîchissait pas l'écran de façon fiable.

Le correctif `22576df1ae0db479ba4633c8425b696ebf20a248` transmet maintenant le Future avant de l'attendre, et le test vérifie le second appel au dépôt ainsi que la disparition de la mission terminée. **La réussite de ce test n'est pas encore confirmée par une CI terminée.**

### CI observée

- [Run Flutter 43768443214](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43768443214) : échec initial du nouveau test.
- [Run Flutter 43769174601](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43769174601) : analyse réussie, test encore échoué sur l'actualisation du FutureBuilder.
- [Run Flutter 43769409722](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43769409722), commit `22576df` : la CI a été annulée lors de commits suivants avant d'apporter un résultat final.
- [Run Flutter 43769537460](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43769537460), commit `29872b7` : nouveau run après les corrections GPS et les derniers changements du panier ; encore `in_progress` au dernier relevé.
- [Run Android 43768409218](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43768409218), commit `dc9a2dd` : **Build Android Debug APK réussi**. Il s'agit du commit de la première correction GPS, antérieur au correctif FutureBuilder.
- [Run Android 43769537440](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43769537440), commit `29872b7` : nouveau build après les dernières modifications ; encore `in_progress` au dernier relevé.

Le job iOS a été ignoré sur ces pushs parce que le workflow le réserve à `workflow_dispatch`. Aucun build iOS n'est déclaré réussi.

## 2. Notifications push — anomalie de reprise identifiée, correction de fond non engagée

La relecture de `supabase/functions/dispatch-push-notifications/index.ts` confirme qu'une notification multi-appareils est marquée `push_sent_at` dès qu'au moins un appareil réussit. Les appareils qui échouent peuvent alors être exclus des reprises Cron. Le runbook `docs/push-notifications.md` décrit le suivi idempotent cible par paire `notification_id + device_id`.

La correction complète exige une migration SQL de suivi par appareil, des RPC atomiques de claim/finalisation et des tests pgTAP/Deno de concurrence et reprise. Le CLI Supabase et un projet staging isolé ne sont pas accessibles dans cette session ; aucune migration SQL non testée n'a été ajoutée. Les secrets Firebase/APNs restent non vérifiés. Aucun envoi de test n'a été effectué.

## 3. iOS — configuration statique relue, build non exécuté

Le dépôt contient :
- les descriptions de permissions de localisation Always/When-In-Use ;
- le mode `location` dans `UIBackgroundModes` ;
- `Runner.entitlements` avec `aps-environment` et sa référence dans le projet Xcode ;
- Bundle ID `com.marketplaceburkina.marketplaceMultiservicesBurkina` et cible minimum statique iOS 15.0.

Le job iOS Simulator Debug est réservé à `workflow_dispatch` et a été ignoré sur les pushs de maintenance. Il n'a pas été déclenché ici. `GoogleService-Info.plist` et la configuration Firebase générée ne sont pas dans le dépôt. Le runbook `docs/runbooks/aud-28-ios-build-and-device-validation.md` décrit les étapes macOS et appareil.

## 4. Tests E2E — scénarios documentés, aucune exécution staging

Le dépôt ne contient pas de répertoire `integration_test/` et aucun compte/projet staging vérifié n'est accessible. Les parcours client, vendeur, coursier, admin/modérateur, webhook, retours, notifications, sécurité RLS/Storage et GPS sont décrits dans `docs/runbooks/aud-27-e2e-staging-validation.md`. Ces scénarios ne seront marqués réussis qu'après exécution sur staging avec des données fictives.

## 5. Fichiers de suivi

- `docs/push-notifications.md` : anomalie des livraisons partielles et architecture cible.
- `docs/runbooks/aud-14-courier-background-location.md` : revalidation des affectations à la reprise.
- `docs/runbooks/aud-27-e2e-staging-validation.md` : plan E2E staging.
- `docs/runbooks/aud-28-ios-build-and-device-validation.md` : vérification iOS Debug/appareils.

## 6. Limites opérationnelles

- Aucun accès au projet Supabase hébergé, aucune modification de secrets, aucune migration distante.
- Aucun paiement/remboursement réel, aucun payout et aucun envoi FCM de test.
- Aucun build Release, certificat, upload de store ou déploiement.
- Aucun merge vers `main`. Son SHA reste `9b70580f322814d6decf9eeac2e5d93aa01e44e9`.

## Addendum — dernières corrections et contrôles (16 novembre 2026)

### GPS / écran livreur

Après trois itérations de test qui ont révélé une actualisation visuelle non fiable dans `FutureBuilder`, l'écran `CourierPage` a été refactoré pour conserver explicitement :
- les affectations actuellement chargées ;
- l'état de chargement ;
- l'erreur initiale.

Le retour au premier plan relit les affectations puis met à jour directement cet état. La même source d'état est maintenant utilisée après une action du livreur (acceptation, retrait, démarrage ou livraison). Si la dernière mission disparaît, le partage GPS local est arrêté ; le serveur continue d'exiger une affectation active lors de chaque écriture de position.

Le test widget de reprise utilise un `Completer` pour maîtriser la fin de la requête. Les runs antérieurs ont échoué successivement sur l'actualisation du FutureBuilder, puis l'analyse a détecté une dernière référence `_future` dans le chemin d'action manuel ; cette référence a été corrigée.

### Résultats CI sur le dernier code observé

- [Flutter CI #43770753158](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43770753158), commit `b05b3ca597603ccba68fb1a866a9b9d8ab981c56` : dernière lecture, analyse réussie et tests en cours ; le run n'a pas encore fourni de conclusion.
- [Android Debug #43770753190](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43770753190), même commit : compilation APK en cours ; aucune conclusion au dernier relevé.
- [Android Debug #43768409218](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43768409218), commit antérieur `dc9a2dd5` : APK Debug réussi pour la première modification GPS, mais avant le refactoring de l'écran.
- Le job iOS reste ignoré sur les événements push et n'a pas été exécuté en mode manuel.

Ne pas annoncer le test widget, le build Android du commit courant ni le build iOS comme réussis avant une conclusion CI correspondante.

### Paiement concurrent — clarification

L'audit de checkout a été complété. La migration `20261116120000_prevent_competing_payment_sessions.sql` mentionnée dans la première version du rapport n'existe pas dans l'arbre Git actuel. La fonction déjà versionnée dans `20261115191336_phase1_commerce_integrity_final.sql` refuse une référence fournisseur différente lorsque `provider_reference` est déjà enregistré (`payment_checkout_reference_conflict`). Le contrat `order_delivery_contract_test.sql` est maintenant porté à 14 assertions et contrôle cette immutabilité.

Cette assertion pgTAP n'a pas été exécutée après modification. La garde SQL empêche le remplacement de la référence enregistrée, mais la création d'une session fournisseur précède cette garde : des objets externes concurrents peuvent encore être créés avant que seul le premier ne soit associé en base. L'objet perdant peut devenir orphelin ; un protocole de claim idempotent avant l'appel fournisseur reste nécessaire.

### Remboursements et finances vendeurs

- L'écran admin n'affiche « Exécuter » que pour les remboursements Wave approuvés. CinetPay reste sur confirmation manuelle et les états ambigus/échoués ne sont pas relancés automatiquement.
- La table privée `PENDING_ALLOCATION` continue de bloquer les retraits vendeurs tant que les allocations comptables ne sont pas validées. Aucune action de libération sommaire n'a été ajoutée.
- L'audit vendeur n'a pas trouvé d'appel versionné aux routines `finalize_seller_group` ou `finalize_seller_group_financials` au moment de la livraison. Deux conventions de ledger existent ; aucune n'est déclenchée dans le parcours versionné examiné. Il faut confirmer le backend externe et faire approuver une convention comptable avant d'ajouter une écriture automatique.

### Périmètre inchangé

Aucune migration hébergée, aucun changement de secrets, aucun paiement/remboursement réel, aucun payout, aucun build Release, aucun déploiement et aucun merge vers `main`. La branche principale reste séparée de la maintenance.
