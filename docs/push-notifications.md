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