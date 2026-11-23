# Répartition des clés et configurations API

Cette fiche distingue les configurations publiques embarquées dans l'application des secrets utilisés uniquement par les serveurs. Une clé ne doit pas être copiée dans chaque plateforme : elle doit être placée là où le code l'utilise.

## 1. Railway — compilation et service Flutter

Le Dockerfile de l'application consomme :

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

Ces deux variables sont déjà présentes sur le service Railway observé. Le connecteur masque leurs valeurs ; leur validité exacte n'a donc pas été vérifiée. `SUPABASE_ACCESS_TOKEN` figure également dans la liste Railway, mais le Dockerfile Flutter ne le consomme pas. Je ne le supprime pas sans vérifier les autres usages possibles du service.

`SUPABASE_PUBLISHABLE_KEY` est la clé publique destinée au client Flutter. Ne jamais remplacer cette clé par `SUPABASE_SERVICE_ROLE_KEY` ou par une clé secrète Supabase.

Le service Railway actuel compile Flutter Web puis sert les fichiers avec Nginx. Les clés privées OpenAI et Firebase ne sont pas nécessaires à ce service de distribution.

## 2. GitHub Actions — secrets de workflows seulement

Le workflow manuel `.github/workflows/repair-aud-07-migration-history.yml` référence :

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_DB_PASSWORD`

Ces secrets servent à ce workflow d'administration/migration. La présence d'un `SUPABASE_ACCESS_TOKEN` dans Railway ne prouve pas que le secret GitHub Actions est configuré : GitHub ne permet pas au connecteur présent ici de lire les valeurs ou de confirmer leur présence. Ces secrets ne sont pas des variables de l'application mobile et ne doivent pas être copiés dans le code Flutter.

Ne pas lancer ce workflow dans le cadre de l'intégration des clés : il modifie l'historique des migrations du projet Supabase officiel.

## 3. Supabase Edge Functions — secrets serveur

Les fonctions serveur consomment les paramètres suivants :

| Secret / variable | Fonction(s) | Emplacement |
|---|---|---|
| `OPENAI_API_KEY` | `platform-assistant`, `analyze-product` | Secrets Edge Functions Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` ou `SUPABASE_SECRET_KEYS` | `analyze-product`, `dispatch-push-notifications` | Secrets Edge Functions Supabase |
| `FCM_SERVICE_ACCOUNT_JSON` | `dispatch-push-notifications` | Secrets Edge Functions Supabase |
| `FCM_PROJECT_ID` | `dispatch-push-notifications` | Variable de secours Edge Function ; le code lit d'abord `project_id` dans le compte de service |

Ne jamais mettre ces secrets dans Flutter, le navigateur, les fichiers versionnés, ni dans les variables Railway du service Nginx. Ne jamais transmettre une clé secrète dans le chat.

Le connecteur Supabase disponible dans cette session ne permet pas de créer ou modifier les secrets Edge Functions. Aucun secret serveur n'a été modifié.

## 4. Firebase — configuration du client mobile

Les configurations clients officielles ne sont pas des clés privées :

- Android : `android/app/google-services.json`, application ID `com.marketplaceburkina.marketplace_multiservices_burkina`.
- iOS : `ios/Runner/GoogleService-Info.plist`, Bundle ID `com.marketplaceburkina.marketplaceMultiservicesBurkina`.
- Flutter : générer `lib/firebase_options.dart` avec `flutterfire configure` depuis le projet Flutter et le projet Firebase existant.

Le fichier Android officiel `android/app/google-services.json` a été téléchargé depuis le projet Firebase `marketplace-multiservices-bf` et ajouté à cette branche. Son `project_id` et son package Android correspondent au projet et à l'identifiant enregistrés. Les configurations iOS `GoogleService-Info.plist` et Flutter `firebase_options.dart` restent à obtenir/générer depuis le même projet Firebase. Aucun fichier ne doit être fabriqué à partir de valeurs supposées.

Le compte de service FCM est différent des configurations clients : son JSON privé va uniquement dans `FCM_SERVICE_ACCOUNT_JSON` côté Supabase Edge Functions.

## 5. Paiements

Wave, CinetPay et les autres prestataires restent hors de cette intégration et seront configurés à la dernière étape, comme prévu.

## État de cette préparation

- Vérification des noms de variables Railway : les noms observés sont présents ; les valeurs restent masquées et leur validité n'est pas certifiée.
- Configuration cliente Android officielle ajoutée à `android/app/google-services.json` sur `integration/firebase-mobile-client` et cohérence du project ID/package vérifiée.
- Configuration iOS et options Flutter encore à raccorder.
- Aucun compte de service ni secret privé ajouté au dépôt ; la clé du fichier Android est une clé cliente Firebase, non un compte de service.
- Aucun workflow manuel, build, déploiement Railway ni changement de la base Supabase n'a été exécuté.
