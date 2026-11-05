# Phase 80 — expansion métier, sécurité et validation

## Ajouts

- 16 verticales métier maintenant exposées par des routes réelles : mobilité, location de véhicules, immobilier, hébergement, événements, emplois, professionnels, agriculture, fret, santé, beauté, services à domicile, numérique, formations, créatifs et colis.
- création sécurisée des demandes de trajet, fret et colis;
- réservations sécurisées pour événements, véhicules et hébergements;
- candidatures emploi et inscriptions formation;
- commandes de services numériques;
- rendez-vous beauté et demandes à domicile;
- suivi colis par code de tracking avec historique limité aux données logistiques nécessaires;
- affichage de la position du livreur sur carte avec attribution OpenStreetMap;
- gestion vendeur : boutique, profil, coupons, promotions, clients, avis, statistiques, finance;
- gestion administrateur : comptes, blocage/réactivation et activation d’associés après paiement vérifié;
- détail de commande avec retours, litiges, avis et accès au suivi livraison;
- tests de cohérence de configuration des verticales.

## Durcissement Supabase

Les mutations sensibles de commandes, avis, retours, litiges, coupons, promotions, boutique, profil vendeur, fret, colis et modules passent par des RPC qui vérifient le propriétaire ou le rôle.

Les données des acheteurs ne sont pas exposées au tableau de bord vendeur. Le suivi d’un colis ne renvoie pas les coordonnées personnelles du destinataire.

Les politiques SELECT dupliquées sur les surfaces concernées ont été regroupées afin de réduire les évaluations RLS inutiles.

## Vérification

La CI GitHub est utilisée pour flutter analyze et flutter test. Plusieurs anciens runs ont échoué sur des erreurs intermédiaires qui ont ensuite été corrigées. Le run associé au dernier commit doit être considéré comme la référence finale lorsqu’il est terminé.

Le SDK Flutter n’est pas installé dans l’environnement de travail courant, donc aucune analyse locale n’est déclarée comme réussie.

## Points production encore distincts

Les plateformes natives Android/iOS doivent être générées/configurées pour les permissions de localisation.

Les intégrations Orange Money, Wave et Moov Money nécessitent les comptes marchands, secrets et webhooks réels. L’application ne simule pas ces accès.

PostGIS reste dans le schéma public car l’extension est non-relocatable. L’avertissement spatial_ref_sys et l’exposition des fonctions st_estimatedextent restent à traiter avec une migration d’extension contrôlée, sans casser la géolocalisation.

## Audit complémentaire — 5 novembre 2026

### Parcours principaux — étape 2

Inspection du code Flutter et des fonctions SQL :
- le panier utilise des RPC pour ajouter et modifier les quantités ;
- le checkout utilise une clé d'idempotence, recalcule les prix depuis le catalogue, contrôle le propriétaire du panier et réserve le stock côté serveur ;
- les réservations de transport verrouillent le trajet et contrôlent la capacité ;
- l'acceptation d'un devis mécanicien verrouille la demande et rejette les autres devis en attente ;
- les règles RLS des demandes de mécanicien et des billets transport limitent la lecture au client concerné.

Limite : l'inspection du code et des migrations n'est pas un test de bout en bout. La suite actuelle contient encore trop peu de tests d'intégration pour certifier tous les parcours acheteur, vendeur, restaurant, coursier et prestataire.

### SaaS multi-boutiques — architecture manquante identifiée

