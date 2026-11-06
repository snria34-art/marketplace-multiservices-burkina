# Audit senior — configuration et corrections

Date : 6 novembre 2026  
Dépôt : `adjasanou49-max/marketplace-multiservices-burkina`  
Branche : `main`

## Périmètre

Revue ciblée des configurations Flutter, Supabase, Firebase/FCM et GitHub Actions à partir des fichiers présents sur `main`. Cette intervention n'a exécuté aucun workflow, test, build, reset de base, migration distante, paiement ou notification.

## Corrections appliquées sur GitHub

### 1. Déclenchement des builds natifs

Fichier : `.github/workflows/native-build.yml`

- Retrait du déclenchement automatique sur les tags `v*`.
- Conservation du seul déclenchement manuel `workflow_dispatch`.
- Motif : éviter qu'un simple tag déclenche une compilation et consomme des minutes Actions alors que les prérequis de publication ne sont pas finalisés.
- Renommage du step Android en `Build Android App Bundle (AAB)`, car la commande exécutée est `flutter build appbundle --release`, pas une génération APK.

Commit : `1633da593b946a620bb0782d3e56d037bba27b05`.

### 2. Documentation Android/iOS

Fichier : `docs/native-platforms.md`

- Correction de la description Android : le workflow construit un AAB release, pas un APK.
- Correction de la description iOS : `flutter build ios --simulator --debug` est une compilation simulateur/debug, pas un IPA release ni une archive App Store.
- Clarification de la signature Android : le keystore et `key.properties` doivent être fournis hors Git via un mécanisme de secrets sécurisé.
- Clarification des dépendances Firebase réelles : ne pas fabriquer `google-services.json`, `GoogleService-Info.plist` ou les identifiants Firebase.
- Documentation des déclenchements manuels.

Commit : `654f6fb97dd2c9bb19fa426704020eeeb858f5e4`.

## Configuration vérifiée

### Flutter

- SDK déclaré : Dart `>=3.12.0 <4.0.0`.
- Analyse statique : `flutter analyze --no-fatal-warnings --no-fatal-infos`. Cette commande laisse passer les warnings et infos ; le dépôt n'impose donc pas encore un seuil strict sans avertissement.
- Tests : `flutter test`.
- Le workflow Flutter reste manuel.
- Aucun résultat de compilation ou d'analyse n'est revendiqué dans cet audit.

### Supabase

- Projet cible connu : `dzhhsoikzxibmngjzcch`.
- Configuration locale `supabase/config.toml` : identifiant de projet local `marketplace-multiservices-burkina`.
- Les webhooks Wave/CinetPay ont `verify_jwt=false` au niveau gateway et doivent continuer à effectuer leur vérification cryptographique/secret dans le code serveur.
- La base active a déjà été rapportée avec 321 migrations appliquées ; le dépôt ne contient pas encore un historique ancien complet permettant de certifier un reset reproductible.
- Ne pas lancer `supabase db reset` sur le projet distant ni modifier l'historique de migrations à l'aveugle.

### Notifications Firebase

- Le code Flutter appelle `Firebase.initializeApp()` et utilise `FirebaseMessaging`.
- Le worker `dispatch-push-notifications` utilise `FCM_SERVICE_ACCOUNT_JSON` et renvoie volontairement `fcm_not_configured` si le secret manque.
- Le document opérationnel `docs/push-notifications.md` rapporte que le worker Supabase est en version 8.
- Le secret Firebase et les fichiers de configuration natifs doivent provenir du vrai projet Firebase. Ils ne peuvent pas être inventés ni stockés dans Git.
- Le service de notification conserve un état au niveau notification, pas au niveau appareil : si certains appareils reçoivent le push et d'autres échouent, la reprise individuelle des seuls appareils en échec n'est pas encore implémentée. Il faut un suivi par couple notification/appareil avant d'optimiser les retries multi-appareils.

## Points bloquants restants — priorité

