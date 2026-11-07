# Audit global — Marketplace Multiservices Burkina

**Date de l'audit :** 7 novembre 2026  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina`  
**Branche :** `main`  
**Supabase :** `dzhhsoikzxibmngjzcch` — PostgreSQL 17.6 — `eu-west-1`  
**Nature :** audit statique du dépôt + contrôles Supabase + examen des workflows et journaux.  
**Mises à jour AUD-01/AUD-03/AUD-04/AUD-05/AUD-06/AUD-11/AUD-12/AUD-13/AUD-14/AUD-15/AUD-16/AUD-17/AUD-18/AUD-19/AUD-20/AUD-21/AUD-22 :** protections commandes, accès et GPS renforcées, 22 Edge Functions versionnées, précontrôle paiement avant création de commande, récupération email, couverture pgTAP accrue et revue SECURITY DEFINER. Aucun paiement réel, test de charge ou restore production, compte propriétaire ou associé n'a été réalisé.

## 1. Conclusion

L'application possède déjà une base fonctionnelle étendue, mais elle **n'est pas prête pour une mise en production**. Les blocages les plus importants portent sur la sécurité d'une table PostGIS exposée, l'allocation comptable des remboursements, l'annulation des commandes payées, la configuration réelle des paiements/notifications, la dérive entre migrations locales et base distante, et l'absence de validation automatisée fiable sur le dernier commit de `main`.

Les constats ci-dessous sont classés par gravité et par dépendance. « Confirmé » signifie que le défaut ou l'absence a été vu directement dans le code, les privilèges SQL, les migrations ou les journaux. « À valider » signifie qu'un essai réel ou une décision métier est encore nécessaire. Les alertes génériques de l'advisor Supabase ne sont pas considérées automatiquement comme des vulnérabilités.

### Inventaire technique vérifié

| Mesure | Résultat |
|---|---:|
| Entrées dans l'arbre GitHub | 657 |
| Fichiers Dart sous `lib/` | 76 |
| Fichiers de tests Dart | 8 |
| Tests SQL dans `supabase/tests/database` | 5 |
| Assertions pgTAP prévues dans ces cinq fichiers | 105 (56 + 13 + 13 + 11 + 12) |
| Tables Supabase `public` et `private` | 183 |
| Tables publiques avec RLS | 167/168 |
| Tables privées avec RLS | 15/15 |
| Migrations SQL présentes dans GitHub | 338 |
| Migrations consignées dans Supabase | 337 |
| Fonctions Edge actives dans Supabase | 22 |
| Dossiers sources Edge avec `index.ts` dans GitHub | 22 |
| Buckets Storage | 5 |

Les mesures de quantité ne prouvent pas la qualité fonctionnelle. Les 82 assertions pgTAP prévues couvrent notamment des permissions, les protections RLS et des contrats de commande/livraison ; elles ne constituent pas une suite de tests de bout en bout pour les parcours commerciaux.

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
- `request_refund(order_id, amount, reason)` ne reçoit pas la portée commerciale du remboursement ; l'écran client ne permet que saisir un montant global et un motif.
- `orders.discount_total` conserve la remise globale ; aucune ventilation par `order_item` ou groupe n'est figée au checkout. Les sous-totaux des groupes et les prix des lignes restent bruts.
- Deux fonctions de finalisation vendeur existent avec des conventions différentes : `finalize_seller_group` crédite le `SALE` brut et débite la `COMMISSION` séparément ; `finalize_seller_group_financials` crédite le `SALE` net et conserve la commission dans une autre convention de statut. Aucun appelant SQL interne, trigger ou job `pg_cron` n'a été identifié ; la recherche du code de la branche `main` ne trouve pas non plus d'appelant Flutter/Edge. L'existence éventuelle d'un appel externe hors dépôt reste à confirmer.
- `reverse_seller_group` est une inversion complète du groupe, pas un mécanisme générique de retour partiel d'un article.
- L'index unique `uq_seller_ledger_ref_type(seller_id, entry_type, reference_id)` peut provoquer une violation lorsque le même vendeur possède plusieurs boutiques/groupes dans une commande : `complete_refund` écrit une ligne REFUND par groupe avec le même `refund_id`.
- `execute-payment-refund` appelle Wave avant `complete_refund` : une confirmation externe suivie d'une erreur ledger annule la transaction SQL et peut laisser le remboursement local en PROCESSING alors que Wave l'a déjà exécuté.
- Le chemin `process_payment_event` crée une demande de remboursement lorsque le fournisseur confirme un paiement après annulation de commande. Mais `complete_refund` ne vérifie pas l'existence d'un crédit SALE avant de débiter les vendeurs ; il peut créer une écriture négative sur une vente jamais créditée. Il passe aussi les groupes en REFUNDED alors que la commande parent reste CANCELLED.
- L'index unique `uq_seller_ledger_ref_type(seller_id, entry_type, reference_id)` peut faire échouer `complete_refund` lorsque le même vendeur possède plusieurs boutiques/groupes dans une commande : la fonction insère alors plusieurs lignes `REFUND` avec le même seller_id, entry_type et refund_id.
- L'Edge Function `execute-payment-refund` appelle le prestataire Wave avant `complete_refund`. Si le prestataire confirme mais que l'insertion ledger échoue, la transaction SQL est annulée après un remboursement externe déjà exécuté ; l'Edge Function retourne `refund_completion_failed` et peut laisser la demande en `PROCESSING`.

**Risque :** imputation financière erronée entre boutiques, vendeurs, plateforme et frais de livraison ; la quantité retournée et la commission correspondante ne sont pas traçables. S'y ajoutent un possible conflit d'unicité du ledger pour un vendeur multi-boutiques, un risque de remboursement externe confirmé mais non comptabilisé localement, et un débit vendeur artificiel si un paiement est capturé après annulation avant tout crédit SALE.

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

