# Notifications push

## Architecture

- Firebase Cloud Messaging (FCM) gère les notifications Android/iOS.
- Le token FCM est enregistré dans notification_devices via register_notification_device.
- Le token est actualisé à chaque rotation FCM.
- Les préférences notification_preferences sont appliquées côté serveur avant l'envoi.
- Une notification insérée dans notifications déclenche automatiquement dispatch-push-notifications via pg_net.
- Supabase Cron relance les notifications non envoyées chaque minute.
- Quand l'application est ouverte, Flutter affiche aussi une notification locale.
- Quand l'application est en arrière-plan ou terminée, le payload FCM contient notification + data pour permettre l'affichage système et la navigation au clic.

## Dépendances

- firebase_core 4.15.0
- firebase_messaging 16.7.0
- flutter_local_notifications 22.3.1

Ces versions correspondent aux versions stables publiées actuellement sur pub.dev. FCM Flutter nécessite firebase_core et les plateformes natives doivent être configurées.

## Configuration Firebase

1. Créer un projet Firebase pour l'application.
2. Ajouter les applications Android et iOS au projet Firebase.
3. Exécuter flutterfire configure depuis la racine du projet pour générer la configuration Flutter officielle.
4. Pour iOS, activer Push Notifications et Remote notifications dans Xcode et téléverser la clé APNs dans Firebase.
5. Pour Android, inclure la configuration Firebase générée pour l'application.
6. Configurer Cloud Messaging API.
7. Créer un compte de service disposant de la permission cloudmessaging.messages.create.
8. Ajouter le JSON du compte de service comme secret Edge Function `FCM_SERVICE_ACCOUNT_JSON`.

## Secrets

Ne jamais committer le JSON du compte de service Firebase.

`FCM_SERVICE_ACCOUNT_JSON` doit rester dans les secrets Supabase Edge Functions.

Le secret interne `push_dispatch_secret` est déjà créé dans Supabase Vault pour les appels Postgres vers l'Edge Function.

## Fonctionnement

Quand une ligne est créée dans notifications :

notifications -> trigger SQL -> pg_net -> dispatch-push-notifications -> FCM -> téléphone.

Si l'envoi échoue, push_attempts et push_error sont conservés. Cron relance les notifications non envoyées jusqu'à 20 tentatives.

## Limitation actuelle

Le code serveur et Flutter sont prêts, mais l'activation réelle sur les téléphones dépend encore du projet Firebase, des fichiers de configuration Android/iOS et du compte de service Firebase. Ces éléments ne peuvent pas être inventés sans créer le projet Firebase réel.

## État opérationnel vérifié — 6 novembre 2026

- La fonction Supabase `dispatch-push-notifications` a été synchronisée depuis `supabase/functions/dispatch-push-notifications/index.ts` et est maintenant déployée en **version 8**.
- Cette version inclut une limite de concurrence de cinq notifications simultanées et une gestion plus robuste des erreurs par appareil.
- Le paramètre `verify_jwt=false` est conservé : l'endpoint est appelé par le trigger serveur et vérifie son secret dédié dans le corps de la fonction. Ne pas retirer ce contrôle.
- Les journaux du 6 novembre montrent encore des réponses HTTP 503 de l'ancienne version 7 avant la synchronisation. Le contrôle Health Supabase continue de signaler un taux d'échec élevé après le déploiement ; aucun envoi réel n'a été provoqué pour tester la nouvelle version.
- Le blocage de configuration confirmé dans l'audit précédent reste à lever : le secret `FCM_SERVICE_ACCOUNT_JSON` et les paramètres du projet Firebase doivent être renseignés dans le gestionnaire de secrets Supabase. Le JSON du compte de service ne doit jamais être ajouté à GitHub.
- Les fichiers Firebase natifs Android/iOS doivent également être générés depuis le véritable projet Firebase. Ne pas fabriquer de faux fichiers ou de faux identifiants.

### Étapes de finalisation (sans déclencher de campagne)

1. Configurer le projet Firebase réel et les applications Android/iOS.
2. Ajouter le secret `FCM_SERVICE_ACCOUNT_JSON` dans Supabase Edge Function Secrets.
3. Ajouter la clé APNs à Firebase pour iOS et vérifier les configurations natives.
4. Lorsqu'un appareil de test sera prêt et que l'utilisateur autorisera une vérification, envoyer une seule notification de test contrôlée.
5. Vérifier la réception, puis confirmer que le taux d'erreur Health revient à la normale.

**Important :** le déploiement version 8 synchronise le code, mais ne peut pas remplacer les secrets Firebase manquants et ne prouve pas encore la réception d'une notification sur un téléphone.

## Diagnostic et correction restante — 6 novembre 2026

