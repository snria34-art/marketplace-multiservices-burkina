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
