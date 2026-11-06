# Audit global — Marketplace Multiservices Burkina

**Date de l'audit :** 7 novembre 2026  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina`  
**Branche :** `main`  
**Supabase :** `dzhhsoikzxibmngjzcch` — PostgreSQL 17.6 — `eu-west-1`  
**Nature :** audit statique du dépôt + contrôles Supabase + examen des workflows et journaux.  
**Mises à jour AUD-01/AUD-03/AUD-04/AUD-06/AUD-16 :** préparation PostGIS, durcissement des annulations impayées, lecteur sécurisé du stock par variante, surveillance FCM et contrôle des cinq buckets appliqués/déployés. Seules les fonctions de santé et les tables de diagnostic ont été modifiées ; aucun paiement, remboursement, stock, solde vendeur ou compte utilisateur n'a été créé/modifié.

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
| Assertions pgTAP prévues dans ces deux fichiers | 60 (47 + 13) |
| Tables Supabase `public` et `private` | 182 |
| Tables publiques avec RLS | 166/167 |
| Tables privées avec RLS | 15/15 |
| Migrations SQL présentes dans GitHub | 328 |
| Migrations consignées dans Supabase | 327 |
| Fonctions Edge actives dans Supabase | 21 |
| Dossiers sources Edge avec `index.ts` dans GitHub | 18 |
| Buckets Storage | 5 |

Les mesures de quantité ne prouvent pas la qualité fonctionnelle. Les 60 assertions SQL couvrent notamment des permissions et des contrôles de sécurité, mais ne constituent pas une suite de tests de bout en bout pour les parcours commerciaux.

## 2. Registre des anomalies — ordre de correction proposé

### P1 — Risque d'intégrité et de disponibilité à traiter avant l'ouverture publique

#### AUD-01 — PostGIS installé dans `public` : métadonnées spatiales modifiables via la Data API
**État : confirmé. Préparation des RPC terminée et vérifiée ; déplacement de l'extension encore en attente de Supabase Support.**

