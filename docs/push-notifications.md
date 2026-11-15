# Notifications push — état de référence

Dernière vérification : 6 novembre 2026.

## Architecture

- Firebase Cloud Messaging (FCM) délivre les notifications push Android et iOS.
- Flutter demande l'autorisation, récupère le token FCM et l'enregistre dans `notification_devices` via `register_notification_device`.
- La rotation du token FCM est synchronisée avec Supabase.
- Les préférences `notification_preferences` sont appliquées côté serveur.
- L'insertion dans `notifications` déclenche le worker `dispatch-push-notifications` via le trigger et `pg_net`.
- Le job Supabase Cron relance périodiquement les notifications éligibles non envoyées.
- Au premier plan, Flutter utilise `flutter_local_notifications`; en arrière-plan, FCM fournit le contenu système et les données de navigation.

## Dépendances Flutter

Les versions déclarées dans `pubspec.yaml` :

- `firebase_core` : 4.15.0
- `firebase_messaging` : 16.7.0
- `flutter_local_notifications` : 22.3.1

Le service Flutter intercepte les erreurs d'initialisation Firebase. Si la configuration native Firebase est absente, les notifications sont désactivées sans empêcher l'application de démarrer. Cela ne signifie pas que FCM est opérationnel.

## Configuration externe obligatoire

Pour activer réellement FCM, le propriétaire du projet doit :

1. Associer les applications Android et iOS au vrai projet Firebase, avec les identifiants de package et Bundle ID exacts.
2. Générer les fichiers officiels `google-services.json`, `GoogleService-Info.plist` et `firebase_options.dart` depuis ce projet.
3. Configurer APNs pour iOS et activer Firebase Cloud Messaging API.
4. Créer un compte de service dédié avec le minimum de permissions nécessaires pour envoyer les messages.
5. Ajouter le JSON du compte de service uniquement dans Supabase Edge Function Secrets sous `FCM_SERVICE_ACCOUNT_JSON`.

Ne jamais inventer ces fichiers, committer un compte de service, ou inclure une clé privée Firebase dans l'application mobile. Ne jamais envoyer un secret dans le chat ou un ticket.

## État serveur vérifié

- Edge Function : `dispatch-push-notifications`, **version 10 ACTIVE**.
- Code source : `supabase/functions/dispatch-push-notifications/index.ts`.
- Concurrence limitée à cinq notifications et cinq appareils par notification.
- Les erreurs d'envoi sont isolées par appareil ; les jetons invalides peuvent être désactivés.
- Le worker ne journalise pas les jetons FCM ni la clé privée.
- `verify_jwt=false` est intentionnel pour l'appel serveur interne. Le worker vérifie séparément le secret applicatif avec `verify_push_dispatch_secret`. Ne pas supprimer ce contrôle.
- Le code de production version 10 correspond au code versionné dans GitHub lors de la dernière vérification.

## Blocage opérationnel confirmé

Les journaux de la version 10 indiquent :

- `fcm_service_account_missing`
- `hasFcmProjectId: false`

Le secret `FCM_SERVICE_ACCOUNT_JSON` et l'identifiant de projet FCM de secours `FCM_PROJECT_ID` ne sont pas présents dans l'environnement observé. Le worker renvoie donc volontairement HTTP 503 au lieu de prétendre qu'une notification a été envoyée.

Le connecteur Supabase disponible ici permet de lire et déployer des fonctions, mais ne fournit pas d'action de gestion des secrets Edge Function. Aucun secret n'a été lu, créé ou modifié pendant cette intervention.

## Limites fonctionnelles restantes

- La réception réelle sur un téléphone Android/iOS n'est pas validée tant que les fichiers natifs Firebase, APNs et le compte de service ne sont pas configurés.
- L'état d'envoi est actuellement principalement conservé au niveau de la notification. Un suivi durable et idempotent par couple notification/appareil reste à concevoir pour pouvoir reprendre précisément les appareils en échec sans renvoyer aux appareils ayant déjà reçu le message.
- Aucun envoi de test, envoi de masse ou workflow de build n'a été lancé dans le cadre du contrôle.

