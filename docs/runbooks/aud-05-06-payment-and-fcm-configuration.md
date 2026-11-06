# AUD-05 / AUD-06 — Configuration des paiements et notifications push

**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**Date de contrôle :** 7 novembre 2026  
**État :** code serveur actif ; comptes marchands et secrets fournisseurs manquants ; aucune clé secrète lue ou copiée.

## 1. État vérifié

Le registre `private.platform_health_checks` indique au dernier contrôle conservé (6 novembre 2026 à 20:15:05 UTC) :

- `WAVE = NOT_CONFIGURED` — `WAVE_API_KEY_missing`
- `CINETPAY = NOT_CONFIGURED` — `CINETPAY_API_KEY_or_SITE_ID_missing`

Les Edge Functions de paiement sont actives :

| Fonction | Version active | Configuration nécessaire |
|---|---:|---|
| `create-wave-payment-session-v3` | 4 | `WAVE_API_KEY` |
| `wave-payment-webhook-v3` | 4 | `WAVE_WEBHOOK_SECRET` |
| `create-cinetpay-payment-session-v3` | 6 | `CINETPAY_API_KEY`, `CINETPAY_SITE_ID` |
| `cinetpay-webhook-v3` | 6 | `CINETPAY_API_KEY`, `CINETPAY_SITE_ID`, `CINETPAY_SECRET_KEY` |
| `dispatch-push-notifications` | 10 | `FCM_SERVICE_ACCOUNT_JSON`, `FCM_PROJECT_ID` (si absent du JSON) |
| `platform-health-monitor` | 6 | Secrets Supabase du projet déjà utilisés par le moniteur |

Aucune clé de paiement n'est présente dans les lignes ciblées de `public.platform_settings`. Les valeurs des secrets Edge Function ne sont pas accessibles via les outils de lecture utilisés et n'ont pas été consultées.

Les fonctions de création de session renvoient HTTP 503 si leurs clés nécessaires manquent. Le système ne crée donc pas de faux checkout lorsque le fournisseur n'est pas configuré.

## 2. Secrets à saisir dans Supabase — jamais dans GitHub

Ouvrir **Supabase Dashboard → Edge Functions → Secrets** pour le projet `dzhhsoikzxibmngjzcch` :

https://supabase.com/dashboard/project/dzhhsoikzxibmngjzcch/functions/secrets

Saisir les valeurs directement dans ce panneau, à partir des portails marchands officiels et du projet Firebase. Ne pas poster les secrets dans le chat, les tickets Linear, les fichiers SQL, les variables Flutter ou le dépôt GitHub. Ne pas créer de valeurs factices.

### Wave

- `WAVE_API_KEY` — clé API du compte marchand Wave.
- `WAVE_WEBHOOK_SECRET` — secret de signature du webhook Wave.
- `WAVE_SIGNING_SECRET` — facultatif dans le code actuel ; permet de signer les appels sortants Wave.
- `WAVE_SUCCESS_URL` — facultatif ; URL de retour succès personnalisée.
- `WAVE_ERROR_URL` — facultatif ; URL de retour erreur personnalisée.

La fonction de webhook `wave-payment-webhook-v3` est publiée avec `verify_jwt=false` parce que Wave ne fournit pas de JWT Supabase. Elle vérifie sa signature HMAC Wave sur le corps brut et refuse les timestamps vieux de plus de cinq minutes. Le chemin de secours Bearer est également comparé en temps constant au secret du webhook. Ne pas activer le contrôle JWT Supabase sur cette URL de callback fournisseur.

### CinetPay

- `CINETPAY_API_KEY` — clé API du compte marchand CinetPay.
- `CINETPAY_SITE_ID` — identifiant du site marchand.
- `CINETPAY_SECRET_KEY` — secret utilisé pour vérifier l'en-tête `x-token` du webhook.
- `CINETPAY_RETURN_URL` — facultatif ; URL de retour client personnalisée.

Le webhook `cinetpay-webhook-v3` vérifie le HMAC du `x-token` avec l'ensemble ordonné des champs de notification, vérifie que le `cpm_site_id` correspond au site marchand, puis interroge l'API CinetPay pour confirmer le statut avant d'appeler `process_payment_event`. Il est publié avec `verify_jwt=false` pour recevoir les callbacks du fournisseur ; ne pas supprimer la vérification HMAC ni remplacer celle-ci par une simple confiance dans le corps HTTP.