- PostGIS 3.3.7 est installé dans `public` et appartient à `supabase_admin`.
- `public.spatial_ref_sys` contient 8 500 définitions de systèmes de coordonnées. `anon` et `authenticated` ont des privilèges INSERT, UPDATE, DELETE et TRUNCATE, hérités des privilèges par défaut du propriétaire de l'extension.
- Ce constat ne signifie pas que les données personnelles ou les coordonnées de livraison sont lisibles dans `spatial_ref_sys`. Le risque principal est l'intégrité : une modification ou suppression d'un SRID peut faire échouer les calculs géographiques et donc dégrader la livraison/localisation.
- Le rôle de projet ne peut ni activer RLS ni retirer les privilèges accordés par `supabase_admin`. Un `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, un `REVOKE` ou un trigger de blocage n'est pas une correction valable.
- Trois colonnes `geography` existent : `courier_locations.location`, `provider_locations.location` et `shops.location`. Elles contiennent actuellement zéro ligne. Deux index GiST ont été recensés (`courier_locations`, `shops`). Il faut préserver tables, types, index et vues.
- Deux fonctions applicatives utilisaient explicitement les noms `public.st_*` et `public.geography` : `calculate_delivery_fee(uuid,jsonb)` et `record_courier_location(double precision,double precision,numeric)`. Elles ont maintenant été préparées dans la migration `20261106195420_aud01_prepare_postgis_functions_schema_fallback.sql` : `search_path = pg_catalog, extensions, public` et références PostGIS non qualifiées. Cette stratégie fonctionne avec PostGIS dans `public` aujourd'hui et résoudra les objets dans `extensions` après le déplacement.
- Aucun autre appel applicatif direct à une RPC PostGIS ni vue métier dépendante de PostGIS n'a été identifié dans les contrôles effectués. Aucune extension supplémentaire dépendant de PostGIS n'a été détectée.

**Risque :** altération possible des définitions SRID, pouvant rendre les calculs spatiaux indisponibles. Ce n'est pas une fuite de données métier. Les statistiques PostgreSQL consultées indiquent zéro UPDATE et zéro DELETE depuis la dernière remise à zéro des statistiques ; aucune tentative POST/PATCH/PUT/DELETE vers `/spatial_ref_sys` n'a été trouvée dans les journaux Data API du 6 au 7 novembre 2026. Cette vérification ne prouve pas l'absence d'activité antérieure à la période de journaux consultée.

**Correction restante :** faire déplacer l'extension PostGIS existante de `public` vers `extensions` par l'intervention non destructive de Supabase Support. Supabase documente que cette méthode préserve les colonnes PostGIS, données, index et vues et s'exécute dans une transaction. Ne pas supprimer/recréer PostGIS soi-même : cette base possède des colonnes `geography` et la procédure DROP CASCADE les supprimerait.

**Préparation déjà appliquée :** la migration `20261106195420_aud01_prepare_postgis_functions_schema_fallback.sql` a été enregistrée dans GitHub et dans Supabase. Elle modifie uniquement le `search_path` et les références PostGIS des deux RPC, sans altérer leurs contrôles métier. Le calcul spatial de test et les permissions ont été vérifiés. Voir `docs/runbooks/aud-01-postgis-schema-move.md` pour la preuve, le message Support et les contrôles restants.

### P1 — Bloquants métier, financiers et opérationnels

#### AUD-02 — Les remboursements partiels débitent potentiellement des vendeurs non concernés
**État : confirmé ; modèle de correction documenté, code financier de production non modifié. Lié à Linear RIA-25.**

`public.complete_refund(uuid,text)` répartit le montant de chaque remboursement au prorata du subtotal de **tous** les groupes vendeurs de la commande. La fonction ne reçoit pas d'allocation explicite par article, quantité ou groupe. Pour un retour partiel qui concerne une seule boutique, le ledger d'autres vendeurs peut donc être débité.

Constats complémentaires vérifiés le 7 novembre :

- `public.refunds` n'a pas de référence à un groupe, un article, un retour ou une quantité.
- `public.returns` peut référencer un seul `order_item_id`, mais n'enregistre pas la quantité demandée/acceptée et ne référence aucun remboursement.
- `request_refund(order_id, amount, reason)` ne reçoit pas la portée commerciale du remboursement.
- `orders.discount_total` conserve la remise globale ; aucune ventilation par `order_item` ou groupe n'est figée au checkout. Les sous-totaux des groupes et les prix des lignes restent bruts.
- Deux fonctions de finalisation vendeur existent avec des conventions différentes : `finalize_seller_group` crédite le `SALE` brut et débite la `COMMISSION` séparément ; `finalize_seller_group_financials` crédite le `SALE` net et conserve la commission dans une autre convention de statut. Aucun appelant SQL interne ou trigger appelant ces routines n'a été identifié lors des contrôles ; leurs appels serveur réels doivent être confirmés.
- `reverse_seller_group` est une inversion complète du groupe, pas un mécanisme générique de retour partiel d'un article.

**Risque :** imputation financière erronée entre boutiques, vendeurs, plateforme et frais de livraison ; la quantité retournée et la commission correspondante ne sont pas traçables.

**Correction retenue :** modèle explicite et immuable `refund_allocations` par groupe/article/quantité et type d'allocation, snapshots de remise/funding par ligne au checkout, règles distinctes pour le remboursement client, le débit vendeur, le reversement de commission et les frais de livraison. Les tests doivent garantir que la somme des allocations égale exactement le montant rendu au client et qu'aucun vendeur non concerné n'est débité.

**Limite volontaire :** ne pas modifier `complete_refund`, `refunds`, `seller_ledger`, les commissions ou les soldes avant validation des règles coupons/livraison/commission et tests sur base isolée. Le runbook `docs/runbooks/aud-02-refund-allocation.md` contient le diagnostic, le modèle recommandé, les invariants et la matrice de tests.

Suivi : https://linear.app/faso/issue/RIA-25/bloquant-finance-corriger-lallocation-des-remboursements-partiels

#### AUD-03 — L'annulation globale ne synchronisait pas les colis, affectations et remboursements
**État : correction serveur appliquée et vérifiée pour le chemin d'annulation globale ; tests d'intégration et validation des parcours utilisateurs encore requis. Lié à Linear RIA-29.**

Avant correction, `public.transition_order_status(uuid,order_status,text)` pouvait annuler directement une commande payée, libérer les stocks et ne pas fermer tous les colis/affectations ni lancer un remboursement cohérent.

**Corrections appliquées sur Supabase :** migrations `20261106200419_block_global_order_cancel_and_harden_unpaid_cancellation.sql` et `20261106201500_aud03_allow_admin_to_cancel_unpaid_orders_safely.sql`.

- La transition globale `CANCELLED` délègue maintenant à `public.cancel_unpaid_order(uuid)`. Elle ne marque plus directement une commande payée comme annulée et ne libère plus le stock elle-même.
- Le parcours impayé exige un compte actif et une commande `PENDING_PAYMENT` ; l'appelant doit être le client propriétaire ou un administrateur actif enregistré (`private.is_admin()`). Un administrateur ne peut donc pas utiliser ce chemin pour annuler une commande payée.
- Il refuse toute commande ayant un colis/une affectation déjà ramassé(e), en transit, livré(e), retourné(e), endommagé(e) ou perdu(e), ainsi qu'une consommation de stock déjà enregistrée.
- Il libère le stock par produit et variante, annule les affectations pré-départ et écrit `delivery_assignment_events`, annule les colis/groupes, libère les utilisations de coupons et journalise l'annulation dans `order_events`.
- Les privilèges `EXECUTE` restent limités à `authenticated` et `service_role`, pas à `anon`.

**Vérification SQL après migration :** propriétaire PostgreSQL et `SECURITY DEFINER` conservés ; délégation vers le flux impayé confirmée ; absence de libération de stock directe dans la fonction globale confirmée ; gardes paiement/dispatch/consommation confirmées dans le flux impayé ; aucun accès anon. La base ne contient actuellement aucune commande, paiement, réservation de livraison, remboursement ou utilisation de coupon : aucun flux métier réel n'a été exécuté.

**Limites restantes :** trois assertions de régression supplémentaires sont maintenant présentes dans `security_regression_test.sql` (plan du fichier : 44), mais elles ne sont pas exécutées ; les parcours Flutter/Edge doivent être testés sur un runner et une base isolée. L'annulation d'une commande déjà payée reste volontairement bloquée par cette RPC tant qu'un workflow de remboursement/retour complet n'est pas défini (voir AUD-02). Cette correction ne déclare pas le ticket RIA-29 entièrement terminé.

Suivi : https://linear.app/faso/issue/RIA-29/commande-securiser-lannulation-globale-et-synchroniser-colis

#### AUD-04 — Le lecteur sécurisé du stock par variante a été déployé
**État : correction backend appliquée et vérifiée ; intégration réelle vendeur à valider. Lié à Linear RIA-28.**

La RPC `public.get_seller_product_variant_inventory(uuid)` manquait sur Supabase alors que l'écran vendeur et `SellerProductsRepository.variantInventory()` l'appelaient déjà.

**Correction appliquée :** migration Supabase `20261106201211_add_secure_seller_variant_inventory_read.sql`. La migration initialement locale a été réalignée sur le numéro exact généré et enregistré par Supabase.

- La RPC exige un compte actif, une session authentifiée et vérifie que le produit appartient à une boutique du vendeur connecté.
- Elle retourne les variantes et les valeurs `quantity` / `reserved_quantity` via un `LEFT JOIN`, donc les variantes sans ligne d'inventaire affichent correctement zéro.
- `authenticated` peut exécuter la RPC ; `anon` et `PUBLIC` ne le peuvent pas.
- La table `public.product_variant_inventory` conserve sa policy de refus d'accès direct et aucun droit SELECT n'est accordé à `anon` ou `authenticated`.
- L'écran Flutter avait déjà le parcours de lecture et d'édition par variante. J'ai supprimé son retour automatique vers l'éditeur de stock parent lorsqu'une lecture de variantes échoue ; il affiche maintenant une erreur et ne tente aucune modification parent dans ce cas.
- Le fichier pgTAP contient une assertion supplémentaire sur la présence de la RPC, son contrôle propriétaire et l'absence de lecture directe. Le plan de `security_regression_test.sql` est maintenant de 45 assertions ; elles n'ont pas été exécutées.

**Limite :** la base ne contient pas encore de compte vendeur ni de produits/variantes de test ; l'exécution réelle de l'écran et la mise à jour des quantités doivent être validées sur un compte vendeur de test avant clôture. Aucun stock réel n'a été changé.

Suivi : https://linear.app/faso/issue/RIA-28/catalogue-ajouter-ledition-du-stock-par-variante-dans-lespace-vendeur

#### AUD-05 — Wave et CinetPay ne sont pas configurés
**État : confirmé par une exécution réelle du moniteur de santé le 6 novembre 2026 à 20:19:04 UTC. Code et webhooks actifs ; comptes marchands/secrets manquants.**

- Wave : `NOT_CONFIGURED`, motif `WAVE_API_KEY_missing`. `create-wave-payment-session-v3` v4 exige `WAVE_API_KEY`; le webhook `wave-payment-webhook-v3` v4 exige `WAVE_WEBHOOK_SECRET`. `WAVE_SIGNING_SECRET` est optionnel pour signer les appels sortants.
- CinetPay : `NOT_CONFIGURED`, motif `CINETPAY_API_KEY_or_SITE_ID_missing`. `create-cinetpay-payment-session-v3` v6 exige `CINETPAY_API_KEY` et `CINETPAY_SITE_ID`; `cinetpay-webhook-v3` v6 exige aussi `CINETPAY_SECRET_KEY`.
- Les fonctions de création renvoient HTTP 503 quand les clés nécessaires manquent ; elles ne simulent pas une session de paiement.
- Les webhooks sont configurés avec `verify_jwt=false` par conception : Wave vérifie une signature HMAC sur le corps brut et une fenêtre temporelle de cinq minutes ; CinetPay vérifie le HMAC de `x-token`, le site marchand et le statut auprès de l'API fournisseur avant `process_payment_event`. Ne pas retirer ces vérifications ni imposer le JWT Supabase sur les callbacks fournisseurs.

**Impact :** aucun parcours de paiement réel ne peut être certifié. Orange Money et Moov Money restent soumis à l'activation marchande CinetPay et aux méthodes activées par le compte.

**Correction restante :** terminer le KYC/activation marchande, obtenir les clés directement depuis les portails marchands et les configurer via Supabase Edge Function Secrets. Le runbook `docs/runbooks/aud-05-06-payment-and-fcm-configuration.md` détaille les noms exacts requis et la séquence de validation. Aucun secret ne doit être copié dans Flutter, GitHub ou un ticket. Aucun paiement réel n'a été effectué.

#### AUD-06 — Notifications push FCM bloquées par l'absence de configuration Firebase serveur
**État : défaut de configuration confirmé et maintenant visible dans le moniteur de santé version 7 ; aucun push réel testé.**

- `dispatch-push-notifications` v10 exige `FCM_SERVICE_ACCOUNT_JSON` et un `project_id` dans le JSON ou `FCM_PROJECT_ID` en secours.
- Les journaux consultés dans la fenêtre par défaut de l'outil comportaient 324 événements `fcm_service_account_missing`, avec `hasFcmProjectId: false`. Le worker renvoie HTTP 503 `fcm_not_configured`.
- Le moniteur `platform-health-monitor` est maintenant en v7 et publie un composant `FCM`. Son dernier contrôle manuel du 6 novembre à 20:19:04 UTC a enregistré `NOT_CONFIGURED`, raison `FCM_SERVICE_ACCOUNT_JSON_missing`, `has_fcm_project_id=false`.
- Deux migrations étendent la liste blanche SQL et la contrainte de `private.platform_health_checks` pour accepter le composant FCM : `20261106201627_allow_fcm_platform_health_component.sql` et `20261106201705_allow_fcm_health_check_component.sql`. La fonction `private.record_platform_health_checks` reste exécutable uniquement par `service_role`.
- Deux assertions pgTAP vérifient que FCM est autorisé dans l'enregistreur et la contrainte, et que la frontière `service_role` seule est conservée. Le fichier `security_regression_test.sql` compte désormais 47 assertions ; elles n'ont pas encore été exécutées.

**Correction restante :** associer Android/iOS à un projet Firebase, activer APNs pour iOS, créer un compte de service autorisé pour Firebase Cloud Messaging et saisir le JSON directement dans Supabase Edge Function Secrets. Configurer `FCM_PROJECT_ID` seulement si le champ `project_id` n'est pas fourni dans le JSON. Ne jamais placer la clé privée dans GitHub, Flutter ou la conversation. Effectuer ensuite un vrai push sur un appareil de test, avec consentement et vérification du token.

#### AUD-07 — Dérive de l'historique des migrations
**État : un seul numéro non réconcilié ; effets fonctionnels déjà présents et équivalence vérifiée. Réparation historique CLI préparée.**

- GitHub contient 328 migrations, Supabase en consigne 327. Le seul numéro GitHub absent de l'historique distant est `20261104020500_add_toy_weapon_product_classification.sql`.
- Le corps de `private.scan_toy_weapon_products()` dans le fichier et dans la base est identique après normalisation des espaces ; propriétaire `postgres`, `SECURITY DEFINER`, `search_path = ''`, ACL n'accordant EXECUTE qu'à postgres.
- Le cron distant `toy-weapon-classifier` est actif, ID 5, toutes les 10 minutes, commande exacte `select private.scan_toy_weapon_products();`. Les tables dépendantes sont présentes.
- Les dernières migrations AUD-01/AUD-03/AUD-04/FCM sont présentes dans les deux historiques. Le fichier de stock variante et la migration AUD-03 admin ont été alignés sur leur timestamp exact.

**Correction restante :** exécuter uniquement la réparation d'historique officielle, sans rejouer le SQL :
`supabase link --project-ref dzhhsoikzxibmngjzcch`, puis `supabase migration repair 20261104020500 --status applied`, puis `supabase migration list`. La procédure complète figure dans `docs/runbooks/aud-07-reconcile-toy-weapon-migration-history.md`.

La commande CLI n'est pas disponible via les connecteurs actuels ; aucune insertion manuelle dans la table d'historique n'a été faite et aucun cron/fonction n'a été réexécuté. Résultat attendu : 328 migrations locales et distantes.

#### AUD-08 — CI automatique préparée ; exécution GitHub Actions bloquée avant la première étape
**État : workflows automatiques ajoutés sur `main`, mais le runner GitHub n'a pas exécuté les étapes lors des premières tentatives.**

- Les anciens workflows Flutter/DB étaient déclenchés seulement manuellement.
- Deux workflows ciblés ont été ajoutés sur `main` :
  - `.github/workflows/flutter-ci.yml` : déclenchement sur push/PR des fichiers Flutter ; vérifie format sans modifier les sources, dépendances, analyse Flutter et tests.
  - `.github/workflows/supabase-functions-ci.yml` : déclenchement sur push/PR des fonctions Edge ; lance `deno check` sur chaque `index.ts`.
- Le build Android/iOS de publication reste distinct et manuel ; les workflows automatiques ne demandent pas les secrets de signature et ne déclenchent pas de paiements.
- Les premiers runs sur `main` ont été créés le 6 novembre 2026 à 20:24:11 UTC (Flutter run `42288045950`, Edge run `42288049924`). Les deux se sont terminés en échec en quelques secondes ; la lecture des jobs retourne `steps=[]` et aucun journal de job n'est disponible. Aucune commande `flutter`, `dart` ou `deno` n'a donc été exécutée par ces jobs. Ce n'est pas une preuve d'échec de compilation.
- La PR brouillon `#1` (`codex/bootstrap`) contient aussi des workflows automatiques, mais comporte 584 fichiers modifiés, est non fusionnée et n'est pas mergeable actuellement. Elle n'a pas été fusionnée ni utilisée comme source unique de vérité.

