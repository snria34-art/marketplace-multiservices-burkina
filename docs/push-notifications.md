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

## Raccordement des configurations natives Firebase

Le dépôt conserve séparément la configuration publique de chaque application cliente et les identifiants privés du serveur d'envoi.

Projet Firebase utilisé : `marketplace-multiservices-bf`.

Identifiants des applications à rattacher à ce même projet :

- Android : `com.marketplaceburkina.marketplace_multiservices_burkina` — application enregistrée et fichier officiel `android/app/google-services.json` ajouté à cette branche.
- iOS : `com.marketplaceburkina.marketplaceMultiservicesBurkina` — application enregistrée et fichier officiel `ios/Runner/GoogleService-Info.plist` ajouté à cette branche.

Emplacements attendus :

- Android : `android/app/google-services.json`
- iOS : `ios/Runner/GoogleService-Info.plist`, associé à la cible Runner dans Xcode.
- Configuration Flutter multiplateforme : générer `lib/firebase_options.dart` avec `flutterfire configure` depuis la racine du projet, en sélectionnant le projet Firebase existant et les applications Android/iOS déjà enregistrées.

Le plug-in Google Services Gradle `4.6.0` est préparé dans la configuration Android. Il est appliqué uniquement lorsque `android/app/google-services.json` est présent ; les compilations de maintenance sans fichier Firebase restent ainsi indépendantes de cette configuration.

Les fichiers de configuration clients Firebase contiennent des identifiants propres à l'application, pas le compte de service d'envoi. Le compte de service JSON est un secret privé : ne pas le mettre dans GitHub, Railway, Flutter ou le bundle mobile. Il doit rester dans les secrets des Supabase Edge Functions sous `FCM_SERVICE_ACCOUNT_JSON`. Le code récupère normalement le `project_id` depuis ce JSON ; `FCM_PROJECT_ID` sert de valeur de secours facultative.

État de cette branche : la structure Gradle Android est préparée et les deux fichiers de configuration clients officiels sont présents : `android/app/google-services.json` et `ios/Runner/GoogleService-Info.plist`. Le project ID, le package Android et le Bundle ID iOS ont été vérifiés. Le plist iOS est référencé dans `ios/Runner.xcodeproj/project.pbxproj` comme ressource de la cible Runner. La génération de `lib/firebase_options.dart` avec FlutterFire reste à effectuer. Aucune valeur Firebase n'a été inventée.

## Configuration externe obligatoire

Pour activer réellement FCM, le propriétaire du projet doit :

1. Vérifier les applications Android et iOS enregistrées dans `marketplace-multiservices-bf` avec leurs identifiants exacts.
2. Conserver les fichiers officiels Android et iOS déjà ajoutés, confirmer que le plist est inclus dans les ressources Runner, puis générer `firebase_options.dart` avec FlutterFire.
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

- La réception réelle sur appareil n'est pas encore validée : les fichiers de configuration clients Android et iOS sont présents, mais les options Flutter restent à générer, la configuration APNs et le compte de service FCM côté serveur restent nécessaires, et aucun test sur téléphone n'est revendiqué.
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

Le blocage Firebase demeure également : le compte de service FCM n'est pas disponible dans les secrets serveur observés et les options Flutter restent à générer. Les fichiers de configuration clients Android et iOS sont présents, mais cela ne configure ni APNs ni le compte de service. Aucun envoi de test n'a été effectué.

### Contrôles de code à garder

- Ne jamais journaliser un token FCM, un JWT ou la clé privée.
- Garder `verify_push_dispatch_secret` et l'exécution service-role uniquement.
- Désactiver les tokens explicitement déclarés `UNREGISTERED` par FCM.
- Un échec de notification ne doit ni bloquer l'application ni être présenté comme une livraison réussie.