### Firebase Cloud Messaging (FCM)

- `FCM_SERVICE_ACCOUNT_JSON` — contenu JSON complet du compte de service Firebase utilisé par le serveur.
- `FCM_PROJECT_ID` — identifiant du projet Firebase ; facultatif uniquement si le JSON fournit déjà `project_id`.

Le JSON du compte de service doit contenir au minimum les propriétés `project_id`, `client_email` et `private_key`. La clé privée appartient uniquement à Supabase Edge Function Secrets. Ne pas la committer, ne pas la mettre dans `firebase_options.dart`, et ne pas la mettre dans les fichiers d'application mobile.

## 3. Corrections de surveillance déjà appliquées

### Enregistreur SQL

Migration Supabase `20261106201627_allow_fcm_platform_health_component` :

- ajoute `FCM` à la liste blanche de `private.record_platform_health_checks(jsonb)` ;
- conserve `SECURITY DEFINER`, propriétaire PostgreSQL, `search_path = ''` et l'exigence `service_role` ;
- conserve le refus d'exécution à `anon` et `authenticated`.

Migration Supabase `20261106201705_allow_fcm_health_check_component` :

- ajoute `FCM` à la contrainte `platform_health_checks_component_check` ;
- conserve tous les composants précédemment autorisés.

Un appel transactionnel de validation avec `service_role` a retourné une insertion d'une ligne ; le `ROLLBACK` a ensuite laissé zéro ligne de test dans `private.platform_health_checks`.

### Moniteur Edge Function

`platform-health-monitor` a été déployé en version 6.

Le nouveau contrôle FCM :

- signale `NOT_CONFIGURED` si le JSON compte de service manque ;
- signale `DEGRADED` si le JSON est invalide ou si `client_email` / `private_key` manque ;
- signale `NOT_CONFIGURED` si l'identifiant de projet manque ;
- signale `NOT_TESTED` lorsque les champs de configuration sont présents, sans prétendre qu'un push a été envoyé.

Les journaux consultés dans la fenêtre par défaut de l'outil de logs contenaient 324 événements `fcm_service_account_missing`, avec `hasFcmProjectId=false`. Cela confirme que le worker push était bloqué par la configuration manquante. Aucune notification n'a été envoyée à titre de test.

## 4. Procédure de validation après configuration

1. Confirmer que le compte Wave et le compte marchand CinetPay sont réellement activés pour le pays, les moyens de paiement et l'environnement (sandbox/production) prévus.
2. Saisir les secrets directement dans le panneau Edge Function Secrets.
3. Vérifier que le moniteur enregistre Wave/CinetPay après contrôle de références valides ; l'absence d'une référence de paiement renvoie `NOT_TESTED`, pas `UP`.
4. Effectuer une transaction sandbox contrôlée, puis vérifier le webhook, la signature, `process_payment_event`, l'idempotence du callback et l'état du paiement.
5. Configurer Firebase Cloud Messaging et saisir les deux secrets FCM.
6. Vérifier que le moniteur reconnaît les champs FCM comme présents ; ce statut n'est pas une preuve d'envoi réussi.
7. Envoyer un push de test vers un appareil de validation interne, vérifier la réception Android et iOS/APNs, puis vérifier la désactivation des tokens invalides et l'absence de double notification.
8. Avant une transaction réelle, confirmer les commissions, remboursements, frais et reçus avec les comptes marchands.

**Ne pas effectuer de test de débit réel sans validation explicite.** Une clé présente ne prouve pas que le compte marchand est activé ou que les callbacks sont configurés correctement.

## 5. État bloquant et responsabilités

La partie code et surveillance est en place, mais les secrets et identifiants des comptes marchands/Firebase doivent provenir des comptes que le propriétaire aura créés ou activés.

- Wave : en attente de `WAVE_API_KEY` et `WAVE_WEBHOOK_SECRET`.
- CinetPay : en attente de `CINETPAY_API_KEY`, `CINETPAY_SITE_ID`, `CINETPAY_SECRET_KEY`.
- FCM : en attente de `FCM_SERVICE_ACCOUNT_JSON` et, si absent du JSON, `FCM_PROJECT_ID`.

Aucune de ces valeurs n'a été inventée, demandée par message ou exposée dans le dépôt.