Le modèle actuel autorise déjà plusieurs boutiques par profil vendeur (shops.seller_id n'est pas unique). Le partage d'accès par boutique existe également via private.seller_access_requests, des périmètres approuvés, des dates d'expiration, une conversation administrative et un journal d'audit.

En revanche, aucun modèle complet d'abonnement et de quotas commerciaux n'a été trouvé dans le schéma inspecté. Les éléments suivants restent à construire :

1. Catalogue de plans vendeurs, avec prix XOF, périodicité et fonctionnalités incluses.
2. Abonnement au niveau du compte vendeur, avec statut, période, renouvellement, suspension et résiliation.
3. Quota d'emplacements/boutiques achetés, et allocation explicite de chaque emplacement à une boutique.
4. Contrôle serveur des limites avant création ou réactivation d'une boutique. Le client ne doit jamais pouvoir augmenter lui-même son quota.
5. Historique immuable des événements d'abonnement et des paiements vérifiés.
6. Invitations par e-mail, y compris pour une personne qui ne possède pas encore de compte.
7. Membres par boutique avec permissions de lecture et d'action séparées, révocation immédiate et journal d'audit.

Le flux actuel de partage est plus limité : le destinataire doit déjà posséder un compte actif et les périmètres autorisés sont actuellement principalement des droits de lecture. Il ne doit pas être présenté comme un système complet d'employés/permissions.

#### Modèle cible proposé

- seller_plans : catalogue des offres géré par la plateforme.
- seller_subscriptions : abonnement du vendeur, période, état, quota acheté et référence de paiement.
- shop_subscription_allocations : association unique entre une boutique et un emplacement payé.
- shop_invitations : invitation ciblée par e-mail, rôle, permissions, expiration et état.
- shop_memberships : utilisateur actif, boutique, rôle et permissions accordées.
- subscription_events et shop_access_audit : historique serveur des changements.

Les tables de facturation et d'audit doivent être protégées par RLS et ne pas être directement modifiables par les clients. Les opérations d'achat, activation, allocation, suspension et révocation doivent passer par des RPC transactionnelles qui vérifient le paiement et l'identité de l'acteur. Un abonnement expiré ne doit pas supprimer les données ni les commandes existantes ; il doit empêcher les nouvelles opérations dépassant les droits payés.

Aucune table SaaS n'est ajoutée dans cette étape d'audit. Le schéma devra être créé par une migration versionnée, testée sur une base locale reconstruite avant toute application distante.

### Paiements — correctifs de code identifiés

- Les fonctions Wave et CinetPay v3 construisaient leurs URL de retour en utilisant orderId avant sa déclaration. Le code a été corrigé pour valider et lire la commande avant de construire les URL.
- La création de session CinetPay v3 pointait vers l'ancien endpoint de webhook. Elle pointe maintenant vers cinetpay-webhook-v3, qui vérifie la notification et confirme la transaction auprès de CinetPay.
- Une branche GET de santé du webhook CinetPay v3 dupliquée a été supprimée.

Ces modifications sont enregistrées dans GitHub. Elles restent à valider par une compilation/typecheck Deno et par des tests de webhook simulés. Aucun paiement réel n'a été déclenché.

### Validation native et sécurité

Les compilations Android/iOS précédemment réussies ne prouvent pas que les notifications push fonctionnent sur des appareils réels. Firebase/APNs et le secret FCM restent nécessaires.

Les tests de charge, les tests de restauration de sauvegarde et les essais de paiement réel restent hors du périmètre de la CI actuelle. Aucune capacité de 1 000 à 10 000 connexions simultanées n'est certifiée.

### Correctif checkout — 5 novembre 2026

- Le sélecteur d'adresse pouvait recevoir plusieurs demandes de devis de livraison en parallèle. Une réponse lente correspondant à l'ancienne adresse pouvait arriver après la réponse de la nouvelle adresse et remplacer son devis à l'écran.
- Le checkout utilise maintenant un identifiant de requête croissant et ignore les réponses et erreurs qui ne correspondent plus à l'adresse sélectionnée.
- Le calcul définitif du prix reste côté serveur dans `checkout_cart` ; ce correctif empêche surtout l'affichage d'un devis obsolète et une confusion de l'utilisateur.
- Le correctif est enregistré dans le commit `df541451734c7b34456d508883bff6bf2db745a8`.
- La compilation/analyse Flutter n'a pas pu démarrer dans GitHub Actions : le job s'arrête en environ trois secondes, avec `runner_id=0`, aucun runner attribué et aucune étape exécutée. Ce résultat ne permet pas de conclure sur la compilation du correctif.

### Diagnostic GitHub Actions — 5 novembre 2026

- Les workflows Flutter, Supabase DB et Android ont de nouveau échoué avant l'exécution de la première étape.
- Les objets Job retournés par GitHub indiquent `runner_id=0`, `runner_name` vide et `steps=[]`. Les logs du job ne sont pas disponibles via l'API (404 BlobNotFound).
- Le problème est donc actuellement situé au démarrage/à l'attribution du runner, et non dans une erreur de test démontrée. La cause administrative exacte (limites de facturation, disponibilité ou politique Actions) reste à confirmer dans les paramètres GitHub du dépôt/compte.
- Le workflow Flutter a été réduit aux permissions `contents: read` et ne tente plus de pousser automatiquement un lockfile depuis la CI.
- Aucun résultat de test n'est déclaré réussi sur les commits récents tant que les jobs n'ont pas réellement exécuté leurs étapes.

### Finding sécurité — portée du partage financier inter-boutiques — 6 novembre 2026

- Relecture statique des migrations `20261103211236_enforce_approved_seller_access_scopes_in_rls.sql` et `20261103211258_limit_seller_access_requests_to_implemented_scopes.sql`.
- Le flux de demande autorisait le scope `financial_read`. Les politiques de lecture partagée de `commissions`, `seller_ledger` et `seller_payouts` recherchaient une boutique du vendeur ayant accordé ce scope, puis filtraient les lignes par `seller_id` seulement.
- Or un vendeur peut posséder plusieurs boutiques. Accorder `financial_read` sur une boutique pouvait donc rendre visibles au collaborateur des lignes financières du vendeur liées à ses autres boutiques.
- Risque : exposition inter-boutiques de données financières à un collaborateur qui n'a reçu l'accès qu'à une seule boutique. Il s'agit d'un défaut de granularité de l'autorisation, pas d'une preuve d'accès à des données d'un autre vendeur.
- La correction est décrite ci-dessous et a depuis été appliquée en production.

### Correction appliquée — isolation du partage financier — 6 novembre 2026

- Migration distante `20261105184635_disable_unsafe_shared_financial_reads` appliquée au projet Supabase actif.
- Suppression des trois politiques de partage dangereuses : `commissions_shared_access_read`, `seller_ledger_shared_access_read` et `seller_payouts_shared_access_read`.
- Vérification après application : les trois politiques ont disparu. Les politiques de lecture du propriétaire vendeur restent présentes pour les commissions et le registre ; la politique propriétaire/administrateur reste présente pour les paiements vendeur. Les garde-fous `active_account_guard` sont conservés.
- Le fichier SQL correspondant est versionné dans `supabase/migrations/20261105184635_disable_unsafe_shared_financial_reads.sql`.
- Effet attendu : un collaborateur ne peut plus obtenir les données financières via le partage de boutique. Le propriétaire vendeur et les administrateurs conservent leurs politiques de lecture existantes.
- État historique au moment de ce premier correctif : le scope `financial_read` était encore accepté par la fonction de demande. Cette limite a été résolue par la migration `20261105184743` décrite plus bas, qui retire ce scope des nouvelles demandes.
- Aucun solde, paiement, remboursement ou écriture du registre n'a été modifié. Aucun test avec de vrais fonds n'a été effectué.


### Retrait du scope financier des nouvelles demandes — 6 novembre 2026

- Migration distante `20261105184743_remove_financial_read_from_seller_access_requests` appliquée au projet Supabase actif.
- La RPC `submit_seller_access_request` n'accepte plus que `shop_profile`, `products`, `inventory_read` et `orders_read`. Une nouvelle demande contenant `financial_read` est rejetée.
- Le fichier SQL est versionné dans `supabase/migrations/20261105184743_remove_financial_read_from_seller_access_requests.sql`.
- Les demandes historiques peuvent encore contenir la valeur ancienne, mais les politiques de lecture financière partagée ont déjà été supprimées : ces anciennes autorisations ne donnent plus accès aux tables financières.
- Les migrations ont été appliquées et les fichiers SQL enregistrés. Les tests d'intégration automatisés n'ont pas encore pu être exécutés, car les runners GitHub Actions du dépôt ne s'attribuent pas (`runner_id=0`).


### Audit complémentaire — droits des RPC financières et stockage — 6 novembre 2026

Contrôles effectués en lecture seule sur le projet Supabase actif :

- `public.complete_refund(uuid,text)` et `public.process_payment_event(uuid,text,payment_status,text,numeric,jsonb)` sont des fonctions `SECURITY DEFINER` dont l'exécution est réservée à `service_role` et au propriétaire PostgreSQL. Les rôles `anon` et `authenticated` n'ont pas le droit EXECUTE.
- Les RPC administratives de paiement vendeur et de remboursement sont exécutables par `authenticated`, mais leurs corps vérifient le rôle administrateur avant toute mutation. Elles ne sont pas exécutables par `anon`.
- `request_seller_payout_secure` est exécutable par les utilisateurs authentifiés, pas par `anon`. La fonction vérifie que le vendeur appartient à l'utilisateur, est vérifié, verrouille la ligne vendeur avec `FOR UPDATE`, calcule le solde du registre, refuse un montant supérieur au solde puis inscrit le retrait et l'écriture négative dans la même transaction.
- Les opérations de finalisation de remboursement verrouillent la ligne de remboursement et le paiement. La fonction de traitement des événements de paiement verrouille le paiement et vérifie le montant et la devise avant de modifier l'état.
- Les buckets Storage `documents`, `order-feedback-media`, `product-media` et `shop-media` sont privés. Le bucket `avatars` est public, ce qui est cohérent avec des photos de profil destinées à être visibles. Les règles de lecture de documents vendeurs sont limitées au propriétaire du fichier ; aucune policy de lecture publique/anon du bucket `documents` n'a été trouvée.
- Les médias de retours/avis ont des policies de lecture distinctes pour l'administrateur, le client/livreur autorisé, le propriétaire et les avis publiés.

Aucune modification de la base de production n'a été nécessaire pour ces points : les droits observés correspondent au modèle de privilèges attendu. Les tests pgTAP ont été étendus pour figer ces garanties dans `supabase/tests/database/security_regression_test.sql` (plan 26). Ils ne sont pas exécutés tant que les runners GitHub Actions ne sont pas disponibles.

#### Vérifications encore nécessaires avant certification financière

- Tester avec des fixtures isolées et rollback la concurrence de deux demandes de retrait, les transitions de statut et la répétition de webhooks.
- Vérifier la cohérence complète entre les événements de paiement, les remboursements partiels et les écritures vendeur.
- Vérifier les chemins de stockage et les tailles/MIME côté application, en complément des restrictions de buckets et policies SQL.
- Aucun paiement, remboursement ou retrait réel n'a été déclenché. Aucun workflow GitHub Actions n'a été lancé.


### Audit des rôles administratifs — 6 novembre 2026

- L'audit des RPC a trouvé que `public.is_admin_actor()` inclut les rôles `ADMIN`, `SUPER_ADMIN` et `MODERATOR`. Cette fonction reste adaptée aux actions de modération (par exemple les décisions sur les produits), mais elle était aussi utilisée pour des mutations financières et de gestion de comptes.
- Risque identifié : un compte modérateur actif pouvait satisfaire le contrôle de certaines RPC de paiement vendeur, de blocage/réactivation de comptes et d'approbation/révocation des accès collaborateurs de boutique.
- Correction appliquée au projet Supabase actif par la migration `20261105192629_restrict_sensitive_admin_actions_to_active_admin_users` : les actions sensibles s'appuient désormais sur `private.is_admin()`, qui exige une entrée active dans `public.admin_users` et un profil actif.
- RPC corrigées : `admin_mark_seller_payout_paid`, `admin_mark_seller_payout_failed`, `admin_set_account_status`, les deux variantes de `admin_review_seller_access_request`, `expire_seller_access_requests` et la révocation administrative de demande d'accès.
- La lecture de la file des demandes peut rester accessible aux modérateurs pour le suivi, mais les notes internes de confirmation téléphonique sont désormais réservées aux administrateurs explicitement enregistrés.
- Le contrôle générique `is_admin_actor()` n'a pas été élargi ni supprimé : il reste utilisé pour les opérations de modération prévues. Les tests pgTAP ont reçu deux assertions ciblées ; ils ne sont pas exécutés afin de ne pas déclencher GitHub Actions ni consommer le quota de facturation.


### Correctif de liaison des preuves de livraison — 6 novembre 2026

- L'audit de `confirm_package_delivery` a trouvé que la preuve photo était jointe à une affectation par `assignment_id`, mais que la requête ne vérifiait pas explicitement que cette affectation appartenait au colis en cours de confirmation.
- Défense en profondeur ajoutée : la preuve doit maintenant être associée à une affectation du même livreur, du même colis et au statut `IN_TRANSIT`. Le code de livraison et l'affectation active du colis restent également vérifiés avant le changement d'état.
- Migration distante appliquée : `20261105193040_bind_delivery_evidence_to_package_assignment`. La définition SQL a été relue après application et contient le contrôle supplémentaire.
- Le test de régression pgTAP est ajouté au plan (30 assertions), mais n'a pas été exécuté conformément à la consigne de ne pas lancer de tests payants/Actions.
- Aucun colis réel, paiement ou remboursement n'a été modifié.


### Annulation sûre d'un groupe vendeur — 6 novembre 2026

- L'audit a confirmé que l'annulation d'un groupe ne libérait pas le stock réservé et ne fermait pas les colis/affectations de livraison encore au stade pré-ramassage.
- La fonction verrouille maintenant la commande principale avant le groupe, exige un compte actif, utilise `private.is_admin()` pour le contrôle administrateur et conserve l'accès d'exécution réservé au rôle serveur de confiance.
- Avant annulation, elle refuse tout groupe dont un colis est déjà ramassé/en transit/livré ou dont la consommation de stock est déjà enregistrée. Sinon, elle libère les quantités réservées, annule les affectations pré-dispatch et les colis concernés, journalise l'événement et met la commande principale à `CANCELLED` ou `PARTIALLY_FULFILLED` selon les autres groupes.
- Migration distante appliquée : `20261105193330_release_stock_and_cancel_package_on_seller_group_cancellation`. Vérification SQL effectuée : contrôles d'accès, libération de stock, journalisation et privilèges serveur confirmés.
- Deux assertions pgTAP supplémentaires (plan total 32) sont ajoutées, mais non exécutées. Aucun paiement, remboursement ou colis réel n'a été touché.


### Prévention des doubles demandes de remboursement — 6 novembre 2026

- L'audit a révélé que `admin_begin_refund` acceptait aussi le statut `PROCESSING`. Un second appel pendant qu'une demande était déjà en traitement pouvait donc relancer la même opération chez le prestataire et créer un risque de double remboursement.
- La fonction n'accepte maintenant que `REQUESTED`, `APPROVED` ou `FAILED` pour passer à `PROCESSING`. Un remboursement déjà en cours est refusé jusqu'à ce que son état soit réconcilié. Le contrôle `private.is_admin()` et l'accès authentifié existant sont conservés.
- Migration distante appliquée : `20261105193436_prevent_duplicate_refund_processing_attempts`. Le code SQL et la condition de transition ont été vérifiés après application.
- Une assertion pgTAP est ajoutée (plan total 33), sans exécution des tests ni appel au prestataire de paiement.


### Paiement confirmé après annulation — 6 novembre 2026

- Le traitement des webhooks acceptait une confirmation tardive après l'annulation de la commande, enregistrait le paiement comme réussi et laissait la commande annulée sans créer de suivi de remboursement.
- La fonction verrouille déjà le paiement et la commande. Elle crée désormais une demande de remboursement pour le montant restant dû lorsque le prestataire confirme un paiement sur une commande annulée. Les demandes déjà ouvertes ou échouées ne sont pas dupliquées ; un remboursement partiel déjà terminé ne provoque qu'une demande pour le solde restant.
- La base ne déclenche aucun appel de remboursement au prestataire : elle inscrit seulement la demande `REQUESTED` pour traitement administratif. Les rôles `anon` et `authenticated` ne peuvent toujours pas exécuter directement le processeur d'événements.
- Migration distante appliquée : `20261105193607_queue_refund_for_payment_settled_after_order_cancellation`. Vérification SQL effectuée : branche d'annulation, demande traçable, anti-duplication et privilèges service_role confirmés.
- Le webhook Wave V3 déployé classait déjà `checkout.session.payment_failed` comme `FAILED`; le fichier GitHub était en retard et a été synchronisé avec la version active (commit `b2f8e98`). Les anciens webhooks V1/V2 sont bien retirés avec HTTP 410.
- Une assertion pgTAP supplémentaire est ajoutée (plan total 34). Les tests ne sont pas exécutés ; aucun remboursement réel ni appel de prestataire n'a été effectué.


### Validation préalable des données de remboursement — 6 novembre 2026

- Le point d'entrée d'exécution passait le remboursement à `PROCESSING` avant de vérifier la référence du prestataire et le montant. Une référence absente pouvait donc bloquer la demande sans appel externe possible.
- `admin_begin_refund` vérifie désormais l'existence du paiement, le montant positif, la devise XOF, le prestataire autorisé et la référence fournisseur non vide avant toute transition vers `PROCESSING`. Les tentatives déjà en cours restent exclues pour éviter les doubles appels.
- Migration distante appliquée : `20261105193703_validate_refund_provider_data_before_processing`. Contrôle du corps SQL et des conditions de transition effectué.
- Une assertion pgTAP supplémentaire est ajoutée (plan total 35), sans exécution des tests ni appel au fournisseur.


### Raccordement du webhook CinetPay V3 — 6 novembre 2026

- La fonction déployée `create-cinetpay-payment-session-v3` envoyait `notify_url` vers `/functions/v1/cinetpay-webhook`, un ancien endpoint retiré qui répond HTTP 410.
- Le callback a été corrigé vers `/functions/v1/cinetpay-webhook-v3`, dont la signature, la vérification côté CinetPay, le montant et la devise XOF sont contrôlés avant traitement.
- Déploiement ciblé effectué : `create-cinetpay-payment-session-v3` version 6, avec `verify_jwt=true` conservé. Aucun paiement réel n'a été lancé.
- La source GitHub a été synchronisée avec le code déployé corrigé.


### Synchronisation des sources des fonctions de paiement — 6 novembre 2026

- Les sources GitHub de `create-wave-payment-session-v3`, `create-cinetpay-payment-session-v3`, `wave-payment-webhook-v3`, `cinetpay-webhook-v3`, `execute-payment-refund` et `payment-return` ont été rapprochées des versions effectivement déployées pour supprimer les écarts de code constatés.
- Les anciens webhooks Wave/CinetPay restent retirés (HTTP 410). Les fonctions de création de paiement conservent `verify_jwt=true`; les webhooks publics conservent leurs contrôles cryptographiques et leurs vérifications côté prestataire.
- Seul le callback CinetPay a nécessité un nouveau déploiement ciblé. Les autres changements de ce groupe sont des synchronisations GitHub, pas des déploiements.


### Indexation des clés étrangères privées — 6 novembre 2026

- L'advisor de performance signalait huit clés étrangères sans index couvrant dans les tables privées de sauvegarde/réparation, d'audit de modération et de demandes d'accès vendeur.
- Huit index ciblés ont été ajoutés sur `restored_by`, `actor_id`, `actor_user_id`, `conversation_id`, `initial_message_id`, `owner_shop_id`, `reviewed_by` et `revoked_by`. Aucun index existant n'a été supprimé.
- Migration distante appliquée : `20261105193940_index_uncovered_private_foreign_keys`. Après application, l'advisor ne signale plus de clé étrangère non indexée (0 au lieu de 8). Les avertissements de politiques permissives et les index inutilisés sont conservés pour analyse séparée ; aucun nettoyage massif n'a été fait.
- Une assertion pgTAP vérifiant les huit index est ajoutée (plan total 36), sans exécution.


### Consolidation des politiques SELECT redondantes — 6 novembre 2026

- L'advisor signalait six ensembles de politiques permissives SELECT en double sur `inventory`, `inventory_movements`, `order_groups`, `order_items`, `products` et `shops`.
- Les prédicats propriétaire, accès vendeur délégué, visibilité publique, client et administrateur ont été fusionnés sans élargir les conditions d'accès. Pour `products` et `shops`, les politiques publiques restent séparées des politiques authentifiées afin de ne pas appeler les contrôles d'accès délégué pour `anon`.
- Migration distante appliquée : `20261105194019_merge_overlapping_authenticated_read_policies`. L'advisor ne signale plus les six doublons ; les avertissements de clés étrangères non indexées sont également à zéro après la migration précédente.
- Une assertion pgTAP vérifie la consolidation et la présence d'une politique SELECT authentifiée sur les tables concernées (plan total 37). Aucun test n'a été exécuté.


### Protection de la localisation des livreurs — 6 novembre 2026

- La politique de lecture permettait à un client de voir la dernière position d'un livreur dès qu'une affectation non livrée existait, y compris si l'affectation ou le colis avait été annulé.
- La lecture client est désormais limitée aux affectations `ASSIGNED`, `ACCEPTED`, `PICKED_UP` ou `IN_TRANSIT`, aux colis en préparation de ramassage/en transit et aux commandes non annulées/non remboursées. Le livreur conserve l'accès à ses propres positions.
- Migration distante appliquée : `20261105194137_restrict_courier_location_to_active_assignments`. La définition de la politique a été relue et les statuts actifs/inactifs vérifiés.
- Une assertion pgTAP est ajoutée (plan total 38), sans exécution.


### Démarrage du trajet par le livreur — 6 novembre 2026

- Le dépôt Flutter appelle `start_package_delivery` depuis le client authentifié, mais la fonction SQL n'accordait auparavant l'exécution qu'à `service_role`. L'action de démarrage du trajet ne pouvait donc pas fonctionner depuis le parcours livreur.
- L'exécution est maintenant accordée à `authenticated` et `service_role`, jamais à `anon`. La fonction exige un compte actif, le rôle `COURIER`, un colis au statut `PICKED_UP` et une affectation `PICKED_UP` appartenant au même utilisateur. Les deux changements d'état restent atomiques dans la transaction.
- Migration distante appliquée : `20261105194234_allow_guarded_courier_start_delivery`. Vérification des privilèges et des contrôles internes effectuée.
- Une assertion pgTAP est ajoutée (plan total 39), sans exécution ni changement de colis réel.


### Blocage restant — privilèges PostGIS spatial_ref_sys — 6 novembre 2026

- L'advisor de sécurité signale toujours `public.spatial_ref_sys` avec RLS désactivé. L'inspection des privilèges confirme que `anon` et `authenticated` disposent actuellement de SELECT, INSERT, UPDATE et DELETE sur cette table de métadonnées PostGIS.
- La table et l'extension PostGIS appartiennent à `supabase_admin`. Le rôle SQL utilisé par les migrations (`postgres`) n'est ni propriétaire, ni membre de `supabase_admin`, ni superutilisateur. La tentative de verrouillage a échoué sur le contrôle de propriété et a été annulée intégralement ; aucun changement partiel n'a été appliqué.
- Ne pas contourner cette propriété ni modifier les catalogues système. Il faut exécuter la correction depuis un contexte propriétaire `supabase_admin` : retirer les droits DML à `anon` et `authenticated`, conserver SELECT public en lecture seule, activer RLS et ajouter une politique SELECT explicite. Tant que cette opération n'est pas faite, l'advisor conserve une erreur de sécurité réelle.


### Récupération manuelle des remboursements Wave bloqués — 6 novembre 2026

- Une requête réseau Wave interrompue ou une confirmation fournisseur reçue alors que la finalisation SQL échoue peut laisser le remboursement en `PROCESSING`. Le statut n'est volontairement pas réessayable automatiquement, pour éviter de renvoyer un remboursement potentiellement déjà exécuté.
- Une fonction `admin_reconcile_wave_refund` est maintenant disponible pour un administrateur actif après vérification manuelle dans Wave. Elle exige une référence de remboursement fournisseur et une note de confirmation, ne traite que les remboursements Wave en `PROCESSING`, appelle uniquement la finalisation comptable interne et inscrit une trace dans `admin_change_log`. Elle ne contacte jamais Wave.
- Migration distante appliquée : `20261105194405_add_admin_recovery_for_confirmed_wave_refunds`. Les privilèges et les gardes administrateur/fournisseur/statut ont été vérifiés.
- Une assertion pgTAP est ajoutée (plan total 40), sans exécution ni remboursement réel.
