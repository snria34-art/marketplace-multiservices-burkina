# Audit global — Marketplace Multiservices Burkina

**Date de l'audit :** 7 novembre 2026  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina`  
**Branche :** `main`  
**Supabase :** `dzhhsoikzxibmngjzcch` — PostgreSQL 17.6 — `eu-west-1`  
**Nature :** audit statique du dépôt + contrôles Supabase en lecture seule + examen des workflows et journaux.  
**Aucune migration, donnée métier, clé secrète, transaction, fonction Edge ou configuration de production n'a été modifiée. Aucun compte propriétaire n'a été créé.

## 1. Conclusion

L'application possède déjà une base fonctionnelle étendue, mais elle **n'est pas prête pour une mise en production**. Les blocages les plus importants portent sur la sécurité d'une table PostGIS exposée, l'allocation comptable des remboursements, l'annulation des commandes payées, la configuration réelle des paiements/notifications, la dérive entre migrations locales et base distante, et l'absence de validation automatisée fiable sur le dernier commit de `main`.

Les constats ci-dessous sont classés par gravité et par dépendance. « Confirmé » signifie que le défaut ou l'absence a été vu directement dans le code, les privilèges SQL, les migrations ou les journaux. « À valider » signifie qu'un essai réel ou une décision métier est encore nécessaire. Les alertes génériques de l'advisor Supabase ne sont pas considérées automatiquement comme des vulnérabilités.

### Inventaire technique vérifié

| Mesure | Résultat |
|---|---:|
| Entrées dans l'arbre GitHub | 657 |
| Fichiers Dart sous `lib/` | 72 |
| Fichiers de tests Dart | 3 |
| Tests SQL dans `supabase/tests/database` | 2 |
| Assertions pgTAP prévues dans ces deux fichiers | 54 (41 + 13) |
| Tables Supabase `public` et `private` | 182 |
| Tables publiques avec RLS | 166/167 |
| Tables privées avec RLS | 15/15 |
| Migrations SQL présentes dans GitHub | 323 |
| Migrations consignées dans Supabase | 321 |
| Fonctions Edge actives dans Supabase | 21 |
| Dossiers sources Edge avec `index.ts` dans GitHub | 18 |
| Buckets Storage | 5 |

Les mesures de quantité ne prouvent pas la qualité fonctionnelle. Les 54 assertions SQL couvrent notamment des permissions et des contrôles de sécurité, mais ne constituent pas une suite de tests de bout en bout pour les parcours commerciaux.

## 2. Registre des anomalies — ordre de correction proposé

### P1 — Risque d'intégrité et de disponibilité à traiter avant l'ouverture publique

#### AUD-01 — PostGIS installé dans `public` : métadonnées spatiales modifiables via la Data API
**État : confirmé. Correction sûre identifiée ; intervention Support requise.**