#### AUD-05 — Wave et CinetPay non configurés ; précontrôle client ajouté
**État : secrets toujours absents ; fonctions de paiement actives ; le checkout bloque maintenant avant de créer une commande si les identifiants serveur ne sont pas présents.**

- Dernier moniteur de santé : 6 novembre 2026 à 22:20:04 UTC ; Wave `NOT_CONFIGURED` (`WAVE_API_KEY_missing`), CinetPay `NOT_CONFIGURED` (`CINETPAY_API_KEY_or_SITE_ID_missing`).
- Wave : `create-wave-payment-session-v3` v4 exige `WAVE_API_KEY`; webhook `wave-payment-webhook-v3` v4 exige `WAVE_WEBHOOK_SECRET`. `WAVE_SIGNING_SECRET` est facultatif pour signer les appels sortants.
- CinetPay : `create-cinetpay-payment-session-v3` v6 exige `CINETPAY_API_KEY` et `CINETPAY_SITE_ID`; webhook `cinetpay-webhook-v3` v6 exige aussi `CINETPAY_SECRET_KEY`.
- Les webhooks gardent `verify_jwt=false` et vérifient leur signature fournisseur (Wave HMAC/time window ; CinetPay HMAC, site ID et statut API). Ne pas retirer ces contrôles.
- Les Edge Functions de création de session répondent 503 si les secrets requis manquent ; elles ne simulent pas un paiement.