## Vérification après configuration

Une fois les éléments Firebase fournis et installés par le propriétaire :

1. Vérifier la présence des secrets côté Supabase sans afficher leurs valeurs.
2. Vérifier que le `project_id` du compte de service correspond au projet Firebase.
3. Envoyer une seule notification à un appareil de test autorisé.
4. Contrôler les journaux, la réception et l'ouverture de la bonne route.
5. Vérifier que les erreurs de santé de la fonction disparaissent.

La version 10 corrige la concurrence et l'isolation des erreurs serveur ; elle ne remplace pas la configuration Firebase et ne prouve pas la réception sur appareil.


## Déconnexion et propriété du token — contrôle du 6 novembre 2026

L'événement Supabase `signedOut` est émis après la suppression de la session. Une RPC qui filtre le token par `auth.uid()` ne peut donc pas être appelée à ce moment avec l'identité de l'utilisateur.

Le service Flutter expose maintenant `signOutAndDeactivateCurrentDevice()` :

1. Appeler `deactivate_notification_device` pendant que la session est toujours active.
2. Interrompre la déconnexion si le serveur ne confirme pas la désactivation, afin de permettre une nouvelle tentative.
3. Appeler `auth.signOut()` seulement après la désactivation.

Le listener `signedOut` ne tente plus une RPC tardive. Les futurs boutons et menus de déconnexion doivent utiliser cette méthode. L'intégration des interfaces et les scénarios de session expirée/perte réseau sont suivis dans Linear **RIA-26**. Aucun parcours complet de déconnexion n'a encore été testé sur appareil.


Le listener `onAuthStateChange` possède également un gestionnaire `onError` explicite. Les erreurs de rafraîchissement ou de réseau transmises par le flux sont journalisées en mode debug au lieu de devenir des exceptions non gérées. Aucun token ni contenu privé n'est journalisé.

## Addendum — contrôle de reprise et fiabilité par appareil (16 novembre 2026)

La relecture de `dispatch-push-notifications/index.ts` met en évidence une limite supplémentaire : quand plusieurs appareils sont ciblés, le worker renseigne `push_sent_at` dès qu'au moins un appareil a reçu le message. Les appareils en échec ne seront donc plus repris par la file Cron, même si `push_error` indique une erreur. C'est une perte possible de notifications sur les appareils concernés.

**Correction cible requise :** table de livraison durable, privée et idempotente par couple `notification_id + device_id`, avec état `PENDING / PROCESSING / SENT / RETRYABLE_FAILURE / PERMANENT_FAILURE`, compteur et timestamp de reprise. Une notification ne doit être considérée comme finalisée que lorsque chaque appareil ciblé est livré ou explicitement abandonné après une erreur permanente/limite de tentatives. La reprise ne doit renvoyer que les appareils non livrés.

**Pourquoi cette correction n'est pas commitée dans le worker aujourd'hui :** elle nécessite une migration SQL, des RPC atomiques de claim/finalisation, des tests pgTAP sur concurrence/rejeu et un test Deno de l'orchestration. Le CLI Supabase et un projet isolé ne sont pas accessibles depuis cette session ; introduire cette migration sans exécuter sa suite locale créerait un risque de régression sur la file de notifications. Le comportement existant est donc signalé comme bloquant, sans patch incomplet.

Le blocage Firebase demeure également : compte de service FCM, identifiant projet et fichiers de configuration natifs ne sont pas présents dans le dépôt. Aucun envoi de test n'a été effectué.

### Contrôles de code à garder

- Ne jamais journaliser un token FCM, un JWT ou la clé privée.
- Garder `verify_push_dispatch_secret` et l'exécution service-role uniquement.
- Désactiver les tokens explicitement déclarés `UNREGISTERED` par FCM.
- Un échec de notification ne doit ni bloquer l'application ni être présenté comme une livraison réussie.