| Priorité | Sujet | État | Action sûre suivante |
|---|---|---|---|
| P0 | Clés Firebase natives et service account | À fournir depuis le projet réel | Ajouter les fichiers Android/iOS non secrets nécessaires au build et placer le JSON service account uniquement dans Supabase Edge Function Secrets |
| P1 | Signature Android | Non validée | Configurer keystore et propriétés via secrets sécurisés, sans committer les clés |
| P1 | Build iOS de publication | Non disponible dans le workflow actuel | Préparer une archive IPA/TestFlight avec compte Apple, certificats et profils |
| P1 | Reproductibilité migrations | Non démontrée | Reconstituer une baseline versionnée et comparer précisément les 321 versions distantes |
| P1 | Remboursements multi-vendeurs | Défaut métier déjà identifié | Concevoir une allocation explicite par article/quantité/groupe avant toute migration |
| P1 | Allocation push par appareil | Non implémentée | Ajouter une table d'état notification/appareil et des retries idempotents |
| P1 | `spatial_ref_sys` | Alerte RLS/permissions connue | Réduire l'exposition Data API ou utiliser une procédure compatible avec le propriétaire PostGIS |
| P2 | Seuil strict Flutter analyze | Non activé | Corriger les warnings progressivement avant de retirer les options `no-fatal` |
| P2 | Capacité 1 000–10 000 connexions | Non mesurée | Définir un profil de charge et des seuils avant tout test autorisé |

## À propos de l'objectif de 89 %

Un taux de correction de 89 % ne peut pas être certifié à partir d'une revue partielle ou d'un nombre de fichiers corrigés. Il faut un inventaire exhaustif des défauts, une pondération par criticité et des validations reproductibles. Ce rapport ne transforme donc pas l'objectif de 89 % en score fictif.

La correction de configuration livrée ici est vérifiable dans GitHub, mais le projet n'est pas certifié prêt pour la production. Les validations automatisées restent volontairement non exécutées.


## Addendum — vérifications connectées du 6 novembre 2026

### Supabase réel

- Projet : `dzhhsoikzxibmngjzcch`, statut `ACTIVE_HEALTHY`, PostgreSQL `17.6.1.166`, région `eu-west-1`.
- Historique distant : 321 migrations.
- Schémas contrôlés : 182 tables.
- L'unique table recensée sans RLS dans le schéma public reste `public.spatial_ref_sys` (8 500 lignes).

### Blocage de propriété de spatial_ref_sys

La lecture de `pg_class` et des privilèges confirme :

- propriétaire : `supabase_admin` ;
- RLS : désactivé ;
- `anon` et `authenticated` disposent de SELECT, INSERT, UPDATE, DELETE et TRUNCATE ;
- le rôle de connexion `postgres` n'est pas superuser et n'est pas membre de `supabase_admin`.

Le compte connecté ne peut donc pas appliquer `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` ni retirer les privilèges accordés par le propriétaire PostGIS. Aucun contournement par changement de rôle n'a été tenté. Il faut une intervention par le propriétaire de l'extension ou une réduction ciblée de l'exposition Data API qui préserve les fonctions PostGIS. Ne pas déplacer l'extension ou modifier les catalogues système.

### Conseillers Supabase

- Sécurité : 1 ERROR (`spatial_ref_sys` sans RLS), 5 WARN (extensions en `public` et fonctions PostGIS exécutables par anon/authenticated), 17 INFO (RLS activé sans policy ; ne pas ajouter de policies permissives pour faire disparaître les alertes).
- Performance : 368 index signalés inutilisés. Aucun index supprimé : le signal est non concluant avant trafic représentatif.
- Health : la fonction push continue de renvoyer 503 tant que le compte de service FCM est absent.

### Notifications — correction livrée

- `dispatch-push-notifications` : **version 10 ACTIVE**.
- Vérification du code déployé : le worker traite au plus cinq notifications simultanément et cinq appareils simultanément par notification.
- Les journaux de la version 10 confirment encore `fcm_service_account_missing` et `hasFcmProjectId=false`. Il s'agit d'une configuration externe manquante, pas d'une erreur qui peut être corrigée en modifiant le code.
- Le compte de service n'a pas été créé, lu ou ajouté : aucune interface de gestion des secrets Edge Function n'est exposée par le connecteur Supabase utilisé ici.

### Flutter — correction livrée

`PushNotificationService.initialize` intercepte maintenant toutes les exceptions de l'initialisation Firebase et journalise le détail uniquement en mode debug. L'absence de fichiers Firebase natifs ne doit pas remonter comme exception non gérée au démarrage de l'application.

### Limites de validation

Aucun workflow GitHub Actions, analyse Flutter, test Dart/SQL, build mobile, migration de production, notification de test ou campagne de notifications n'a été lancé. Les corrections de code et le déploiement Edge Function sont confirmés par relecture GitHub/Supabase ; la compilation Flutter et la réception sur un téléphone restent à valider après configuration Firebase.
