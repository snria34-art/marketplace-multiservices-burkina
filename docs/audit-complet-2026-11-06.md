# Audit complet — Marketplace Multiservices Burkina

**Date : 6 novembre 2026**  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina`  
**Branche :** `main` — dépôt privé  
**Supabase :** `dzhhsoikzxibmngjzcch` — PostgreSQL 17.6.1 — région `eu-west-1` — état `ACTIVE_HEALTHY`  
**Commit de référence inspecté :** `7b07bf540cd6bcf99828bcb03c8827ea17040a2d`

## 1. Conclusion exécutive

Le projet possède une base technique importante et de nombreux parcours métier, mais **il n'est pas certifié prêt pour une mise en production**. Les principaux blocages ne sont pas le nombre d'écrans ou de tables : ils concernent la reproductibilité de la base, les tests réels, les intégrations natives, le suivi GPS arrière-plan, les remboursements, la livraison des notifications et la capacité mesurée.

### État synthétique

| Domaine | Constat au 6 novembre |
|---|---|
| Dépôt | Privé, branche main accessible en lecture/écriture |
| Base active | 321 migrations appliquées ; 182 tables dans public/private |
| RLS | 166/167 tables publiques et 15/15 tables privées ont RLS |
| Stockage | 5 buckets ; 4 privés et avatars public |
| Edge Functions | 21 fonctions déployées |
| Verticales | 16 modules déclarés ; 5 sans action métier depuis l'écran générique |
| Données métier | 0 ligne dans les 12 tables essentielles contrôlées |
| Tests Flutter | 3 fichiers de test Dart identifiés |
| CI | workflows Flutter et DB manuels ; build natif manuel ou sur tag |
| Push | FCM non configuré ; erreurs 503 déjà observées |
| GPS | premier plan seulement ; arrière-plan non garanti |
| Capacité | aucune preuve de charge à 1 000–10 000 connexions simultanées |

## 2. Points bloquants prioritaires

### P1 — Sécurité de `public.spatial_ref_sys`

L'advisor Supabase signale une erreur : RLS désactivé sur `public.spatial_ref_sys`. La table est détenue par le propriétaire de l'extension PostGIS, et le rôle courant n'a pas le droit de modifier sa sécurité. Le contrôle SQL confirme que `anon` et `authenticated` possèdent actuellement des privilèges INSERT, UPDATE, DELETE et TRUNCATE en plus de SELECT.

**Action requise :** corriger par une procédure compatible avec le propriétaire PostGIS/Supabase, ou réduire l'exposition Data API de cette table. Ne pas contourner le propriétaire, ne pas modifier les catalogues système et ne pas désactiver PostGIS.

### P1 — Remboursements et allocation comptable

Le problème déjà identifié reste ouvert : `complete_refund` répartit le débit du remboursement au prorata des sous-totaux des groupes vendeurs, sans cibler précisément la boutique, les articles et quantités concernés. Cela peut débiter des vendeurs non concernés et provoquer des conflits de ledger lorsque plusieurs boutiques appartiennent au même vendeur.

**Action requise :** définir un modèle d'allocation explicite par ligne d'article/groupe, quantité, frais de livraison, remise, commission et sommes déjà versées. Ajouter des tests comptables négatifs et concurrents. Ne pas activer de remboursement automatique supplémentaire avant cette correction.

### P1 — Historique des migrations non reproductible

La base distante a 321 migrations appliquées. Le README indique encore 258 migrations et un rapport daté du 4 novembre indique 259. Le dépôt documente que l'historique SQL ancien est incomplet. La reconstruction d'une base vide n'est donc pas démontrée.

Le workflow DB exécute `supabase db reset`, qui dépend de la capacité à rejouer toutes les migrations locales. Tant que l'historique complet n'est pas versionné et rejouable, le résultat de ce workflow n'est pas une preuve fiable de reproductibilité.

**Action requise :** reconstruire une baseline versionnée et documenter la correspondance entre les 321 versions distantes et les migrations du dépôt avant toute modification destructive.

### P1 — Publication Android

Le build Gradle release échoue explicitement si `android/key.properties` ou le keystore manque. Le workflow `.github/workflows/native-build.yml` lance `flutter build appbundle --release`, mais ne crée pas le fichier de signature et ne charge pas de secret de signature dans le runner. Le workflow de tag ne peut donc pas produire un AAB signé dans sa configuration actuelle.

Le job iOS construit un simulateur en mode debug ; il ne produit pas un IPA de publication. La documentation native décrit un objectif plus avancé que le workflow réellement exécuté.

**Action requise :** configurer une procédure de signature sécurisée à partir de secrets GitHub, ou séparer explicitement le build de validation du build de publication. Créer ensuite une vraie archive iOS/TestFlight avec les certificats et profils Apple.

### P1 — Notifications push

La fonction `dispatch-push-notifications` est déployée en version 7. Les journaux et le rapport de santé ont déjà signalé 5 réponses 503 sur 5 requêtes sur deux fenêtres ; la fonction retourne `fcm_not_configured` lorsque `FCM_SERVICE_ACCOUNT_JSON` est absent.

Le code du dépôt a évolué, mais la version déployée n'est pas synchronisée avec le worker récent. Les fichiers Firebase natifs `google-services.json` et `GoogleService-Info.plist` ne sont pas fournis.

**Action requise :** créer/configurer le projet Firebase, les applications Android/iOS, APNs et le service account côté secrets Supabase ; synchroniser la fonction déployée avec la source après validation. Ne jamais masquer le 503 en prétendant que la notification est envoyée.

## 3. Sécurité Supabase

### RLS et politiques

Contrôle SQL en lecture seule :

- `public` : 167 tables, 166 avec RLS activé ; 1 exception, `spatial_ref_sys`.
- `private` : 15 tables, toutes avec RLS activé.
- 357 politiques sont présentes sur 164 tables publiques.
- L'advisor signale 17 tables RLS sans policy : 15 tables privées et les tables publiques `delivery_evidence` et `review_media`. Les privilèges directs anon/authenticated sur ces tables sont absents ; ces surfaces sont conçues pour être servies via des RPC/contrôles ciblés. Ne pas créer de policy permissive juste pour faire disparaître l'INFO.
- Le schéma `private` donne actuellement USAGE à anon et authenticated, mais aucun privilège direct de table n'a été trouvé pour ces rôles. Vérifier les schémas réellement exposés dans les réglages Data API avant toute exposition future.

### Fonctions SECURITY DEFINER

- 119 fonctions SECURITY DEFINER dans `public`, dont 80 exécutables par authenticated.
- 45 dans `private`, dont 25 exécutables par authenticated.
- Trois surcharges PostGIS `st_estimatedextent` restent exécutables par anon/authenticated.
- Trois fonctions du schéma privé sont également exécutables par anon : deux helpers de lecture de médias d'avis publiés et `private.is_admin()`. Cette dernière renvoie faux sans utilisateur authentifié. Les tables privées ne sont pas directement lisibles par les rôles clients.
- Les RPC administratives contrôlées échantillonnées (`get_admin_dashboard`, `get_admin_refunds`, `admin_set_account_status`) vérifient l'administration côté serveur ; `get_seller_dashboard` filtre par l'identité du vendeur.

L'alerte de 80 fonctions authentifiées est générique et ne prouve pas que 80 vulnérabilités existent. Il faut poursuivre la revue fonction par fonction : identité, compte actif, rôle, propriété, permissions, search_path fixe et tests d'accès négatifs. Ne pas révoquer globalement ces fonctions.

### Extensions et vues

- Cinq extensions installées dans `public` : `citext`, `pg_trgm`, `postgis`, `vector`, `pg_net`.
- Deux vues publiques PostGIS : `geography_columns` et `geometry_columns`, sans option security_invoker observée. Ce sont des vues de métadonnées ; leurs privilèges et leur exposition doivent rester contrôlés.
- Ne pas déplacer PostGIS sans audit de relocatabilité et de dépendances.

### Stockage

Cinq buckets configurés :

| Bucket | Accès | Limite |
|---|---|---:|
| avatars | public | 5 MiB |
| shop-media | privé | 50 MiB |
| documents | privé | 10 MiB |
| product-media | privé | 5 MiB |
| order-feedback-media | privé | 20 MiB |

Les types MIME sont limités. Les parcours d'upload contrôlent maintenant les tailles avant lecture mémoire, puis contrôlent les octets lus ; les parcours média utilisent des MIME autorisés et des extensions canonisées. Les nettoyages Storage après échec RPC restent best-effort.

**Limite :** aucun objet n'était présent dans Storage lors du contrôle. Aucun vrai fichier n'a donc permis de valider les permissions, téléchargements, URL signées, lecture multi-rôle ou suppression sur un parcours complet. Les contrôles MIME déclaratifs ne valident pas la signature binaire réelle.

### Advisors

- Sécurité : 1 ERROR (`spatial_ref_sys`), 5 WARN (extensions et fonctions PostGIS), 17 INFO (RLS sans policy).
- Performance : 369 index signalés inutilisés. Ce signal est peu représentatif sans trafic métier ; ne pas supprimer en masse.
- Health : aucun lint remonté par l'advisor Health au moment de la lecture.

## 4. Parcours métier et fonctionnalités manquantes

### Verticales

Les 16 modules sont déclarés et ont des tables/configurations. L'écran générique `VerticalDiscoveryPage` ne fournit cependant pas d'action dans son switch pour cinq modules :

1. immobilier (`realEstate`) ;
2. professionnels (`professionals`) ;
3. agriculture (`agriculture`) ;
4. santé (`health`) ;
5. services créatifs (`creative`).

Le dépôt contient des fonctions de lecture/configuration, mais aucun flux d'action associé dans cet écran pour ces cinq verticales. Le bouton générique ne doit pas être considéré comme un parcours métier terminé.

Les autres modules ont plusieurs actions (trajets, événements, location, hébergement, candidatures, formations, services numériques, beauté, domicile, fret, colis), mais leur fonctionnement réel reste à valider par tests de bout en bout.

### Vendeurs multi-boutiques

Le vendeur peut déjà posséder plusieurs boutiques et le nom normalisé d'une boutique est unique globalement. Le partage d'accès existant ne constitue pas un vrai RBAC d'employés.

Aucune table dédiée n'a été trouvée pour :
- plans et abonnements vendeurs ;
- quotas payés de boutiques et allocations d'emplacements ;
- invitations e-mail à durée limitée ;
- membres de boutique avec permissions granulaires.

Le document `docs/saas-multishop-architecture.md` décrit la cible, mais ce modèle n'est pas implémenté. Aucune table dédiée de fournisseurs/approvisionnement ou de fiscalité n'a été identifiée dans les schémas inspectés.

### GPS et livraison

Le suivi livreur fonctionne au premier plan avec une position immédiate puis une fréquence de 15 secondes, sérialisée pour éviter les envois concurrents. Android ne déclare pas `ACCESS_BACKGROUND_LOCATION` ni un service de premier plan de localisation ; iOS ne déclare pas le mode background `location`.

Le suivi lorsque l'application est suspendue/fermée n'est donc pas garanti. Il manque le service arrière-plan avec consentement, indicateur visible, reprise, arrêt à la fin de mission et essais sur appareils réels.

### Paiements

Le code contient les intégrations Wave et CinetPay ; Orange Money et Moov Money sont proposés via CinetPay Collect. Les webhooks v3 sont configurés sans JWT de passerelle et doivent valider leur signature propre. Les comptes marchands, clés et secrets de production restent à configurer dans Supabase.

Plusieurs générations de fonctions de paiement (anciennes versions et v3) sont encore déployées. Une fonction déployée `payment-webhook-gateway` apparaît dans la liste Supabase mais son fichier source attendu n'a pas été trouvé dans le dépôt. Vérifier les références, l'usage réel et la provenance avant de désactiver ou supprimer quoi que ce soit.

Aucun paiement réel ni test de remboursement réel n'a été effectué.

## 5. Tests, CI et capacité

### Tests

Trois fichiers de test Dart ont été identifiés :
- `test/smoke_test.dart` : démarrage de l'application ;
- `test/vertical_repository_test.dart` : configuration des verticales ;
- `test/push_notification_test.dart` : routage des notifications.

La suite pgTAP `supabase/tests/database/security_regression_test.sql` annonce `plan(41)`, mais n'a pas été exécutée. Il manque des tests d'intégration et E2E couvrant les rôles client, vendeur, restaurant, livreur, administrateur, prestataires, commandes multi-vendeurs, stock concurrent, livraison, remboursements, webhooks signés, messagerie et médias.

### Workflows

- `flutter.yml` : déclenchement manuel uniquement ; `flutter analyze` autorise les warnings/infos non fatals.
- `supabase-db-tests.yml` : déclenchement manuel ; lance Deno check, Supabase local, `supabase db reset` et `supabase test db`.
- `native-build.yml` : manuel ou sur tag `v*` ; Android AAB release, iOS simulateur debug.

Aucun workflow n'a été déclenché pendant cet audit. Les actions tierces sont référencées par tags et non par SHA complet ; un durcissement de la chaîne d'approvisionnement reste souhaitable.

### Capacité et continuité

Aucun test de charge ne prouve 1 000 à 10 000 connexions simultanées. Il manque des mesures de débit, latence p95/p99, saturation du pool PostgreSQL, consommation Realtime, quotas Edge Functions, stockage/CDN, reprise après incident et comportement réseau mobile faible.

Aucune preuve de restauration complète de sauvegarde/PITR n'a été fournie ou exécutée dans cet audit. Les procédures de sauvegarde, RPO/RTO et exercice de restauration restent à documenter et valider.

## 6. Données et conformité Burkina Faso

Au moment du contrôle, les tables suivantes contenaient chacune zéro ligne : profils, vendeurs, boutiques, produits, commandes, paiements, remboursements, affectations livraison, documents légaux, consentements, tickets support et événements de fraude. Cela signifie qu'aucun parcours métier réel n'est démontré sur ces données dans cet environnement.

La table `legal_documents` existe mais est vide ; `user_consents` est également vide. Les documents CGU, CGV, confidentialité, retours, livraison, conditions vendeur/coursier et produits interdits ne sont donc pas publiés dans la base contrôlée.

Il manque une revue juridique/fiscale Burkina Faso des conditions de vente, responsabilités de la marketplace, fiscalité/commissions, facturation, protection des données, conservation/suppression, consentement et traitement des réclamations. Les documents doivent être validés par un professionnel compétent avant publication.

## 7. Ordre de travail recommandé

1. Corriger le blocage `spatial_ref_sys` par une procédure propriétaire compatible, sans compromettre PostGIS.
2. Finaliser le modèle comptable d'allocation des remboursements et les protections ledger.
3. Restaurer la reproductibilité des migrations depuis une base vide.
4. Corriger le workflow Android de signature et produire une vraie archive iOS.
5. Configurer Firebase/FCM et synchroniser le worker push déployé.
6. Implémenter les actions des cinq verticales manquantes.
7. Construire les abonnements, quotas, invitations et permissions des boutiques.
8. Implémenter le suivi GPS en arrière-plan avec consentement et essais réels.
9. Ajouter les tests E2E et tests de concurrence ; exécuter la CI seulement après autorisation et contrôle du coût.
10. Publier les documents légaux/fiscaux validés et vérifier la conformité.
11. Mesurer la charge 1 000–10 000 connexions et réaliser un exercice de restauration.
12. Auditer les anciennes Edge Functions de paiement et retirer les versions obsolètes seulement après vérification de leur usage.

## 8. Limites et opérations non effectuées

Cet audit est une inspection statique du dépôt et des contrôles Supabase en lecture seule. Il ne constitue pas un audit de pénétration ni une certification de production.

Aucun secret n'a été affiché ou modifié. Aucun paiement, remboursement, upload réel, déploiement, changement de schéma, suppression de données, test Flutter, build natif ou workflow GitHub Actions n'a été exécuté. Le dépôt est resté privé.

**Verdict :** architecture riche et base avancée, mais production non validée. Les priorités P1 ci-dessus doivent être résolues avant d'ouvrir l'application à des utilisateurs et à des flux financiers réels.