**Correction applicative ajoutée :**
- Nouvelle Edge Function `check-payment-provider-config` v1, `verify_jwt=true), retourne seulement un booléen de configuration, jamais les valeurs ou noms de secrets.
- Wave est déclaré configuré si API key et secret webhook existent ; CinetPay si API key, site ID et secret webhook existent.
- Flutter appelle cette fonction avant `checkout_cart`. Si le provider est non configuré, aucune commande n'est créée et aucun stock n'est réservé.
- Test unitaire ajouté sur le parsing de la réponse : fournisseur configuré, non configuré, statut incohérent et réponse invalide.

**Impact restant :** aucun paiement réel n'est possible tant que les comptes marchands/KYC et les clés ne sont pas activés. Le précontrôle vérifie la présence des variables serveur, pas la validité du compte, du solde marchand, du webhook ou du canal de paiement. Les tests sandbox restent requis. Runbook : `docs/runbooks/aud-05-06-payment-and-fcm-configuration.md`.

#### AUD-06 — Notifications push FCM toujours non configurées
**État : monitorage et code en place ; secrets Firebase absents ; aucune réception réelle testée.**

- `dispatch-push-notifications` v10 exige `FCM_SERVICE_ACCOUNT_JSON` et un `project_id` dans le JSON ou `FCM_PROJECT_ID` en secours.
- Dernier état FCM dans `private.platform_health_checks` : 6 novembre 2026 à 22:20:04 UTC, `NOT_CONFIGURED`, raison `FCM_SERVICE_ACCOUNT_JSON_missing`, `has_fcm_project_id=false`.
- Logs des dernières 24 h lors du relevé : 450 événements `fcm_service_account_missing` dans `function_logs`.
- `platform-health-monitor` v7 inspecte la présence et la structure des secrets sans afficher leur valeur ; il ne considère pas un push comme testé si aucun message n'a été envoyé.
- Deux migrations autorisent FCM dans `private.platform_health_checks` et sa contrainte ; enregistreur reste `service_role` uniquement.

**Correction restante :** associer Android/iOS au projet Firebase, activer APNs pour iOS, générer un compte de service limité à Firebase Cloud Messaging et saisir `FCM_SERVICE_ACCOUNT_JSON` directement dans Supabase Edge Function Secrets. Configurer `FCM_PROJECT_ID` si absent du JSON. Aucun secret ne doit aller dans GitHub/Flutter/chat. Effectuer ensuite un vrai push de test sur appareil interne autorisé ; aucun push réel n'a encore été testé.

#### AUD-07 — Dérive de l'historique des migrations
**État : un seul numéro non réconcilié ; effets fonctionnels déjà présents et équivalence vérifiée ; workflow manuel de réparation préparé.**

- GitHub contient 333 migrations SQL ; Supabase en consigne 332.
- Le seul numéro GitHub absent de l'historique distant est `20261104020500_add_toy_weapon_product_classification.sql`.
- Le corps de `private.scan_toy_weapon_products()` dans le fichier et dans la base est identique après normalisation des espaces ; propriétaire `postgres`, `SECURITY DEFINER`, `search_path = ''`, ACL n'accordant EXECUTE qu'à postgres.
- Le cron distant `toy-weapon-classifier` est actif, ID 5, toutes les 10 minutes, commande exacte `select private.scan_toy_weapon_products();`. Les trois relations dépendantes sont présentes.
- Aucun scan métier ni cron n'a été déclenché pendant l'audit ; le contenu de la fonction et le job ont été lus en catalogue.

**Correction préparée :** workflow manuel `.github/workflows/repair-aud-07-migration-history.yml`, limité au projet `dzhhsoikzxibmngjzcch` et au seul numéro `20261104020500`. Il exige un texte de confirmation exact, la CLI Supabase 2.122.1 et les secrets GitHub `SUPABASE_ACCESS_TOKEN` + `SUPABASE_DB_PASSWORD`. Le workflow exécute la commande officielle `supabase migration repair 20261104020500 --status applied`, sans rejouer le SQL de la migration, puis liste l'historique.

**Limite actuelle :** le workflow est commité mais pas encore lancé ; les secrets GitHub ne sont pas accessibles à l'agent et aucune insertion manuelle dans `supabase_migrations.schema_migrations` n'a été effectuée. La divergence 333/332 reste donc présente. Après exécution, le total attendu est 333 local et 333 distant.

Runbook : `docs/runbooks/aud-07-reconcile-toy-weapon-migration-history.md`.

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

#### AUD-10 — Cinq verticales consultables n'avaient pas de parcours d'action complet
**État : AUD-10.1 Créatifs et AUD-10.2 Immobilier — backend sécurisé et intégration Flutter ajoutés ; Professionnels, Agriculture et Santé restent à traiter. Les essais de bout en bout restent ouverts.**

##### AUD-10.1 — Créatifs

- Migrations Supabase : \`20261106235154_secure_creative_booking_workflow\`, \`20261106235226_fix_creative_booking_decision_normalization\` et \`20261106235601_minimize_creative_booking_provider_payload\`.
- Retrait des écritures directes client sur \`creative_bookings\` ; lecture limitée au client ; maintien de \`active_account_guard\` en RESTRICTIVE.
- RPC pour demander, annuler une demande en attente, lister les demandes des services détenus par le prestataire, confirmer avec montant ou refuser.
- Les RPC vérifient session, compte actif, propriété et transition ; aucun EXECUTE anon ; le fournisseur ne reçoit pas l'UUID du client.
- Interface Flutter raccordée : demande, liste client, annulation, liste prestataire, acceptation avec montant ou refus.
- L'embedding public \`service_providers(display_name)\` a été retiré de la requête du catalogue créatif car anon n'a pas le droit de lire cette table.
- 11 contrôles SQL live équivalents aux assertions pgTAP sont vrais. Les quatre fonctions ont franchi le garde d'authentification sans session ; les opérations n'ont pas créé de données de test.

##### AUD-10.2 — Immobilier

- Migration appliquée : \`20261106235956_secure_real_estate_visit_request_workflow\`.
- Ajout de \`real_estate_visit_requests\` avec demandeur, annonce, message, date/heure souhaitée facultative, statut et horodatages ; une seule demande \`REQUESTED\` par demandeur et annonce.
- RLS activée ; aucun privilège direct Data API pour \`anon\` et \`authenticated\` ; les RPC authentifiées sont les seuls points d'entrée client.
- Cinq RPC : création, annulation client, liste client, liste propriétaire, acceptation/refus propriétaire.
- Contrôles serveur : compte actif, annonce active et vérifiée, prestataire actif et vérifié, identité du propriétaire depuis la relation \`service_providers.user_id\`, état de transition, date dans les 180 jours et message de 1 000 caractères maximum.
- Migration complémentaire `20261107000545_lock_real_estate_listing_state_during_request_transitions` : verrouillage `FOR SHARE` des lignes annonce/prestataire à la création et `FOR UPDATE` lors de la décision, pour prévenir les courses avec leur désactivation ou leur changement de vérification.
- Le résultat propriétaire n'expose pas l'UUID du demandeur. Une personne ne peut pas demander une visite de sa propre annonce.
- Flutter raccordé : bouton \`Visiter / contacter\`, demande facultative avec préférence de date et message, écran des demandes client, annulation, boîte de réception propriétaire et décision accepter/refuser.
- 12 contrôles directs de structure/droits/RPC sont prévus dans pgTAP ; ils n'ont pas été exécutés car l'extension pgTAP n'est pas installée. Des vérifications SQL live et des appels contrôlés sans session ont réussi.
- Le conseiller Supabase ajoute cinq éléments à sa catégorie générique SECURITY DEFINER pour les cinq RPC authentifiées. C'est voulu et documenté : elles ne sont pas exécutables par anon ou PUBLIC et valident identité/compte/propriété.
- Une acceptation signifie que le propriétaire accepte la demande, pas qu'un créneau est garanti. Pas encore de chat lié, coordonnées téléphoniques, agenda avec conflits, notifications, paiement, ni tests de compilation Flutter.

##### AUD-10 — Travaux restants et limites de validation

- Professionnels, Agriculture et Santé n'ont toujours pas de workflow complet raccordé.
- Les flux créatifs et immobiliers n'ont pas encore été testés avec de vrais comptes distincts, ni par tests Flutter, analyseur, build mobile ou test automatisé hébergé.
- Les fichiers pgTAP sont versionnés mais l'extension n'est pas installée sur la base distante ; les assertions n'ont donc pas été exécutées.
- Les devis, communications, notifications, scénarios de disponibilité et conflits de créneaux, paiements et journaux complets de transition restent à spécifier.

Runbooks : \`docs/runbooks/aud-10-creative-bookings-security.md\` et \`docs/runbooks/aud-10-2-real-estate-visit-requests-security.md\`.

#### AUD-11 — Les routes protégées ne contrôlaient pas la session ou le rôle
**État : gardes Flutter ajoutés sur main ; parcours administrateur/modérateur séparé ; tests unitaires écrits mais non exécutés.**

Le routeur précédent n'avait ni `redirect` ni `refreshListenable` lié aux changements d'authentification. Les routes privées étaient affichables sans vérification préalable.

**Corrections ajoutées :**
- `GoRouter` écoute maintenant les événements d'authentification Supabase et réévalue les redirections. Le routeur et l'écouteur sont libérés ensemble à la destruction du provider.
- Les routes panier, checkout, commandes, suivi livraison, favoris, achats groupés, messages, notifications, admin, vendeur et coursier exigent une session.
- Les profils doivent avoir le statut `ACTIVE`. Les comptes `SUSPENDED` ou `BLOCKED` sont orientés vers une page d'accès restreint.
- Les routes d'administration générales exigent un enregistrement `admin_users.active=true`, cohérent avec `private.is_admin()`.
- Exception de moindre privilège : un utilisateur portant uniquement `MODERATOR` peut accéder à `/admin/catalog-moderation` et `/admin/reviews`, mais pas au tableau de bord global, aux comptes, remboursements, paramètres ou réparations plateforme. Les autres routes admin exigent toujours `admin_users.active=true`.
- Les routes `/seller/*` exigent le rôle `SELLER` et un profil réel dans `public.sellers`. Les profils vendeur en attente peuvent encore accéder à leur espace pour suivre leur validation ; les mutations restent contrôlées par les RPC.
- `/courier` exige le rôle `COURIER`, en accord avec les fonctions SQL de colis.
- Les erreurs de lecture de rôle/status provoquent un refus par défaut. Les destinations de retour à la connexion sont filtrées pour ne permettre que les routes internes sûres.

**Tests ajoutés :** 10 tests unitaires couvrent les groupes de routes, les familles admin/vendeur/coursier, le périmètre modérateur et les redirections internes. Aucun n'a encore été exécuté car GitHub Actions n'a pas attribué de runner dans les dernières exécutions ; aucune validation Flutter locale n'est disponible ici.

**Frontière serveur :** les guards Flutter ne remplacent pas RLS/RPC. Les opérations de plateforme sont maintenant restreintes côté base à `private.is_admin()`. Les RPC vendeur/coursier continuent à vérifier compte actif, rôle et propriété côté serveur.

#### AUD-12 — Le rôle MODERATOR héritait de contrôles administrateur trop larges
**État : séparation modérateur/administrateur renforcée ; hiérarchie fine entre administrateurs encore à définir.**

Le helper `public.is_admin_actor()` reconnaît les rôles actifs `ADMIN`, `SUPER_ADMIN` et `MODERATOR`. Il est utilisé par les actions de modération du catalogue/avis, mais aussi par certaines fonctions d'administration générale. Un modérateur pouvait donc auparavant appeler des opérations globales qu'il n'a pas besoin d'exécuter.

**Correction appliquée sur Supabase :** migration `20261106204520_restrict_platform_admin_actions_to_registered_admins.sql`.

Les actions suivantes exigent maintenant `private.is_admin()`, qui vérifie l'existence d'un enregistrement actif dans `public.admin_users` et un profil `ACTIVE` :
- `get_admin_dashboard()` : métriques globales des utilisateurs, commandes, vendeurs et support ;
- `private.admin_run_safe_platform_repairs()`, `private.get_platform_health()`, `private.get_platform_repair_audit()`, `private.rollback_platform_repair()` ;
- `private.admin_get_return_policy_settings()` et `private.admin_set_return_window()` ;
- les triggers `enforce_profile_security_fields()` et `enforce_seller_document_review_fields()`, empêchant un modérateur de modifier le statut/vérification de son propre profil ou les métadonnées de validation de documents vendeur.

**Les modérateurs conservent** les fonctions de file et décision de modération du catalogue et des avis qui contrôlent explicitement `public.is_admin_actor()`. Le routeur Flutter a été adapté en conséquence : rôle `MODERATOR` autorisé uniquement sur les écrans catalogue/avis ; les autres écrans admin restent réservés aux lignes actives de `admin_users`.

**Vérification SQL après migration :** toutes les fonctions sensibles listées utilisent maintenant `private.is_admin()` et ne référencent plus `public.is_admin_actor()`. Les fonctions `private.admin_decide_catalog_finding` et `private.admin_decide_review` conservent leur garde `public.is_admin_actor()`. Les droits EXECUTE aux rôles clients restent inchangés, sans accès anon. Aucun utilisateur ou rôle n'a été créé dans la base hébergée.

**Risque restant :** `admin_roles` et `admin_users.admin_role_id` existent, mais le champ `admin_role_id` n'est toujours pas utilisé par les fonctions d'autorisation. Tous les administrateurs enregistrés dans `admin_users` disposent encore des mêmes permissions générales. La matrice propriétaire / SUPER_ADMIN / opérations financières / logistique / support doit être définie et appliquée avant d'ajouter des associés ou autres administrateurs. Le compte propriétaire initial reste non provisionné selon la consigne du projet.

**Tests :** deux assertions pgTAP supplémentaires vérifient l'usage de `private.is_admin()` pour les opérations globales et le maintien des autorisations de modération. Le fichier `security_regression_test.sql` contient 50 assertions ; les deux fichiers pgTAP totalisent 63 assertions prévues. Elles ne sont pas exécutées à cause de l'indisponibilité actuelle du runner CI.

#### AUD-13 — Le cycle de déconnexion et de désactivation des tokens n'était pas intégré
**État : parcours centralisé ajouté ; RPC serveur durcie et vérifiée ; tests runtime encore requis. Lié à Linear RIA-26.**

Avant correction, `PushNotificationService.signOutAndDeactivateCurrentDevice()` existait mais aucune interface ne l'appelait. Les utilisateurs pouvaient donc fermer une session sans désactiver le token FCM.

**Corrections ajoutées :**
- Nouveau composant réutilisable `AccountSessionActionButton` ajouté à l'accueil, aux tableaux de bord vendeur, administrateur et livreur.
- L'écran de compte suspendu/bloqué utilise aussi le même service de déconnexion sécurisée.
- Les appels directs `auth.signOut()` ont été retirés des écrans ; l'appel n'est désormais présent que dans `PushNotificationService`.
- Avant la déconnexion, le service utilise le token en cache ou récupère le token courant Firebase lorsque le service est initialisé. Il attend la réponse serveur et exige le booléen `true` avant de vider le cache et de signer l'utilisateur.
- Si Firebase est initialisé mais que la récupération du token échoue, la déconnexion est interrompue afin de permettre une nouvelle tentative. Si aucun token n'est disponible, la déconnexion peut se poursuivre sans appel RPC.
- Migration Supabase `20261106203915_secure_notification_device_deactivation_for_blocked_accounts.sql` : la RPC devient `SECURITY DEFINER`, vérifie `auth.uid()`, ne modifie que le token appartenant à cet utilisateur, valide le token et retourne vrai seulement lorsqu'aucune ligne active correspondante ne subsiste.
- Le privilège EXECUTE reste absent de `anon` et disponible à `authenticated` / `service_role`. La RPC peut maintenant désactiver le token d'un utilisateur suspendu/bloqué, car elle doit être utilisable pour quitter sa session même si le guard RLS ordinaire est fermé. Elle ne peut toujours pas désactiver le token d'un autre utilisateur.
- Une assertion pgTAP supplémentaire vérifie `SECURITY DEFINER`, l'identité utilisateur, le périmètre du token, l'idempotence et l'absence d'exigence `require_active_account()`. Le fichier `security_regression_test.sql` contient maintenant 48 assertions ; elles restent à exécuter.

**Limites :** aucun compte ou token réel n'existe encore sur le projet pour tester le cycle complet. La réception effective des push et l'absence de push après déconnexion doivent être testées sur un appareil Android/iOS avec Firebase configuré. Les tests Flutter/pgTAP n'ont pas été exécutés, GitHub Actions n'ayant pas encore démarré un runner.

#### AUD-14 — Le suivi GPS livreur en arrière-plan
**État : flux continu Flutter et permissions natives ajoutés ; garde serveur sur affectation active ; test widget ajouté ; validation appareil/store et rétention encore requises.**

L'ancien code utilisait un `Timer.periodic(15s)` attaché à la page coursier : il n'offrait aucune garantie quand le système suspendait l'application.

**Corrections ajoutées :**
- `DeviceLocationService.positionStream()` utilise maintenant le flux continu `Geolocator.getPositionStream()`, pas de minuteur Flutter. Android vise 15 secondes et 25 m ; la précision et le rythme réel restent soumis au GPS, au système et à l'économie d'énergie.
- Activation volontaire depuis l'espace livreur, après écran d'explication du partage en arrière-plan et vérification qu'une mission est affectée.
- Android utilise `AndroidSettings` avec un service de premier plan et une notification persistante `Suivi de livraison actif`. Le manifeste déclare `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`.
- iOS utilise `AppleSettings.allowBackgroundLocationUpdates=true`, sans pause automatique et avec indicateur système. `Info.plist` contient les descriptions WhenInUse/Always et le mode `UIBackgroundModes/location`.
- Le livreur doit autoriser « Toujours / Autoriser tout le temps » pour que le flux puisse continuer en arrière-plan. La page permet d'arrêter explicitement le partage.
- Le flux s'arrête quand toutes les missions sont terminées/annulées, lorsqu'il n'existe plus d'affectation, si le serveur refuse la position faute de mission active, à la demande du livreur ou à la destruction de la page/déconnexion.
- Supabase migration `20261106205236_require_active_courier_assignment_for_location_updates.sql` : `record_courier_location` exige maintenant une affectation active associée à un colis/commande non terminés. Sans mission, aucun enregistrement GPS n'est permis ; les gardes COURIER/compte actif, validation des coordonnées, search_path PostGIS et ACL sont conservés.
- Un test Flutter vérifie que l'application ne propose pas le partage GPS quand le livreur n'a aucune mission. Une assertion pgTAP supplémentaire couvre la garde serveur. Le fichier `security_regression_test.sql` comporte 51 assertions ; total prévu 64 avec l'autre fichier.

**Limites importantes :**
- Aucun build Android/iOS, test sur appareil physique ou test en arrière-plan n'a été exécuté ici ; les tests pgTAP/Flutter restent non exécutés faute de runner GitHub opérationnel.
- Google Play / App Store peuvent exiger des explications/contrôles supplémentaires pour la localisation permanente ; les permissions natives ne garantissent pas l'approbation.
- Aucune tâche de purge des anciennes positions n'a été trouvée. La durée de conservation n'a pas été fixée arbitrairement. Le suivi RIA-31 demande de définir la durée, les finalités et la purge serveur avant mise en production.

Runbook : `docs/runbooks/aud-14-courier-background-location.md`. Suivi livraison/GPS : https://linear.app/faso/issue/RIA-11/07-livraison-et-gps. Conservation GPS : https://linear.app/faso/issue/RIA-31/confidentialite-definir-la-conservation-et-la-purge-des-positions-gps.

#### AUD-15 — Dérive entre sources Edge Functions et déploiements Supabase
**État : source parity restaurée ; trois fonctions déployées et relues ; CI Deno non confirmé.**

Au départ, Supabase exposait 21 fonctions et le dépôt ne contenait que 18 dossiers sources. Les trois absentes étaient `expire-products` v2, `admin-health-check` v2 et `payment-webhook-gateway` v3.

**Corrections appliquées :**
- Sources de `expire-products` et `admin-health-check` restaurées dans GitHub. Les deux exigences `admin_users.active=true` et `profiles.status='ACTIVE'` sont maintenant vérifiées côté fonction, avec refus par défaut si une lecture d'autorisation échoue.
- Code tombstone de `payment-webhook-gateway` versionné ; la fonction reste explicitement retirée, HTTP 410 `legacy_endpoint_retired`, sans logique de paiement.
- Les trois fonctions ont été redéployées et relues depuis Supabase :
  - `expire-products` v3, `verify_jwt=true`, contrôles admin + profil ACTIVE confirmés ;
  - `admin-health-check` v3, `verify_jwt=true`, contrôles admin + profil ACTIVE confirmés ;
  - `payment-webhook-gateway` v4, `verify_jwt=false`, HTTP 410 confirmé.
- Le projet expose maintenant 22 fonctions et GitHub contient 22 dossiers sources correspondants : parité 22/22. La fonction `check-payment-provider-config` v1, `verify_jwt=true`, a été ajoutée pour le précontrôle paiement client. Aucun endpoint n'a été supprimé ou désactivé.
- Aucun secret n'a été lu ou ajouté à GitHub ; aucun paiement ni produit réel n'a été modifié.

**Limite CI :** le workflow Edge Functions a échoué sans enregistrer d'étapes ou journaux récupérables. Les sources déployées ont été relues, mais `deno check` n'est donc pas confirmé. Le test Deno doit être relancé quand GitHub Actions attribuera un runner.

Runbook : `docs/runbooks/aud-15-edge-function-source-parity.md`.

#### AUD-16 — Le moniteur Storage ne couvrait initialement que deux buckets sur cinq
**État : correction de surveillance appliquée et testée ; flux d'accès aux objets encore à valider.**

Le contrôle initial ne vérifiait que `order-feedback-media` et `product-media`. La fonction `platform-health-monitor` v7 vérifie maintenant les cinq buckets réels : `avatars`, `documents`, `order-feedback-media`, `product-media` et `shop-media`.

Le contrôle manuel du 6 novembre 2026 à 20:19:02 UTC a renvoyé HTTP 200 et les cinq buckets ont répondu `UP` avec HTTP 200.

**Limite :** ce probe confirme que le bucket existe et répond au point d'accès Storage privilégié ; il ne démontre pas un upload, un téléchargement, une URL signée, ni l'application des règles RLS/Storage par rôle. Les tests de fichiers factices et les accès positifs/négatifs pour client, vendeur et administrateur restent requis. Les buckets `documents`, `shop-media`, `product-media` et `order-feedback-media` sont privés ; `avatars` est public selon sa configuration actuelle.

#### AUD-17 — Couverture des tests métier insuffisante
**État : couverture structurelle renforcée ; exécution CI et scénarios end-to-end toujours bloquants.**

Inventaire actuel :
- 8 fichiers de tests Dart : authentification/récupération email, précontrôle de configuration paiement, routage/guards, bouton de session, refus de GPS sans mission, routage des notifications, démarrage app et configuration des verticales.
- 3 fichiers SQL pgTAP : comptes de démo locaux (13 assertions), contrats checkout/commande/livraison/remboursement (13 assertions) et sécurité/RLS/RPC (56 assertions), soit 82 assertions prévues.
- Les 13 nouvelles conditions du fichier `order_delivery_contract_test.sql` ont été évaluées en lecture seule sur les fonctions SQL et ACL réellement déployées : 13/13 sont vraies.

**Tests de contrat ajoutés :** annulation uniquement des commandes impayées, refus des commandes déjà payées/expédiées, libération du stock et des coupons, synchronisation commandes/colis/affectations, garde de propriété vendeur, idempotence checkout et adresse appartenant au client, calcul des frais côté serveur, vérification expiration/stock, acceptation d'affectation coursier, preuve photo/code de retrait, progression de livraison et preuve/code de livraison, accès service-role-only à `complete_refund`.

**Limite :** l'évaluation SQL précédente est une vérification de prédicats en lecture seule sur les fonctions actives ; elle ne signifie pas que le script pgTAP a été exécuté. Aucun test Flutter, pgTAP, Edge/Deno, scénario paiement fournisseur, scénario multi-vendeur réel, transport, mécanicien ou test appareil GPS n'a encore terminé avec un résultat CI lisible. Les derniers jobs GitHub Actions s'arrêtent sans étapes ou logs récupérables.

**Correction restante :** exécuter les trois suites pgTAP sur la base locale reconstruite par `supabase db reset`, puis `supabase test db`; exécuter `flutter analyze` et `flutter test` ; ajouter de vrais scénarios d'intégration pour webhooks avec fournisseurs simulés, allocations partielles, retours multi-boutiques, courses, réservations et accès croisés ; exécuter les tests Android/iOS. Ne pas utiliser de paiement réel ou données de production pour ces tests.

Suivi : Linear RIA-27 — https://linear.app/faso/issue/RIA-27/qualite-production-construire-une-validation-des-parcours.

#### AUD-18 — Capacité, sauvegardes et restauration
**État : premier relevé disponible ; 1 000–10 000 utilisateurs et reprise après incident non certifiés.**

Snapshot du projet Supabase en lecture seule :
- PostgreSQL 17.6.1, projet `ACTIVE_HEALTHY`, base d'environ 80 MB.
- `max_connections = 60`, 3 connexions réservées ; 11 connexions clients observées au moment de la capture.
- Logs PgBouncer sur les dernières 24 h : 0 « max client connections reached », 0 « client login timeout », 0 « no more connections allowed », 0 « server login retry ». Les 71 expirations observées étaient des connexions serveur fermées pour inactivité.
- Aucun deadlock, slot de réplication ou connexion de réplication observé.
- `pg_stat_archiver` : 33 222 WAL archivés, 0 échec, dernier archivage le 6 novembre 2026 à 21:25:50 UTC. Cet indicateur ne prouve pas que la sauvegarde quotidienne ou PITR est activée et restaurable.
- Données métier quasiment absentes : 0 compte/profil, 0 produit, 0 objet Storage ; environ 80 MB de base, principalement SRID et tables de diagnostic.

**Conclusion de capacité :** la saturation n'est pas visible dans ce snapshot ou dans les logs 24 h, mais cela ne démontre pas une capacité de 1 000 à 10 000 utilisateurs. Le nombre de connexions Postgres n'est pas équivalent au nombre d'utilisateurs ; le compute exact et le plafond client du pooler doivent être vérifiés dans les paramètres Supabase. Les plafonds officiels du pooler varient de 200 clients sur Nano/Micro à 12 000 sur 16XL ; la pool size et le budget doivent être mesurés et approuvés avant une montée en charge. Voir https://supabase.com/docs/guides/platform/compute-and-disk et https://supabase.com/docs/guides/database/connection-management.

**Script préparé :** `tests/load/k6_readonly_supabase_categories.js` simule un profil de lecture uniquement, refuse le ref production, exige `TARGET_ENV=staging` et prépare des paliers 100 → 1 000 → 10 000 VUs. Il n'a pas été exécuté ; aucun trafic de charge n'a été généré.

**Backups / reprise :** la liste des backups et les points de restauration ne sont pas exposés par les outils connectés. Le plan Supabase exact du projet reste à confirmer dans Dashboard > Billing. Supabase indique que les projets Pro/Team/Enterprise reçoivent des backups quotidiens (rétention Pro 7j, Team 14j, Enterprise jusqu'à 30j) ; le Free plan doit exporter les données avec la CLI et garder une copie hors site. Les backups DB n'incluent pas les objets Storage. Aucune restauration réelle n'a été faite. Source : https://supabase.com/docs/guides/platform/backups.

**Correction restante :** confirmer plan/compute/pooler, préparer un dataset staging réaliste, exécuter les paliers k6 et un test de restauration dans un projet isolé, sauvegarder séparément les binaires Storage et mesurer RPO/RTO. Linear RIA-32 suit ce travail. Aucun compute, plan, backup, pool size ou objet métier n'a été modifié.

Runbook : `docs/runbooks/aud-18-capacity-backup-restore.md`.

#### AUD-19 — Récupération de compte et OTP téléphone manquants
**État : récupération email ajoutée côté application ; callback et SMTP Supabase à configurer ; OTP téléphone non activé.**

Le formulaire de connexion propose toujours email/mot de passe et inscription email. Le parcours de récupération par email est maintenant ajouté :
- écran `Mot de passe oublié ?` relié à `resetPasswordForEmail()` ;
- email de récupération avec redirection `marketplaceburkina://auth/recovery` ;
- événement Supabase `AuthChangeEvent.passwordRecovery` écouté dès la fin de `Supabase.initialize()` ;
- écran de nouveau mot de passe qui reste verrouillé sans événement de récupération confirmé, vérifie deux saisies identiques, puis utilise `updateUser(UserAttributes(password: ...))` ;
- callback Android déclaré ; iOS réutilise le schéma personnalisé déjà présent ;
- 3 tests unitaires vérifient l'ouverture/fermeture du marqueur de récupération ; test de routes public couvrant les deux chemins de callback.

**Action manuelle nécessaire :** ajouter exactement `marketplaceburkina://auth/recovery` dans Supabase Dashboard > Authentication > URL Configuration > Redirect URLs, puis vérifier le modèle Email Templates > Reset Password et le SMTP. L'outil de connexion ne permet pas de lire ou modifier cette allow-list ; cette configuration n'est donc pas confirmée. Le SMTP Supabase intégré est limité et best-effort ; l'usage en production peut nécessiter un SMTP personnalisé. Aucun fournisseur payant n'a été activé.

**OTP téléphone :** non activé. Supabase Phone Auth nécessite un fournisseur SMS externe (Twilio, MessageBird, Vonage, etc.) et les SMS sont facturés selon le fournisseur/destination. Aucun secret ou fournisseur SMS n'a été configuré. Il faut décider du coût avant d'ajouter le flux de numéro +226. Le runbook documente cette décision.

**Tests/limites :** aucun email réel n'a été envoyé, aucun compte utilisateur n'existe en base et aucun test sur appareil Android/iOS n'a été effectué. Les tests Flutter/CI ne sont pas confirmés exécutés. Le reset email ne peut être déclaré prêt en production qu'après configuration Redirect URLs + SMTP et test d'un lien sur les deux plateformes.

Runbook : `docs/runbooks/aud-19-email-password-recovery.md`.

### P3 — Alertes d'information, pas des défauts à corriger en masse

#### AUD-20 — 366 index non uniques signalés inutilisés
**État : mesure PostgreSQL détaillée ; aucune suppression justifiée à ce stade.**

Supabase Performance Advisor remonte 366 index `unused_index` au niveau INFO (observés le 6 novembre à 21:40 UTC).

Lecture de `pg_stat_user_indexes` et `pg_index` :
- Stats reset : 25 août 2026 à 20:33 UTC.
- Schéma `public` : 571 index dont 559 sans scan.
- Schéma `private` : 44 index dont 39 sans scan.
- Total public/private sans scan : 598 ; parmi eux 232 index sont primaires ou uniques et ne doivent pas être considérés comme candidats à la suppression.
- Les 366 restants sont précisément les index non uniques/non primaires sans scan, même nombre que l'advisor.
- Taille des 366 index : 3 031 040 octets (~2,9 MiB). Taille totale des 598 index sans scan : 5 414 912 octets (~5,2 MiB).
- La plupart des tables métier contrôlées ont zéro ligne ; les tables produits, commandes, remboursements, avis, livreurs, messages, boutiques et demandes de service ne présentent pas encore de trafic représentatif.
- Dernier ANALYZE observé : 21 septembre 2026 ; dernier AUTOANALYZE : 6 novembre 2026.

Plusieurs index sans scan protègent des parcours critiques qui ne sont simplement pas utilisés avec des tables vides : historique commandes, produits par boutique/état, péremption, missions coursier, dernières positions GPS, colis, messages, paiements, commissions, payouts et remboursements. D'autres index uniques assurent l'idempotence checkout, les références fournisseurs, les slugs ou les noms de boutiques.

**Décision :** aucun index supprimé et aucune migration destructive préparée. Le coût mémoire actuel des 366 index candidats est inférieur à 3 MiB, alors qu'une suppression prématurée peut rendre les premiers parcours métier lents ou dégrader l'intégrité. Refaire la mesure après un jeu de données staging représentatif et trafic réel, étudier les plans EXPLAIN/BUFFERS et les contraintes avant toute décision.

Runbook : `docs/runbooks/aud-20-unused-index-review.md`.

#### AUD-21 — 17 tables RLS sans policy
**État : vérifié ; état intentionnel et verrouillé en régression.**

Le relevé Supabase confirme 17 tables RLS activées sans policy :
- 15 tables `private` de diagnostics, audit, modération, réparations plateforme, règles de retour et délégations vendeurs ; leur ACL est limitée à `postgres`.
- 2 tables publiques de médias (`delivery_evidence`, `review_media`) ; leur ACL permet le rôle serveur `service_role`, mais pas `anon` ni `authenticated`.

Vérification live avec `has_table_privilege` sur SELECT/INSERT/UPDATE/DELETE :
- tables présentes : 17/17 ;
- privilège direct anon : 0/17 ;
- privilège direct authenticated : 0/17.

Les fonctions métier utilisent des chemins contrôlés :
- lecture des médias d'avis publics via `private.get_public_review_media(uuid)` SECURITY DEFINER, qui ne retourne que les avis `PUBLISHED`, appelé par la fonction publique autorisée en lecture anonyme ;
- lecture des preuves de livraison via `private.get_customer_delivery_evidence(uuid)` SECURITY DEFINER, qui exige un compte actif et vérifie `orders.customer_id = auth.uid()`, appelé par une RPC authentifiée ;
- pièces jointes créées via des RPC qui valident identité, chemin Storage, propriété, état métier et type de preuve.

**Décision :** ne pas ajouter de policies permissives ni de privilèges table directs pour effacer cet avertissement. L'absence de policy entraîne le refus d'accès direct et protège ces tables internes. Si une nouvelle lecture métier est nécessaire, ajouter une RPC limitée et des tests négatifs, pas une policy générique.

Deux assertions pgTAP supplémentaires sont ajoutées à `security_regression_test.sql` : accès direct refusé sur les 17 tables et accès média limité aux fonctions publiées/propriétaires. Le plan de ce fichier passe à 53 assertions ; le total des trois suites est maintenant 79. Les tests pgTAP restent à exécuter par CI.

Runbook : `docs/runbooks/aud-21-rls-no-policy-tables.md`.

#### AUD-22 — Revue des fonctions SECURITY DEFINER et de leurs search_path
**État : 163 fonctions applicatives contrôlées ; 14 chemins renforcés ; trois fonctions natives PostGIS restent gérées par Supabase.**

Inventaire du catalogue PostgreSQL :
- 166 fonctions SECURITY DEFINER dans `public` et `private` ;
- 163 fonctions applicatives détenues par `postgres` et trois fonctions natives PostGIS C détenues par `supabase_admin` ;
- 107 fonctions exécutables par `authenticated`, six par `anon` ;
- les 163 fonctions applicatives ont désormais toutes un `search_path` explicite ; 48 utilisent le chemin vide (protection forte avec qualification des objets) ;
- 14 fonctions applicatives ont explicitement `pg_temp` en dernier ;
- les seules trois fonctions sans search_path restent les trois surcharges natives `public.st_estimatedextent`, gérées par `supabase_admin`.

**Fonctions accessibles à anon :** deux helpers média ne retournent que les médias d'avis `PUBLISHED` ; `private.is_admin()` vérifie `auth.uid()`, `admin_users.active=true` et profil `ACTIVE` et renvoie faux en absence d'utilisateur ; les trois autres fonctions anon sont les fonctions C PostGIS. Aucune révocation globale n'est justifiée.

**Corrections appliquées par migrations :**
- `20261106220518_harden_security_definer_search_paths` a durci 12 RPC applicatives et `handle_new_user()` : `pg_catalog` en premier, schémas métiers nécessaires au centre, `pg_temp` en dernier.
- `20261106220850_harden_payment_provider_event_search_path` a protégé la résolution du type `payment_status` dans `process_payment_provider_event()`, tout en conservant son exécution service-role-only.
- Les fonctions restent détenues par `postgres` ; leur corps, propriétaire, droits EXECUTE et logique métier sont inchangés.

**Contrôles post-migration :**
- 13/13 signatures de la première migration présentes et avec le chemin exact ; aucun EXECUTE anon sur les 12 RPC ; `handle_new_user` reste réservé au serveur.
- `process_payment_provider_event` conserve le chemin attendu, aucun EXECUTE anon/authenticated, EXECUTE service_role uniquement.
- Aucun ancien chemin `public` ou `public, private` non protégé ne subsiste dans le lot examiné.
- Un scan ciblé des fonctions applicatives restantes avec chemin non vide n'a trouvé aucune référence non qualifiée à une relation existante ; trois types personnalisés réellement non qualifiés ont été corrigés.
- Les trois fonctions PostGIS C restent sans chemin et appartiennent à `supabase_admin` : ne pas les modifier avec le rôle du projet ; elles restent suivies dans AUD-01.

Trois assertions pgTAP supplémentaires protègent les 14 chemins et ACL. `security_regression_test.sql` compte maintenant 56 assertions ; total des trois suites : 82 prévues. Les prédicats ont été évalués en lecture seule sur la base live et sont vrais, mais la suite pgTAP complète n'a pas été exécutée par CI.

Runbook : `docs/runbooks/aud-22-security-definer-search-path-review.md`.

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
9. AUD-10 — terminer les verticales immobilier, professionnels, agriculture et santé ; compléter les parcours créatifs avancés et les tests. AUD-19 — terminer la récupération de compte en production.

## 5. Limites de l'audit

Cet audit combine inspection de fichiers, recherches ciblées, lecture de fonctions SQL actives, privilèges, historique des migrations, listes de fonctions et journaux. Il ne constitue pas un audit ligne par ligne certifié de chaque fichier ni un pentest externe. Les SDK Flutter/Dart/Deno n'ont pas été exécutés depuis cet environnement ; les dernières exécutions GitHub consultées n'ont pas démarré de runner. Aucun paiement, push, GPS en arrière-plan, scénario multi-utilisateur, charge, sauvegarde ou restauration réelle n'a été effectué.

Le registre doit être mis à jour après chaque correction avec : référence du commit, migration éventuelle, tests exécutés, résultat CI et preuve de non-régression.