- PostGIS 3.3.7 est installé dans `public` et appartient à `supabase_admin`.
- `public.spatial_ref_sys` contient 8 500 définitions de systèmes de coordonnées. `anon` et `authenticated` ont des privilèges INSERT, UPDATE, DELETE et TRUNCATE, hérités des privilèges par défaut du propriétaire de l'extension.
- Ce constat ne signifie pas que les données personnelles ou les coordonnées de livraison sont lisibles dans `spatial_ref_sys`. Le risque principal est l'intégrité : une modification ou suppression d'un SRID peut faire échouer les calculs géographiques et donc dégrader la livraison/localisation.
- Le rôle de projet ne peut ni activer RLS ni retirer les privilèges accordés par `supabase_admin`. Un `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, un `REVOKE` ou un trigger de blocage n'est pas une correction valable.
- Trois colonnes `geography` existent : `courier_locations.location`, `provider_locations.location` et `shops.location`. Elles contiennent actuellement zéro ligne. Deux index GiST ont été recensés (`courier_locations`, `shops`). Il faut préserver tables, types, index et vues.
- Deux fonctions applicatives utilisent explicitement les noms de schéma actuels `public.st_*` et `public.geography` : `calculate_delivery_fee(uuid,jsonb)` et `record_courier_location(double precision,double precision,numeric)`. Elles devront être adaptées au schéma `extensions` après le déplacement.
- Aucun autre appel applicatif direct à une RPC PostGIS ni vue métier dépendante de PostGIS n'a été identifié dans les contrôles effectués. Aucune extension supplémentaire dépendant de PostGIS n'a été détectée.

**Risque :** altération possible des définitions SRID, pouvant rendre les calculs spatiaux indisponibles. Ce n'est pas une fuite de données métier. Les statistiques PostgreSQL consultées indiquent zéro UPDATE et zéro DELETE depuis la dernière remise à zéro des statistiques ; aucune tentative POST/PATCH/PUT/DELETE vers `/spatial_ref_sys` n'a été trouvée dans les journaux Data API du 6 au 7 novembre 2026. Cette vérification ne prouve pas l'absence d'activité antérieure à la période de journaux consultée.

**Correction retenue :** déplacer l'extension PostGIS existante de `public` vers `extensions` par l'intervention non destructive de Supabase Support. Supabase documente que cette méthode préserve les colonnes PostGIS, données, index et vues et s'exécute dans une transaction. Ne pas supprimer/recréer PostGIS soi-même : cette base possède des colonnes `geography` et la procédure DROP CASCADE les supprimerait.

**Préparation :** voir `docs/runbooks/aud-01-postgis-schema-move.md`. Le dossier contient le message à transmettre à Supabase Support, les deux définitions SQL corrigées à appliquer après le déplacement et les contrôles de validation. Aucun changement SQL de production n'a été appliqué à ce stade.

### P1 — Bloquants métier, financiers et opérationnels

#### AUD-02 — Les remboursements partiels débitent potentiellement des vendeurs non concernés
**État : confirmé dans la fonction SQL. Lié à Linear RIA-25.**

`public.complete_refund(uuid,text)` répartit le montant du remboursement au prorata du sous-total de **tous** les groupes vendeurs de la commande. La fonction ne reçoit pas d'allocation explicite par article, quantité ou groupe. Pour un retour partiel qui concerne une seule boutique, son ledger peut donc être débité alors que d'autres boutiques supportent aussi une part du remboursement.

**Correction :** spécifier l'allocation par ligne d'article/groupe, quantités, remise, commission, frais de livraison, taxes éventuelles et remboursements déjà traités. Ajouter des tests transactionnels pour les commandes multi-vendeurs, plusieurs remboursements partiels, vendeurs multiples et plusieurs boutiques appartenant au même vendeur. Ne pas modifier la fonction de production avant définition de cette règle comptable.

Suivi : https://linear.app/faso/issue/RIA-25/bloquant-finance-corriger-lallocation-des-remboursements-partiels

#### AUD-03 — L'annulation globale ne synchronise pas tous les colis et remboursements
**État : confirmé dans la fonction SQL. Lié à Linear RIA-29.**

`public.transition_order_status(uuid,order_status,text)` est exécutable par `authenticated`. Elle autorise l'annulation d'une commande payée par le client ou l'administrateur et libère des réservations de stock. Elle met à jour la commande et les groupes, mais ne synchronise pas systématiquement les colis et affectations coursier, ne bloque pas explicitement une annulation après prise en charge et ne déclenche pas, à elle seule, une demande de remboursement pour un paiement déjà encaissé.

Le chemin distinct `cancel_unpaid_order(uuid)` est plus restrictif et traite correctement les commandes en attente de paiement ; il ne corrige pas le problème de la RPC globale.

**Correction :** définir une machine d'état cohérente commande/groupe/colis/affectation/paiement/remboursement et retirer les transitions impossibles. Ajouter des tests sur colis créé, accepté, ramassé, en transit, livré et paiement déjà encaissé. Coordonner avec AUD-02.

Suivi : https://linear.app/faso/issue/RIA-29/commande-securiser-lannulation-globale-et-synchroniser-colis

#### AUD-04 — Le lecteur sécurisé du stock par variante manque dans la base distante
**État : confirmé. Lié à Linear RIA-28.**

La migration locale `20261106180000_add_secure_seller_variant_inventory_read.sql` crée `public.get_seller_product_variant_inventory(uuid)`, mais son numéro ne figure pas dans l'historique distant et la fonction est absente de Supabase. L'écran vendeur appelle cette RPC ; lorsqu'elle échoue, il retombe sur l'interface de stock parent, tandis que la RPC serveur refuse déjà la modification parent pour les produits gérés par variantes.

**Impact :** le parcours lecture/édition du stock par variante n'est pas complet sur la base actuellement connectée.

**Correction :** tester cette migration sur une base/branche locale reconstruite, vérifier les droits et l'appartenance vendeur, puis la déployer avec procédure de migration contrôlée et test de non-régression.

Suivi : https://linear.app/faso/issue/RIA-28/catalogue-ajouter-ledition-du-stock-par-variante-dans-lespace-vendeur

#### AUD-05 — Wave et CinetPay ne sont pas configurés
**État : confirmé par les derniers contrôles de santé enregistrés le 6 novembre 2026.**

- Wave : `NOT_CONFIGURED`, motif `WAVE_API_KEY_missing`.
- CinetPay : `NOT_CONFIGURED`, motif `CINETPAY_API_KEY_or_SITE_ID_missing`.
- Les fonctions de création de session v3 renvoient volontairement HTTP 503 quand les clés nécessaires manquent.

**Impact :** aucun parcours de paiement réel ne peut être certifié. Orange Money et Moov Money sont proposés via CinetPay dans l'architecture, mais restent soumis à la configuration marchande CinetPay.

**Correction :** terminer KYC/activation marchande, configurer les secrets côté Supabase, puis tester avec les environnements de test et des webhooks signés. Aucun secret ne doit être copié dans Flutter, GitHub ou un ticket.

#### AUD-06 — Notifications push FCM bloquées par l'absence de configuration Firebase serveur
**État : confirmé dans les journaux de la fonction `dispatch-push-notifications` version 10.**

Les journaux du 6 novembre 2026 montrent à répétition `fcm_service_account_missing` et `hasFcmProjectId: false`. Le worker renvoie HTTP 503 `fcm_not_configured` au lieu de déclarer une notification envoyée. Les fichiers natifs `google-services.json`, `GoogleService-Info.plist` et `firebase_options.dart` sont absents du dépôt.

**Correction :** associer les applications Android/iOS à un vrai projet Firebase, activer APNs pour iOS, installer les fichiers officiels et configurer `FCM_SERVICE_ACCOUNT_JSON` et `FCM_PROJECT_ID` comme secrets Edge Function. Ensuite, tester une notification réelle sur un appareil contrôlé.

Suivi complémentaire : https://linear.app/faso/issue/RIA-26/notifications-integrer-la-desactivation-du-token-avant-chaque

#### AUD-07 — Dérive de l'historique des migrations
**État : confirmé ; reproductibilité complète non démontrée.**

- GitHub contient 323 migrations, Supabase en consigne 321.
- `20261104020500_add_toy_weapon_product_classification.sql` est locale mais absente de l'historique distant ; pourtant la fonction `private.scan_toy_weapon_products()` et son cron actif existent déjà dans la base. Cela indique une dérive d'historique ou une opération manuelle à réconcilier.
- `20261106180000_add_secure_seller_variant_inventory_read.sql` est locale et sa fonction n'existe pas sur le serveur.
- La documentation du dépôt indique également que l'ancien historique SQL n'est pas encore entièrement reproductible sur une base vide.

**Correction :** établir un état de référence entre les migrations locales, l'historique distant et le schéma réel ; reconstruire une base locale vide ; résoudre les migrations appliquées manuellement et les versions manquantes avant d'utiliser `db reset` comme preuve de déploiement. Ne pas appliquer automatiquement les deux migrations.

#### AUD-08 — Validation CI non démontrée sur le dernier commit de `main`
**État : confirmé dans la configuration et les exécutions consultées.**

- Les workflows Flutter, base Supabase et build natif sont déclenchés par `workflow_dispatch` uniquement ; ils ne se déclenchent pas automatiquement sur push ou pull request.
- Les dernières exécutions consultées sur `main` (5 novembre 2026) se sont terminées en échec avant attribution d'un runner : `runner_id=0`, aucune étape exécutée.
- Cela ne prouve pas une erreur de compilation ou de code ; les commandes n'ont pas été lancées.
- Le workflow Flutter utilise `flutter analyze --no-fatal-warnings --no-fatal-infos`, ce qui ne rend pas les avertissements bloquants.

**Correction :** réactiver une CI automatique sur push/PR, obtenir un runner opérationnel, faire exécuter `flutter pub get`, `flutter analyze`, `flutter test`, `deno check`, `supabase db reset` et `supabase test db`. Garder les échecs visibles et corriger leur cause réelle.

#### AUD-09 — Publication Android/iOS non prête
**État : confirmé par les fichiers de configuration.**

- Android refuse volontairement le build release si `android/key.properties` ou le keystore de signature manque. Seul le modèle `android/key.properties.example` est versionné.
- Le workflow natif ne charge aucune signature depuis des secrets ; il lance néanmoins `flutter build appbundle --release`.
- Le job iOS ne produit qu'un build simulateur debug non signé ; ce n'est pas un IPA App Store/TestFlight.

**Correction :** séparer validation native et release, injecter les secrets de signature de façon protégée, conserver le keystore hors Git et mettre en place une vraie archive iOS signée avec certificats/profils Apple.

### P2 — Fonctionnalités, autorisations et fiabilité à compléter

#### AUD-10 — Cinq verticales sont consultables mais sans action métier
**État : confirmé dans `vertical_discovery_page.dart`.**

Les modules immobilier, professionnels, agriculture, santé et créatifs n'appartiennent pas à `_hasAction`. Ils peuvent afficher des annonces, mais la page ne fournit pas le bouton de demande, réservation, commande ou candidature correspondant.

**Correction :** définir pour chaque verticale son parcours métier, les contrôles de disponibilité/propriété, les RPC de création et les statuts, puis ajouter l'interface et les tests.

#### AUD-11 — Les routes ne contrôlent pas la session ou le rôle avant d'afficher les pages protégées
**État : confirmé au niveau du routeur.**

`GoRouter` ne définit ni `redirect` ni `refreshListenable` lié à l'état d'authentification. Les routes `/admin/*`, `/seller/*`, `/courier`, `/orders` et plusieurs pages privées sont enregistrées sans garde UI.

**Impact :** un utilisateur non connecté peut atteindre visuellement ces pages et obtenir des erreurs ou des écrans vides. Cela ne prouve pas à lui seul un contournement des RLS/RPC côté serveur ; les autorisations serveur restent la frontière de sécurité.

**Correction :** ajouter des gardes de route et une redirection selon session, statut de compte, rôle et permissions, tout en gardant les mêmes vérifications côté serveur.

#### AUD-12 — Le modèle de rôles administrateur ne différencie pas encore les permissions
**État : confirmé dans le schéma et les fonctions SQL inspectées.**

Les tables `admin_roles` et la colonne `admin_users.admin_role_id` existent, mais aucune fonction SQL inspectée ne référence `admin_role_id` ou `admin_roles`. `private.is_admin()` vérifie seulement qu'une ligne `admin_users` est active et que le profil est actif. Les opérations administratives qui l'appellent accordent donc un accès administrateur commun, sans matrice de permissions basée sur le rôle lié.

**Correction :** décider des profils ADMIN/SUPER_ADMIN/finance/modération/logistique, créer une matrice de permissions serveur et tester les refus négatifs. Le compte propriétaire initial n'est pas encore provisionné et aucune création n'a été réalisée pendant cet audit.

#### AUD-13 — Le cycle de déconnexion et de désactivation des tokens n'est pas intégré
**État : confirmé. Lié à Linear RIA-26.**

La méthode `signOutAndDeactivateCurrentDevice()` existe, mais aucune interface de déconnexion ni aucun appel de déconnexion n'a été retrouvé dans le code Flutter. En outre, la RPC `deactivate_notification_device` renvoie toujours `true`, même si aucune ligne n'a été désactivée ; côté Flutter, la RPC n'est appelée que si le token courant est en cache.

**Correction :** intégrer un seul service de déconnexion à tous les rôles, vérifier le nombre de lignes réellement désactivées, gérer token absent/rotation/session expirée et tester la reprise si le réseau échoue.

#### AUD-14 — Le suivi GPS ne fonctionne pas en arrière-plan
**État : confirmé dans les manifests natifs et le code coursier.**

Le coursier transmet sa position au premier plan, avec une fréquence de 15 secondes. Android n'a pas de permission/service de localisation arrière-plan dédié ; iOS n'a pas le mode background `location`. Les autorisations descriptives iOS sont présentes, mais elles ne remplacent pas l'implémentation du service.

**Impact :** la position n'est pas garantie si l'application est suspendue ou fermée. Ne pas promettre un suivi continu en arrière-plan à ce stade.

**Correction :** mettre en place un service de localisation en arrière-plan conforme aux règles Android/iOS, consentement explicite, notification persistante, redémarrage/récupération et arrêt à la fin de mission ; tester sur appareils réels.

#### AUD-15 — Trois fonctions Edge déployées n'ont pas de source correspondante dans GitHub
**État : confirmé.**

Supabase expose 21 fonctions actives ; le dépôt contient 18 dossiers de fonctions avec `index.ts`. Les fonctions déployées sans source locale correspondante sont :
- `expire-products` v2 ;
- `admin-health-check` v2 ;
- `payment-webhook-gateway` v3.

La dernière est un ancien endpoint qui répond explicitement HTTP 410 `legacy_endpoint_retired`, mais demeure déployé. Les deux premières ont du code métier et des contrôles administrateur côté serveur.

**Correction :** versionner les deux sources manquantes, documenter le tombstone 410, puis vérifier les références entrantes et sortantes avant de désactiver une ancienne fonction.

#### AUD-16 — Le moniteur de santé ne teste que deux buckets sur cinq
**État : confirmé dans `platform-health-monitor` v5.**

Le contrôle Storage interroge `order-feedback-media` et `product-media` uniquement. Les buckets `avatars`, `documents` et `shop-media` ne sont pas couverts par cette vérification. Au moment de l'audit, aucun objet n'était stocké dans les cinq buckets ; les vrais flux upload/download/URL signée/suppression n'ont donc pas été validés.

**Correction :** étendre les probes à tous les buckets selon le niveau d'accès attendu et exécuter des tests avec des objets factices, en vérifiant les accès positifs et négatifs pour chaque rôle.

#### AUD-17 — Couverture des tests métier insuffisante
**État : confirmé par l'inventaire, niveau de risque à mesurer.**

Trois fichiers de tests Dart couvrent le démarrage, le routage des notifications et la configuration du dépôt des verticales. Deux suites pgTAP contiennent 41 et 13 assertions, surtout sur permissions/sécurité. Il manque encore une preuve automatisée de bout en bout pour panier/checkout, concurrence du stock, remboursements, annulations globales, paiement/webhooks simulés, transport, mécaniciens, réservation et GPS.

**Correction :** ajouter tests unitaires de calcul, tests de repositories, tests Widget des parcours, tests SQL positifs/négatifs et tests d'intégration des webhooks avec signatures/faux fournisseurs.

#### AUD-18 — Capacité, sauvegarde et restauration non certifiées
**État : non testé.**

Aucun résultat probant n'a été trouvé pour une charge de 1 000 à 10 000 connexions simultanées, un test de reprise après panne, une restauration réelle de sauvegarde ou un exercice de continuité.

**Correction :** établir les objectifs de charge et latence, tester progressivement les scénarios de concurrence (checkout/stock/notifications), puis exécuter une restauration vérifiée et mesurer RPO/RTO avant lancement.

#### AUD-19 — Authentification utilisateur encore limitée
**État : confirmé dans l'écran de connexion actuel ; décision produit nécessaire.**

L'écran `SignInPage` propose email/mot de passe et inscription email. Aucun parcours « mot de passe oublié » n'y est visible ; aucun flux OTP par téléphone n'a été retrouvé. Si la connexion par numéro burkinabè et la récupération autonome de compte font partie du cahier des charges, ces parcours restent à construire.

**Correction :** décider des modes d'identification (email, téléphone/OTP ou les deux), de la récupération, de la vérification, de la politique de mot de passe et de la protection anti-abus.

### P3 — Alertes d'information, pas des défauts à corriger en masse

#### AUD-20 — 368 index signalés inutilisés
**État : information de l'advisor performance.**

Le signal « unused index » dépend des statistiques d'utilisation et du trafic observé. Le volume métier est actuellement quasi nul. Ne pas supprimer ces index sans mesure en charge et examen des requêtes/contraintes.

#### AUD-21 — 17 tables RLS sans policy
**État : contrôlé, non retenu comme vulnérabilité directe.**

Les 17 tables sont des tables privées ou des tables médias protégées ; les privilèges directs SELECT des rôles `anon` et `authenticated` sont absents. Ne pas ajouter des policies permissives pour faire disparaître l'avis de l'advisor.

#### AUD-22 — Avertissements génériques SECURITY DEFINER et extensions PostGIS
**État : à suivre, pas une preuve de 80 vulnérabilités.**

L'advisor rapporte 80 fonctions SECURITY DEFINER exécutables par `authenticated` et trois surcharges C PostGIS `st_estimatedextent` exécutables par `anon`. Le scan de définition n'a pas trouvé de fonction PL/pgSQL applicative accessible sans référence à une vérification d'identité/administrateur ; les trois fonctions sans search_path fixe sont les fonctions C PostGIS. Cela ne remplace pas une revue détaillée de chaque fonction, mais interdit de révoquer globalement les 80 sans analyse.

## 3. Contrôles qui ne justifient pas une correction immédiate

- Les tables `review_media` et `delivery_evidence` ont RLS et aucun droit direct SELECT pour `anon`/ `authenticated`, bien qu'elles n'aient pas de policy propre.
- Le flux `cancel_unpaid_order` est distinct de la RPC globale : il limite l'annulation au client propriétaire d'une commande en attente de paiement et libère les réservations/colis.
- Les RPC de stock par variante et les réservations/consommations/libérations utilisent le stock par variante ; le problème connu est la lecture vendeur manquante sur la base distante, pas la totalité du moteur de réservation.
- Les webhooks Wave/CinetPay ont `verify_jwt=false` à la passerelle par conception, mais vérifient les signatures fournisseur dans le code. Ne pas réactiver aveuglément le JWT sur des callbacks fournisseurs.
- `payment-return` affiche un message statique selon le statut et encode l'identifiant de commande dans le deep link ; l'examen du code ne montre pas de redirection arbitraire contrôlée par l'utilisateur.
- Les cinq buckets ont des limites de taille/types MIME et les quatre buckets non-avatar sont privés ; il reste à tester les vrais flux fichiers.
- Les 9 comptes de démonstration sont uniquement dans le seed de test local `supabase/seed.test.sql`. La base hébergée auditée contient zéro utilisateur Auth, zéro profil, zéro rôle, zéro administrateur et zéro rôle admin. Le déclencheur d'inscription crée un profil CUSTOMER ; il ne crée pas le propriétaire SuperAdmin. Aucun compte n'a été créé pendant cet audit.

## 4. Ordre de correction recommandé

1. AUD-01 — demander à Supabase Support le déplacement non destructif de PostGIS vers `extensions`, puis adapter les deux RPC métier.
2. AUD-02 et AUD-03 — définir puis corriger ensemble le calcul comptable des remboursements et les transitions de commande/colis.
3. AUD-07 — rendre l'état de base reproductible et réconcilier les migrations.
4. AUD-04 — déployer/tester la lecture sécurisée du stock par variante après validation locale.
5. AUD-08 et AUD-17 — rendre les tests automatiques exécutables et étendre la couverture.
6. AUD-05 et AUD-06 — configurer les fournisseurs et Firebase, puis tester les parcours réels contrôlés.
7. AUD-11 à AUD-16 — compléter les autorisations UI, RBAC, déconnexion, GPS et synchronisation des fonctions Edge.
8. AUD-09 et AUD-18 — achever la publication native, la capacité et la restauration.
9. AUD-10 et AUD-19 — terminer les fonctionnalités et parcours d'authentification prévus par le produit.

## 5. Limites de l'audit

Cet audit combine inspection de fichiers, recherches ciblées, lecture de fonctions SQL actives, privilèges, historique des migrations, listes de fonctions et journaux. Il ne constitue pas un audit ligne par ligne certifié de chaque fichier ni un pentest externe. Les SDK Flutter/Dart/Deno n'ont pas été exécutés depuis cet environnement ; les dernières exécutions GitHub consultées n'ont pas démarré de runner. Aucun paiement, push, GPS en arrière-plan, scénario multi-utilisateur, charge, sauvegarde ou restauration réelle n'a été effectué.

Le registre doit être mis à jour après chaque correction avec : référence du commit, migration éventuelle, tests exécutés, résultat CI et preuve de non-régression.