### Ce qui fonctionne côté serveur

- Le job pg_cron numéro 1 est actif et s'exécute chaque minute.
- Il appelle `/functions/v1/dispatch-push-notifications`.
- Les appels de vérification `verify_push_dispatch_secret` retournent HTTP 200 dans les journaux observés entre 14:29 et 14:38 UTC.
- La fonction est déployée en version 8 (ACTIVE), avec `verify_jwt=false` et le contrôle applicatif du secret conservé.

### Blocage restant

La configuration Firebase n'est pas présente dans le dépôt : `google-services.json`, `GoogleService-Info.plist` et `firebase_options.dart` doivent provenir du projet Firebase réel. Le compte de service FCM doit être installé dans les secrets Supabase. Sans ces éléments, l'API FCM ne peut pas authentifier les envois.

### Procédure de finalisation sans exposer de clé

1. Dans Firebase Console, ouvrir le projet réel de Marketplace Burkina (ou le créer si aucun projet n'existe).
2. Enregistrer l'application Android avec son identifiant de package exact et l'application iOS avec son Bundle ID exact.
3. Télécharger `google-services.json` et `GoogleService-Info.plist`, puis générer `firebase_options.dart` avec FlutterFire CLI. Ces fichiers doivent correspondre aux identifiants natifs du dépôt.
4. Dans Google Cloud Console du même projet, activer Firebase Cloud Messaging API et créer un compte de service avec uniquement la permission nécessaire pour envoyer des messages FCM (`cloudmessaging.messages.create`).
5. Générer une clé JSON pour ce compte de service. Ne pas la coller dans le chat, dans GitHub, dans un ticket ou dans un fichier source.
6. Dans Supabase Dashboard → projet `dzhhsoikzxibmngjzcch` → Edge Functions → Secrets, créer `FCM_SERVICE_ACCOUNT_JSON` avec le contenu JSON complet. Le champ `project_id` du JSON doit correspondre au projet Firebase. Le code lit aussi `FCM_PROJECT_ID` comme solution de repli si nécessaire.
7. Après configuration, vérifier les journaux et envoyer au maximum une notification de test vers un appareil de test explicitement choisi. Ne pas lancer de test de masse.

### Protection des clés

- Ne jamais committer le JSON du compte de service.
- Ne jamais utiliser une clé Firebase Admin dans Flutter ou dans une application mobile.
- Limiter l'accès au secret Supabase aux personnes qui administrent le projet.
- Si une clé de service est exposée, la révoquer immédiatement dans Google Cloud IAM et en générer une nouvelle.

### État

Le worker backend est déployé en version 8. La configuration Firebase et les fichiers natifs réels restent à fournir par le propriétaire du projet Firebase. Aucune notification de test ni notification de masse n'a été envoyée pendant ce diagnostic.


## Correctif opérationnel du 6 novembre 2026 — version 10

La fonction `dispatch-push-notifications` est maintenant déployée en **version 10 (ACTIVE)**.

### Changements de code vérifiés

- Synchronisation du code de production version 9 avec le dépôt.
- Limitation à cinq notifications traitées simultanément.
- Limitation à cinq appareils traités simultanément par notification.
- Isolation des erreurs au niveau appareil : une erreur réseau isolée ne doit plus faire échouer tout le lot d'appareils.
- Journalisation structurée des erreurs de traitement sans journaliser les jetons FCM ni la clé privée.
- `verify_jwt=false` reste volontairement en place avec la vérification du secret interne `verify_push_dispatch_secret`.

### Cause 503 confirmée après déploiement

Les journaux de la version 10 montrent encore :

`fcm_service_account_missing`

et

`hasFcmProjectId: false`

Le code confirme donc que le secret `FCM_SERVICE_ACCOUNT_JSON` n'est pas disponible dans l'environnement de la fonction et qu'aucun `FCM_PROJECT_ID` de secours n'est défini. Le 503 est conservé volontairement : il ne faut pas déclarer une notification envoyée lorsque FCM n'est pas authentifié.

### Ce qui reste nécessaire

1. Ajouter le compte de service Firebase réel comme secret Supabase `FCM_SERVICE_ACCOUNT_JSON`.
2. Vérifier que le `project_id` du compte de service correspond au projet Firebase.
3. Ajouter la configuration native issue de ce même projet Firebase pour Android et iOS.
4. Après ces configurations, autoriser un test unique sur un appareil de test.

Le connecteur Supabase disponible permet de lire et de déployer les Edge Functions, mais ne fournit pas ici d'action de gestion des secrets Edge Function. Aucun secret n'a été inventé, lu ou écrit par cette intervention. Aucun push de test ni test de masse n'a été déclenché.