**Correction restante :** vérifier les paramètres Actions du dépôt (Actions activées, politique d'exécution, minutes/quota, runner hébergé ou runner group, éventuelle limite de facturation), puis relancer les runs. Ne pas désactiver les validations en réponse à l'absence de runner. Une fois qu'un runner démarre, corriger les vrais échecs de format, analyse, tests ou type-check observés.

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

#### AUD-16 — Le moniteur Storage ne couvrait initialement que deux buckets sur cinq
**État : correction de surveillance appliquée et testée ; flux d'accès aux objets encore à valider.**

Le contrôle initial ne vérifiait que `order-feedback-media` et `product-media`. La fonction `platform-health-monitor` v7 vérifie maintenant les cinq buckets réels : `avatars`, `documents`, `order-feedback-media`, `product-media` et `shop-media`.

Le contrôle manuel du 6 novembre 2026 à 20:19:02 UTC a renvoyé HTTP 200 et les cinq buckets ont répondu `UP` avec HTTP 200.

**Limite :** ce probe confirme que le bucket existe et répond au point d'accès Storage privilégié ; il ne démontre pas un upload, un téléchargement, une URL signée, ni l'application des règles RLS/Storage par rôle. Les tests de fichiers factices et les accès positifs/négatifs pour client, vendeur et administrateur restent requis. Les buckets `documents`, `shop-media`, `product-media` et `order-feedback-media` sont privés ; `avatars` est public selon sa configuration actuelle.

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

1. AUD-01 — demander à Supabase Support le déplacement non destructif de PostGIS vers `extensions`, puis vérifier les RPC déjà préparées dans le `search_path` compatible avant/après migration.
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
