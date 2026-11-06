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


### Informations de tournée dans l'espace livreur — 6 novembre 2026

- L'écran livreur n'affichait que l'identifiant du colis et son statut : il ne fournissait ni adresse de retrait, ni adresse de destination, ni coordonnées GPS utilisables.
- Une RPC dédiée `get_courier_assignments` retourne maintenant uniquement les affectations actives du livreur connecté, avec le nom/adresse de la boutique et les champs nécessaires à l'itinéraire de livraison. Elle exige un compte actif et le rôle `COURIER`; les numéros de téléphone et le nom du destinataire ne sont révélés qu'après acceptation de l'affectation.
- Le dépôt Flutter utilise cette RPC et affiche les adresses, les contacts autorisés et les liens d'itinéraire Google Maps (coordonnées GPS lorsqu'elles existent, adresse sinon).
- Migration distante appliquée : `20261105194532_add_secure_courier_assignment_details`. La fonction et ses privilèges ont été vérifiés. Les fichiers Flutter ont été relus sur GitHub ; les tests Flutter ne sont pas exécutés.
- Une assertion pgTAP supplémentaire est ajoutée (plan total 41), sans exécution.


### Audit complémentaire — annulations globales, synchronisation des colis et allocation des remboursements — 6 novembre 2026

Relecture en lecture seule des définitions SQL actuellement déployées (`complete_refund`, `request_refund`, `transition_order_status`, `transition_order_group_status`, `sync_order_after_package_change`, `open_return`) et des index de `seller_ledger`.

#### Findings à corriger avant mise en production financière

1. **Allocation des remboursements partiels trop large**
   - `complete_refund` répartit chaque remboursement au prorata du `subtotal` de tous les groupes de la commande, sans référence à la boutique, au groupe ou à l'article à l'origine du remboursement.
   - Cette règle peut débiter les vendeurs non concernés lorsqu'un seul groupe ou un seul article est remboursé. Elle répartit également tout montant remboursé (qui peut inclure des frais ou remises) sur les seuls sous-totaux produits.
   - Le registre a une contrainte unique `(seller_id, entry_type, reference_id)`. Si un même vendeur possède plusieurs boutiques/groupes dans une commande, plusieurs insertions REFUND pour ce vendeur et ce remboursement peuvent entrer en conflit ; la fonction actuelle ne regroupe pas explicitement les montants par vendeur avant insertion.
   - `request_refund(order_id, amount, reason)` ne recueille pas de cible d'allocation. Le modèle actuel ne permet donc pas de déterminer de façon fiable le ou les vendeurs qui doivent supporter le remboursement.
   - **Correction requise** : définir une source d'allocation explicite et immuable (au minimum refund allocations par groupe, idéalement par article/quantité, avec traitement distinct des frais de livraison, remises, commissions et montants déjà versés). Agréger ensuite par vendeur avant d'écrire le registre, et rendre l'écriture idempotente. Ne pas remplacer le prorata par une autre formule arbitraire.

2. **Annulation globale incohérente avec les protections d'annulation par boutique**
   - `transition_order_status` autorise un administrateur à définir directement le statut parent sans matrice de transitions stricte. Lors d'une annulation, elle libère les quantités de tous les articles puis passe certains groupes à `CANCELLED`, mais ne ferme pas les colis et affectations pré-ramassage comme le fait `transition_order_group_status`.
   - Le contrôle de la fonction globale ne bloque pas explicitement les colis déjà pris en charge/en transit avant de changer le statut parent. Il existe donc un risque de divergence entre commande, groupes, colis et affectations.
   - **Correction requise** : centraliser l'annulation globale sur les mêmes contrôles que l'annulation de groupe, verrouiller dans un ordre cohérent, refuser les états déjà expédiés/livrés, libérer le stock une seule fois et fermer les colis/affectations encore pré-départ. La voie administrative doit avoir des transitions autorisées explicites et auditées.

3. **Synchronisation parent incomplète après changement d'un colis**
   - `sync_order_after_package_change` passe un groupe à `DELIVERED` seulement si tous ses colis sont livrés, et la commande parent à `DELIVERED` seulement si tous les groupes sont livrés. Elle passe le parent à `IN_TRANSIT` lorsqu'au moins un groupe est en transit.
   - Elle ne calcule pas explicitement les états parent `CANCELLED` ou `PARTIALLY_FULFILLED` à partir de l'ensemble des groupes. Les annulations actuelles compensent parfois cela par une mise à jour manuelle, mais cette logique est dispersée et peut laisser un statut parent obsolète selon l'ordre des événements.
   - **Correction requise** : une fonction unique de recalcul du statut parent à partir de tous les groupes et colis, appelée après chaque transition pertinente, avec une table de vérité documentée pour les mélanges livré/annulé/en transit/en attente.

4. **Retours d'articles et remboursements ne sont pas reliés par le flux inspecté**
   - `open_return` crée une demande de retour au niveau de l'article livré et vérifie le délai de retour, mais le flux inspecté ne montre pas de fonction de décision qui crée une allocation de remboursement rattachée à cet article.
   - Il faut relier l'approbation du retour à une allocation comptable précise, sans rembourser automatiquement un article uniquement parce qu'une demande de retour a été ouverte.

#### Décision de sûreté

- Aucun changement comptable ou de statut n'a été appliqué pendant cet audit : il manque une règle métier confirmée pour déterminer la responsabilité du vendeur, la part des frais de livraison/remises et le traitement des commandes multi-boutiques avec plusieurs boutiques appartenant au même vendeur.
- Aucun paiement, remboursement, retour, retrait ou colis réel n'a été modifié.
- Aucun test pgTAP/Flutter ni workflow GitHub Actions n'a été lancé.
- Le prochain correctif doit commencer par le schéma d'allocation de remboursement et une fonction transactionnelle idempotente ; ensuite seulement, la logique d'annulation globale et le recalcul parent pourront être unifiés sans risquer de déséquilibrer le registre.


### Audit complémentaire — Storage, RPC SECURITY DEFINER et compatibilité Supabase CLI — 6 novembre 2026

#### Stockage des médias et documents
- Buckets constatés : `avatars` (public), `documents`, `order-feedback-media`, `product-media`, `shop-media` (privés).
- Les quatre buckets privés disposent de politiques de lecture ciblées ; les documents ne sont pas rendus publics. Les politiques d'insertion vérifient les chemins d'objets et l'appartenance au vendeur/utilisateur ; une politique restrictive commune exige un compte actif pour les opérations authentifiées.
- Les médias de produits ne sont lisibles publiquement que si le produit est actif, la boutique active et vérifiée, et le produit non expiré. Les médias de boutique sont publiquement lisibles uniquement pour les boutiques actives et vérifiées. Les médias d'avis/livraison ont des contrôles dédiés (propriétaire, commande/livraison, avis publié, admin).
- `avatars` est volontairement public pour les images de profil. Les opérations d'écriture restent contrôlées par RLS. Deux générations de politiques de lecture authentifiée des avatars se recouvrent ; c'est un nettoyage possible, mais aucune suppression n'a été faite pour ne pas toucher à la compatibilité cliente.
- Limite d'upload configurée : avatars 5 MiB, documents 10 MiB, feedback 20 MiB, product-media 5 MiB, shop-media 50 MiB. Les types MIME sont restreints par bucket.
- **Observation importante** : les cinq buckets affichent actuellement zéro objet dans `storage.objects`. Les règles sont en place, mais l'audit ne peut pas encore confirmer le parcours réel d'upload/téléchargement avec des fichiers de production.
- Les buckets privés doivent être téléchargés via session autorisée ou URL signée courte ; ne jamais convertir les documents ou preuves privées en bucket public.

#### Fonctions privilégiées et RPC
- Inventaire SQL des fonctions `SECURITY DEFINER` de `public` : aucune fonction applicative listée n'est exécutable par `anon`. Les 3 avertissements anon de l'advisor sont les surcharges natives PostGIS `st_estimatedextent`.
- Les fonctions applicatives accessibles à `authenticated` sont des RPC de l'application ; l'avertissement advisor de 80 fonctions ne prouve pas à lui seul une vulnérabilité. Elles doivent néanmoins conserver leurs contrôles d'identité, rôle, propriété, statut de compte et limites d'entrée.
- Les fonctions dont le `search_path` est vide utilisent des références explicitement qualifiées (`public.*`, `private.*`, `auth.*`) dans les définitions relues. Les schémas `public`, `private`, `extensions` et `vault` ne donnent pas le privilège CREATE à `anon`, `authenticated` ou `PUBLIC`.
- Les vues exposées identifiées dans `public` sont les vues PostGIS `geography_columns` et `geometry_columns`, détenues par `supabase_admin` ; aucune vue métier applicative supplémentaire n'a été détectée dans `pg_views`.

#### Advisor sécurité et blocage propriétaire
- L'advisor confirme encore : 17 tables RLS sans policy (dont tables privées/audit et deux tables publiques fermées volontairement), 1 erreur RLS désactivé sur `public.spatial_ref_sys`, 5 avertissements extensions en `public`, 3 avertissements anon PostGIS et 80 avertissements SECURITY DEFINER accessibles aux utilisateurs authentifiés.
- Ne pas ouvrir les 17 tables sans policy : leur absence de policy constitue ici un refus d'accès par défaut, pas une raison d'ajouter une policy permissive.
- La correction de `spatial_ref_sys` reste bloquée par son propriétaire `supabase_admin`. Ne pas contourner ce contrôle ni modifier les catalogues système.

#### Compatibilité CLI
- Le workflow DB du dépôt épingle `supabase/setup-cli@v1` à la version `2.122.1`, ce qui évite la migration implicite vers Supabase CLI v3 annoncée le 2 novembre 2026.
- CLI v3 change le ciblage par défaut des commandes DB/Storage vers le local et exige `--remote` pour les opérations hébergées. Toute future migration de CLI doit mettre à jour explicitement les commandes, sans déclencher le workflow maintenant.
- GitHub Actions n'a pas été exécuté ; aucun test ni déploiement n'a été lancé.

#### Conclusion
- Les règles Storage sont cohérentes avec les catégories de données et la séparation public/privé voulue. La prochaine validation fonctionnelle devra utiliser un compte de test et des fichiers non sensibles, mais uniquement après autorisation explicite de lancer les tests.
- Aucun changement de bucket, de policy, de fonction, de statut utilisateur ou de fichier utilisateur n'a été appliqué pendant cet audit.


### Correction technique — concurrence des notifications push — 6 novembre 2026

- Le fan-out vers les appareils FCM est désormais limité à 5 envois simultanés par notification.
- Le traitement du lot de notifications en attente est limité à 5 notifications simultanées au lieu de lancer tout le lot de 50 en parallèle.
- Une erreur réseau sur un appareil est convertie en échec isolé `FCM_NETWORK_ERROR` afin que les autres appareils de la même notification continuent d'être traités.
- Une erreur de traitement d'une notification n'interrompt plus le lot entier ; la réponse conserve un résultat par identifiant avec un code d'erreur générique, sans renvoyer de détails internes.
- La limite réduit les pointes de concurrence, mais ne constitue pas un test de charge. Le déploiement de l'Edge Function et les tests restent à faire plus tard, après autorisation explicite.
- Vérification effectuée : relecture du fichier sur la branche `main`, présence confirmée du worker limité à 5 pour les appareils et les notifications, et des chemins d'erreur isolés.


### Audit notifications — appareils, accès aux données et état du déploiement — 6 novembre 2026

- `notification_devices` : RLS limité au propriétaire et aux comptes actifs ; le jeton push est unique globalement ; la RPC `register_notification_device` n'accepte que ANDROID/IOS, rejette les jetons vides ou supérieurs à 4096 caractères et empêche un autre compte de revendiquer un jeton existant.
- `notification_preferences` : lecture/écriture limitée au propriétaire et compte actif.
- `notifications` : lecture limitée au propriétaire ; UPDATE accordé uniquement sur la colonne `read_at`, et non sur les champs système de dispatch. Les utilisateurs ne peuvent donc pas falsifier `push_sent_at`, `push_attempts` ou le contenu de notification via cette table.
- `claim_notification_for_push` verrouille la notification, refuse les éléments déjà envoyés et les traitements récents (fenêtre de 5 minutes), puis marque le traitement en cours. Cela réduit le risque de double traitement concurrent.
- Limite connue à traiter avant un fort volume multi-appareils : le modèle stocke le résultat d'envoi au niveau notification, pas au niveau de chaque appareil. Lorsqu'une notification réussit sur au moins un appareil mais échoue sur un autre, l'état actuel évite un renvoi global qui dupliquerait les notifications déjà reçues, mais ne permet pas de retenter uniquement l'appareil en échec. Une table d'état par couple notification/appareil serait nécessaire pour une reprise précise.
- La fonction Edge `dispatch-push-notifications` est actuellement déployée en version 7 ; le code du dépôt contient maintenant le worker à concurrence limitée. **Le code modifié n'a pas été déployé**. Aucun appel de dispatch n'a été fait, aucun push réel n'a été envoyé.


### Incident observé — dispatch push en 503 — 6 novembre 2026

- L'advisor Health signale que `dispatch-push-notifications` a renvoyé 5 erreurs sur 5 requêtes (100 %) sur deux fenêtres consécutives.
- Les journaux confirment des réponses HTTP 503 répétées sur la version déployée 7, déclenchées par `pg_net/0.20.4`. Le contexte de configuration déjà constaté est `fcm_not_configured` : le compte de service Firebase/FCM n'est pas configuré dans les secrets de la fonction.
- Le code de dispatch est conçu pour refuser l'envoi quand le service account FCM est absent ; ce comportement est préférable à une fausse confirmation de livraison.
- **Action nécessaire avant activation** : renseigner côté Supabase Edge Function les secrets Firebase requis (`FCM_SERVICE_ACCOUNT_JSON`, ou les champs de projet complémentaires prévus par le code), puis effectuer un test contrôlé avec un appareil de test et confirmer la réception. Ne jamais enregistrer le JSON du compte de service dans GitHub ni dans le code mobile.
- La version du dépôt contenant la limite de concurrence n'est pas encore déployée ; le runtime continue donc d'exécuter la version 7. Aucun appel manuel de l'endpoint n'a été effectué durant cet audit.


### Correction Android — signature de production obligatoire — 6 novembre 2026

- Le fichier `android/app/build.gradle.kts` ne retombe plus sur la signature `debug` lorsque `android/key.properties` est absent.
- Une compilation `release` échoue désormais explicitement si le fichier de signature est absent, si l'une des propriétés `keyAlias`, `keyPassword`, `storeFile`, `storePassword` manque, ou si le keystore indiqué n'existe pas.
- Les compilations `debug` restent configurables sans keystore de production.
- Le fichier `.gitignore` ignore déjà `android/key.properties` et `android/app/upload-keystore.jks`; ces éléments sensibles ne doivent jamais être commités.
- Relecture GitHub effectuée : absence du fallback debug confirmée, contrôles de présence/complétude du keystore confirmés, exclusions Git confirmées.
- Aucun APK/AAB n'a été construit et aucun keystore n'a été lu, créé ou modifié.


### Suivi GPS du livreur — correction de robustesse et limite arrière-plan — 6 novembre 2026

- Relecture de `CourierPage`, `DeviceLocationService`, du manifeste Android et de `Info.plist`.
- Le suivi existant est un envoi au premier plan : première position immédiate, puis timer de 15 secondes tant que l'écran livreur reste actif. Ce n'est pas un service de localisation en arrière-plan.
- Le code précédent lançait les appels périodiques sans attendre leur fin et ne capturait pas les exceptions du timer. Des requêtes pouvaient se chevaucher si le réseau ou le GPS était lent, et une erreur asynchrone pouvait rester non gérée.
- Correctif enregistré dans `lib/features/courier/presentation/courier_page.dart`, commit `4d6a71ca26d132f337301a27aa69c4d1336a2a76` : verrou « single-flight » pour empêcher les envois concurrents ; capture des erreurs périodiques ; arrêt du partage avec message visible lorsque l'envoi échoue.
- Documentation mise à jour dans `docs/mobile-location-permissions.md`, commit `65be668ced3a61d07ee1ae866dab5535cb4bd23f`.
- Limite native confirmée : Android déclare les permissions de localisation au premier plan, sans `ACCESS_BACKGROUND_LOCATION` ni service de premier plan de localisation. iOS a les descriptions d'usage « When In Use » et « Always », mais ses modes d'arrière-plan ne contiennent pas `location`. Le suivi en arrière-plan n'est donc pas certifié et ne doit pas être promis.
- Prochaine étape : concevoir le service arrière-plan Android/iOS avec consentement, indicateur visible, arrêt à la fin de mission, reprise contrôlée et tests sur appareils réels. Ne pas ajouter de permissions arrière-plan avant l'implémentation correspondante.
- Aucun test Flutter, build natif, workflow GitHub Actions, déploiement Supabase ou opération de paiement n'a été exécuté.


### Séparation des clés Supabase client/serveur — 6 novembre 2026

- Inspection de `lib/core/config/supabase_config.dart` : l'application Flutter ne lit que `SUPABASE_PUBLISHABLE_KEY`, avec compatibilité de repli sur l'ancienne variable publique `SUPABASE_ANON_KEY`. L'initialisation Supabase garde `debug: false`.
- Recherche ciblée dans le dépôt de `SUPABASE_SERVICE_ROLE_KEY` : les références retrouvées sont dans les Edge Functions Deno côté serveur ; aucune référence à cette variable n'a été trouvée dans le code Flutter inspecté.
- Conclusion limitée à cette vérification : la configuration Flutter examinée sépare correctement la clé publique client de la clé de service serveur. Cette recherche ne remplace pas un scan exhaustif d'historique Git, des secrets CI et de tous les fichiers binaires.
- Aucun secret n'a été affiché, demandé ou modifié. Aucun déploiement ni test n'a été exécuté.


### Upload des images produit — validation MIME et nettoyage des objets orphelins — 6 novembre 2026

- Relecture de `SellerProductsRepository.uploadProductImage`.
- Avant correction, l'extension était reprise directement du nom du fichier et le type MIME pouvait être fourni sans liste blanche côté client. Si l'enregistrement des métadonnées échouait après l'upload, l'objet Storage pouvait rester orphelin.
- Correctif enregistré dans `lib/features/seller/data/seller_products_repository.dart` : seuls JPEG, PNG et WebP sont acceptés ; le suffixe du chemin Storage est généré depuis le type MIME autorisé, et non repris arbitrairement du nom d'origine ; si le RPC `add_seller_product_image` échoue, le client tente de supprimer l'objet qui vient d'être envoyé puis conserve l'erreur initiale.
- La détection MIME utilise le type fourni par le sélecteur et, s'il est absent, une correspondance stricte avec les extensions JPEG/PNG/WebP. Cela améliore la validation cliente mais ne prouve pas le contenu binaire réel du fichier : la politique MIME et la limite 5 MiB du bucket restent le contrôle serveur. Une validation de signature binaire côté serveur serait un durcissement supplémentaire.
- Les objets Storage et les métadonnées n'ont pas été testés en environnement réel. Aucun fichier n'a été envoyé, aucune donnée existante n'a été supprimée. Aucun test Flutter, workflow Actions ou déploiement n'a été lancé.


- Correctif complémentaire : `SellerModerationPage._respond` conserve désormais le chemin Storage et le client d'upload hors du bloc `try`. Si l'appel `seller_respond_to_catalog_finding` échoue après l'envoi d'une photo/vidéo, le client tente de supprimer le média non associé dans `order-feedback-media`, sans masquer l'erreur initiale. Commit : `6980921e7d6a9272f3bc0d8698cb11b71d9517e2`. Nettoyage best-effort, non testé en environnement réel.


- Correctif complémentaire : `CourierRepository.uploadEvidence` supprime maintenant de façon best-effort le fichier de preuve envoyé si le RPC `attach_delivery_evidence` échoue. Cela évite de conserver une photo/vidéo de livraison privée sans ligne de métadonnées associée. Commit : `05d22ee95a03995f9255fa06db01ec98d633fad1`. Aucun média réel n'a été envoyé ou supprimé ; comportement non testé.


### Audit complémentaire — parcours d'upload mobile — 6 novembre 2026

- Relecture sur `main` des quatre parcours d'upload : `SellerProductsRepository.uploadProductImage`, `SellerModerationPage._respond`, `CourierRepository.uploadEvidence` et `OrderDetailsPage._review`.
- Les quatre parcours effectuent désormais un nettoyage Storage best-effort si l'enregistrement RPC des métadonnées échoue après l'upload. Le nettoyage conserve l'erreur initiale et n'est pas présenté comme garanti si Storage est indisponible.
- Le parcours images produit est le plus strict : liste blanche JPEG/PNG/WebP, extension de stockage dérivée du MIME accepté et suppression de l'objet si `add_seller_product_image` échoue.
- Les parcours modération, preuve de livraison et avis utilisent encore, à des degrés divers, l'extension du nom de fichier et/ou un MIME fourni par le sélecteur avec fallback. Cela ne prouve pas le format binaire réel et ne remplace pas une validation serveur de signature de fichier.
- Avant de normaliser ces trois parcours, il faut confirmer les formats effectivement acceptés par les sélecteurs mobiles et les limites MIME du bucket `order-feedback-media` (images et vidéos). Ne pas imposer une liste arbitraire qui bloquerait des formats légitimes ou créerait des incohérences avec la policy Storage.
- Aucun fichier réel n'a été envoyé ou supprimé. Aucun test Flutter, build, workflow GitHub Actions ou déploiement n'a été lancé.


### Durcissement des MIME pour les médias clients — 6 novembre 2026

- Les trois parcours restants ont été harmonisés avec la liste MIME déjà définie dans la migration Storage `20261103220723_restrict_media_buckets_to_image_and_short_video_mime_types.sql` : images JPEG/PNG/WebP/HEIC et vidéos MP4/QuickTime.
- `CourierRepository.uploadEvidence` n'accepte que les MIME image autorisés pour la preuve photo ; `SellerModerationPage._respond` et `OrderDetailsPage._review` appliquent une liste distincte selon IMAGE/VIDEO.
- Le suffixe du chemin Storage est désormais canonisé à partir du MIME accepté (jpg/png/webp/heic/mp4/mov), au lieu de reprendre librement l'extension d'origine. Si le MIME est absent, seul un fallback via une extension explicitement reconnue est accepté.
- Les formats acceptés correspondent aux MIME autorisés par le bucket `order-feedback-media`; sa limite Storage est de 20 MiB. Les limites applicatives plus strictes restent en place (5 MiB pour les images et preuves photo, 20 MiB pour les vidéos).
- Commits : `fea7320a4620ed2ab3e77d8f931ffa0bd7c4c640` (preuves livreur), `3b234011746ac749878cd4eddb663136042c32f0` (réponses modération), `b16fa8d854176d38c2c4071bf24607ec464e9c84` (avis clients).
- Limite restante : la validation MIME côté client et la policy Storage ne valident pas la signature binaire réelle. Une inspection du contenu côté serveur reste nécessaire si le niveau de garantie doit dépasser les contrôles MIME déclaratifs.
- Vérification effectuée : relecture des trois fichiers après commit et comparaison des MIME avec la migration Storage et la limite du bucket. Aucun fichier réel, test, build, workflow Actions ou déploiement n'a été exécuté.


### Journalisation mobile — diagnostics push limités au mode debug — 6 novembre 2026

- La recherche ciblée des appels `debugPrint`/ `print(` a trouvé des traces d'erreurs et de stack traces dans le service de notifications push.
- Les trois blocs de diagnostic concernés sont désormais protégés par `kDebugMode`. Les détails d'exception et les stack traces ne sont donc plus écrits par ces blocs dans les builds release.
- Le changement ne modifie pas le flux d'inscription des jetons push, l'authentification, ni les appels RPC. Les erreurs restent gérées comme auparavant.
- Commit : `fcb4cd9333b8cb459f7caff0413035d0503b14fe`.
- Vérification effectuée : relecture du fichier sur `main`, présence du garde `kDebugMode` confirmée pour les trois blocs. Aucun build, test ou workflow n'a été lancé.


### Navigation des notifications — destinations internes allowlistées — 6 novembre 2026

- L'audit de `lib/core/navigation/app_navigation.dart` a révélé que le champ `route` fourni par le payload push était accepté dès lors qu'il commençait par `/`. Le payload pouvait donc choisir une destination interne arbitraire, y compris une route d'administration. Cela ne remplaçait pas les contrôles d'autorisation des écrans, mais élargissait inutilement la surface d'attaque.
- Le routage direct depuis `data['route']` a été supprimé. Les notifications sont maintenant redirigées uniquement vers les destinations fixes déjà utilisées par le service : commandes, suivi livraison, messages, promotions, transport, services ou notifications.
- Les identifiants de commande/livraison sont filtrés par une expression stricte `^[A-Za-z0-9_-]{1,128}$` avant insertion dans le chemin ; les slashs, fragments, paramètres et séquences de traversal sont rejetés.
- Tests de régression ajoutés pour une route arbitraire vers l'administration, les identifiants contenant des séparateurs et un identifiant opaque valide.
- Commits : `24c37e1a6ffaf9e8bcd2ba3a662d80b4cee102d5` (navigation), `970f0b5187217ee373787ed4e0181d40d145029b` (tests).
- Relecture des routes dans `lib/core/routing/app_router.dart` effectuée : les chemins construits correspondent aux routes déclarées. Aucun test n'a été exécuté ; les tests sont seulement ajoutés.


- Correction de mise en forme du fichier de tests : les trois nouveaux cas ont été replacés à l'intérieur de `main()` (commit `5ae7b065a260043720d1cabbf4f085e9058b4cd1`). Relecture statique confirmée ; tests non exécutés.


### Précontrôle de taille des médias avant lecture en mémoire — 6 novembre 2026

- Les trois parcours de preuve livreur, réponse de modération et avis client lisaient les fichiers en mémoire avant de vérifier leur taille maximale. Un fichier très volumineux pouvait donc provoquer une consommation mémoire inutile ou une pression mémoire sur le mobile avant d'être rejeté.
- Les parcours consultent maintenant `XFile.length()` et rejettent les fichiers vides ou trop volumineux avant `readAsBytes()`. La taille des octets effectivement lus est ensuite contrôlée une seconde fois avant l'upload.
- Les plafonds applicatifs restent inchangés : 5 MiB pour preuve/photo et 20 MiB pour vidéo.
- Commits : `8b0ee807916b97693e1303a1a6ed24418e7d7e34` (livreur), `6f0f3b8cd5763cc3f9d6ddcfbfecfb6944bf189f` (modération), `79794aa35ce016495cdf437f60f630f7c2a151df` (avis clients).
- Relecture des trois fichiers effectuée. Aucun test Flutter, build, workflow Actions ou upload réel n'a été exécuté.


- Extension du précontrôle mémoire au parcours d'image produit : `SellerProductsRepository.uploadProductImage` vérifie maintenant `XFile.length()` avant la lecture en mémoire, puis contrôle à nouveau la taille des octets lus. Plafond inchangé : 5 MiB. Commit `1d93b3022a04945f819937d1c9347bd4c3715a45`.


### AUD-03 — annulation globale : durcissement serveur appliqué — 7 novembre 2026

- La revue de la fonction SQL active a confirmé que l'annulation globale pouvait auparavant cibler une commande payée et exécuter la libération du stock sans fermer systématiquement les colis et affectations de livraison.
- Migration appliquée sur Supabase : `20261106200419_block_global_order_cancel_and_harden_unpaid_cancellation`.
- `transition_order_status(..., 'CANCELLED', ...)` délègue maintenant à `cancel_unpaid_order`. La fonction globale n'effectue plus elle-même une libération des réservations ni une mise à jour globale des groupes en `CANCELLED`.
- Le flux impayé vérifie le propriétaire de la commande, le statut `PENDING_PAYMENT`, l'absence de paiement réglé, l'absence de colis/affectation déjà expédié(e) et l'absence de consommation de stock.
- Il libère le stock par produit et variante, ferme les affectations pré-départ, ajoute `delivery_assignment_events`, annule colis/groupes, libère les utilisations de coupon et inscrit `order_events`.
- Contrôle post-migration : fonctions détenues par `postgres`, `SECURITY DEFINER` conservé, `anon` sans droit EXECUTE, `authenticated` et `service_role` autorisés. Les gardes attendues ont été retrouvées dans les définitions actives.
- Deux assertions pgTAP ont été ajoutées au fichier `security_regression_test.sql` (plan augmenté de 41 à 43 assertions pour ce fichier). Aucun test pgTAP/Flutter/Edge n'a été exécuté : les validations automatiques restent à lancer sur un runner fonctionnel et une base isolée.
- La base ne contient actuellement aucune commande, paiement, coupon utilisé, affectation ou remboursement ; aucun stock ou argent métier n'a été modifié.
- **Statut : correction serveur appliquée ; ticket RIA-29 maintenu en cours** jusqu'aux tests d'intégration et à la validation des parcours. L'annulation d'une commande payée reste bloquée par cette RPC tant qu'un workflow de retour/remboursement cohérent n'est pas défini (voir AUD-02).
- Commit migration GitHub : `53e513c5487ba5c27cf819033edc7d70092766b7`. Commit tests : `8a32c1e1e6994c75d3c0961be68715a1cccc7d2e`.


- Relecture complémentaire : le premier durcissement faisait passer aussi les annulations administrateur par le contrôle du propriétaire client. Migration corrective appliquée : `20261106201500_aud03_allow_admin_to_cancel_unpaid_orders_safely`. Un administrateur actif enregistré via `private.is_admin()` peut maintenant annuler une commande appartenant à un client, mais uniquement si elle reste `PENDING_PAYMENT` et si les gardes paiement/colis/stock sont satisfaites.
- Vérification SQL : le guard admin, le prédicat propriétaire-ou-admin et le statut `PENDING_PAYMENT` sont présents dans la définition déployée ; les privilèges restent réservés à authenticated/service_role, sans anon.
- Une troisième assertion pgTAP a été ajoutée pour vérifier l'accès admin sur les seules commandes impayées. Le fichier contient 44 assertions, non exécutées à ce stade. Aucune donnée métier n'a été modifiée.


### AUD-04 — RPC de lecture sécurisée du stock par variante déployée — 7 novembre 2026

- La base active ne disposait pas de `public.get_seller_product_variant_inventory(uuid)`, alors que le dépôt Flutter appelait déjà cette RPC.
- Migration Supabase appliquée : `20261106201211_add_secure_seller_variant_inventory_read`. Le fichier GitHub porte maintenant le même numéro que l'historique de migration distant.
- La fonction vérifie le compte actif, la session authentifiée et la propriété du produit à travers boutique/vendeur. Elle retourne les variantes avec `quantity` et `reserved_quantity`, en retournant zéro si aucune ligne d'inventaire n'existe.
- Vérification SQL : `authenticated` peut exécuter la fonction ; `anon` ne le peut pas ; la table `product_variant_inventory` ne donne toujours aucun droit direct SELECT aux rôles clients et sa policy de refus reste active.
- Le dépôt Flutter avait déjà les méthodes de lecture et de modification par variante. Le fallback vers l'éditeur de stock parent est désormais supprimé si la lecture des variantes échoue : l'écran affiche une erreur et ne modifie pas le stock.
- Ajout d'une assertion pgTAP ; le fichier `security_regression_test.sql` contient désormais 45 assertions. Les assertions restent à exécuter ; aucun test Flutter ou compte vendeur réel n'a pu être lancé ici.
- Aucune quantité de stock n'a été changée. Le ticket RIA-28 reste ouvert jusqu'à un test UI sur un compte vendeur de validation.



### AUD-05 / AUD-06 — contrôles paiements et FCM — 6 novembre 2026

- Déclenchement manuel de la même requête que la tâche Cron du moniteur : HTTP 200. Aucun paiement ou push n'a été initié.
- Wave reste `NOT_CONFIGURED` : `WAVE_API_KEY` absent. CinetPay reste `NOT_CONFIGURED` : `CINETPAY_API_KEY` et/ou `CINETPAY_SITE_ID` absent(s). Les fonctions checkout répondent 503 en l'absence de leurs clés.
- Webhooks actifs Wave v4 et CinetPay v6 : vérification HMAC (Wave sur body brut + timestamp 5 minutes ; CinetPay sur `x-token` puis vérification auprès de l'API fournisseur) avant l'appel idempotent `process_payment_event`.
- Les logs consultés dans la fenêtre par défaut comportaient 324 événements `fcm_service_account_missing`, `hasFcmProjectId=false`. Les clés Firebase serveur ne sont pas présentes.
- Migrations appliquées : `20261106201627_allow_fcm_platform_health_component` et `20261106201705_allow_fcm_health_check_component`. La fonction privée d'enregistrement demeure autorisée seulement à `service_role`, la contrainte de composant accepte désormais `FCM`.
- `platform-health-monitor` v6 avait été ajusté pour tester FCM ; il est ensuite passé en **v7** pour étendre aussi le probe Storage aux cinq buckets. Le contrôle réel HTTP 200 a enregistré les statuts Wave/CinetPay/FCM `NOT_CONFIGURED` et les autres composants testés `UP`.
- Les tests pgTAP correspondants ont été ajoutés : le fichier `security_regression_test.sql` est à 47 assertions. Les tests n'ont pas encore été exécutés.
- Les secrets marchands et Firebase restent à saisir directement dans Supabase Edge Function Secrets depuis les comptes officiels. Aucun secret n'a été lu, généré ou commité.

### AUD-16 — probe Storage étendu — 6 novembre 2026

- `platform-health-monitor` v7 teste maintenant les cinq buckets : avatars, documents, shop-media, order-feedback-media, product-media.
- Un probe manuel a reçu HTTP 200 et les cinq buckets ont répondu HTTP 200.
- Ce test n'est pas une preuve d'upload/download ou d'accès correct par rôle ; les tests avec objets factices et vérifications positives/négatives restent à faire.


### AUD-13 — Déconnexion et révocation FCM intégrées — 7 novembre 2026

- Le nouveau composant `AccountSessionActionButton` est posé sur l'accueil, les tableaux de bord vendeur, administrateur et livreur ; la page de compte suspendu/bloqué utilise aussi le service commun.
- Aucun écran ne fait directement `auth.signOut()`. La déconnexion passe par `PushNotificationService.signOutAndDeactivateCurrentDevice(client:)`.
- Si Firebase est initialisé mais que le token n'est pas en cache, le service tente de le récupérer avant de révoquer.
- La méthode attend que le RPC confirme `true` avant de vider le token et fermer la session. En cas d'échec, la session reste ouverte pour permettre une nouvelle tentative.
- La migration `20261106203915_secure_notification_device_deactivation_for_blocked_accounts` a été appliquée. La RPC est maintenant `SECURITY DEFINER` avec `auth.uid()` obligatoire, filtre strict sur `user_id` et `push_token`, token non vide, résultat idempotent qui confirme qu'aucune ligne active correspondante ne reste.
- Le SECURITY DEFINER est nécessaire car la policy `active_account_guard` de `notification_devices` empêcherait sinon un compte suspendu/bloqué de désactiver son propre token avant sa déconnexion. La fonction ne permet toujours pas de modifier le token d'un autre utilisateur.
- ACL vérifiée : `anon` sans EXECUTE ; `authenticated` et `service_role` autorisés. Propriétaire postgres et `search_path = pg_catalog, public` conservés.
- Un test pgTAP structurel supplémentaire est ajouté : `security_regression_test.sql` comporte 48 assertions. Un test Flutter vérifie le bouton lorsque Supabase n'est pas configuré.
- Pas de token ou compte réel dans la base ; les tests Flutter/pgTAP ne sont pas exécutés. Le test final sur appareil Android/iOS (push reçu, logout, aucun push post-logout, nouvelle connexion et réenregistrement du token) reste requis.


### AUD-12 — séparation des permissions ADMIN / MODERATOR — 7 novembre 2026

- Le helper `public.is_admin_actor()` reconnaissait ADMIN, SUPER_ADMIN et MODERATOR ; ce même guard protégeait auparavant plusieurs fonctions globales qui ne relèvent pas de la modération.
- Migration Supabase appliquée : `20261106204520_restrict_platform_admin_actions_to_registered_admins`.
- Les fonctions tableau de bord global, état de santé, audit/réparation/rollback plateforme et lecture/modification des règles de retour exigent maintenant `private.is_admin()` (profil actif + `admin_users.active=true`).
- Les triggers de protection des champs statut/vérification profil et validation des documents vendeur exigent aussi `private.is_admin()`. Un modérateur ne peut donc plus utiliser ces chemins pour modifier les données de sécurité de son propre profil ou les champs de validation vendeur.
- Les fonctions de file et décision de modération du catalogue et des avis conservent `public.is_admin_actor()`. Le rôle MODERATOR garde donc l'accès à ces deux activités.
- Le routeur Flutter permet à un modérateur sans ligne `admin_users` d'accéder uniquement à `/admin/catalog-moderation` et `/admin/reviews`. Les routes comptes, remboursement, santé, assistant, retour et tableau de bord exigent un administrateur actif.
- Vérification SQL après migration : les RPC sensibles référencent maintenant `private.is_admin()`; les helpers de modération continuent d'utiliser `public.is_admin_actor()`. Les ACL n'ont pas été élargies à anon. Pas de comptes/roles créés.
- Deux assertions pgTAP supplémentaires ajoutées ; `security_regression_test.sql` contient 50 assertions et le total avec l'autre fichier est 63. Les tests n'ont pas été exécutés faute de runner Actions.
- Limite restante : `admin_roles` et `admin_users.admin_role_id` ne sont toujours pas utilisés par les autorisations ; tous les administrateurs actifs ont les mêmes droits globaux. La matrice OWNER/SUPER_ADMIN, ADMIN, FINANCE, LOGISTICS_ADMIN, SUPPORT et MODERATOR est préparée dans `docs/runbooks/aud-12-admin-rbac-matrix.md`, suivi par Linear RIA-30. Aucun compte propriétaire ni associé n'a été provisionné.



### AUD-14 — GPS livreur en arrière-plan — 7 novembre 2026

- Le minuteur périodique attaché à `CourierPage` a été remplacé par `Geolocator.getPositionStream()` avec paramètres natifs. Android configure un service de premier plan et une notification persistante ; iOS active `allowBackgroundLocationUpdates` et le mode `UIBackgroundModes/location`.
- Le manifeste Android déclare ACCESS_FINE/COARSE, ACCESS_BACKGROUND_LOCATION, FOREGROUND_SERVICE et FOREGROUND_SERVICE_LOCATION. Les descriptions Always/WhenInUse iOS précisent que le GPS ne se partage que pendant une livraison active.
- Le partage commence après un consentement explicite et après vérification d'au moins une affectation active. L'écran explique la demande d'autorisation « Toujours / Autoriser tout le temps » et la notification Android. Le livreur peut arrêter manuellement.
- À la fin/annulation de la dernière mission, à l'absence d'affectation, à un refus serveur ou au démontage de la page, l'abonnement GPS est annulé. Les erreurs réseau temporaires sont signalées sans créer un deuxième flux.
- Migration Supabase appliquée : `20261106205236_require_active_courier_assignment_for_location_updates`. La RPC `record_courier_location` refuse maintenant les écritures si aucune affectation du livreur en état actif n'est reliée à un colis/commande non terminés. Aucun changement des ACL/validation des coordonnées ; `anon` reste interdit.
- Le compte projet ne contient actuellement aucune affectation et aucune position GPS. Un test Flutter est ajouté pour vérifier le refus de démarrer le suivi lorsque le livreur n'a aucune mission ; une assertion pgTAP a été ajoutée (security_regression_test.sql à 51 assertions).
- Les tests Flutter/pgTAP n'ont pas encore été exécutés faute de runner GitHub Actions. Aucun APK/IPA ni test physique Android/iOS n'a été construit ou exécuté. L'approbation des permissions de localisation par les stores reste à valider.
- Aucune politique de purge des positions GPS n'est définie. Aucun historique n'a été créé. Le ticket RIA-31 demande de définir la durée de conservation, les finalités et la purge serveur avant l'activation production.
- Runbook : `docs/runbooks/aud-14-courier-background-location.md`. Ticket RIA-11 en cours.



### AUD-15 — parité des sources Edge Functions restaurée — 7 novembre 2026

- Trois fonctions déployées n'avaient aucun fichier source dans GitHub : `expire-products` v2, `admin-health-check` v2 et `payment-webhook-gateway` v3.
- Les sources des deux fonctions actives ont été restaurées sous `supabase/functions/expire-products/` et `supabase/functions/admin-health-check/`. Le code vérifie le Bearer JWT Supabase, `admin_users.active=true` et `profiles.status='ACTIVE'`, avec refus par défaut si la vérification échoue.
- Le gateway a été versionné comme tombstone, sans logique de paiement, avec réponse HTTP 410 `legacy_endpoint_retired`.
- Déploiement Supabase vérifié après lecture des sources live : `expire-products` v3, `admin-health-check` v3, `payment-webhook-gateway` v4. Les deux premières ont `verify_jwt=true` et le contrôle profil actif ; le gateway garde `verify_jwt=false` et renvoie HTTP 410.
- Supabase a toujours 21 fonctions ; le dépôt contient désormais 21 dossiers de fonctions correspondants. Aucun endpoint supprimé/désactivé, aucun secret ou paiement réel touché.
- Le workflow Deno CI s'est déclenché mais les jobs n'ont retourné aucune étape/journal accessible. Le code live a été vérifié, mais `deno check` reste non confirmé.
- Runbook : `docs/runbooks/aud-15-edge-function-source-parity.md`.



### AUD-17 — couverture des tests commande/livraison renforcée — 7 novembre 2026

- Inventaire sur main : 6 fichiers de tests Flutter, 3 fichiers SQL pgTAP et 77 assertions déclarées au total (13 comptes de démo, 13 contrats commande/livraison, 51 sécurité).
- Nouveau fichier `supabase/tests/database/order_delivery_contract_test.sql`, 13 assertions : garde d'annulation impayée et refus paiement/expédition, libération stock/coupon, synchronisation colis/affectations/groupes/commande, propriétaire vendeur, checkout idempotent et adresse utilisateur, frais serveur/expiration/réservation stock, accès coursier, photo/code retrait, démarrage et confirmation livraison, preuve et synchro, ACL de remboursement service-role-only.
- Les 13 prédicats du nouveau fichier ont été évalués sur le schéma Supabase actif en lecture seule ; 13/13 étaient vrais au moment de la vérification.
- Cette vérification de prédicats n'est pas une exécution pgTAP. Les tests Flutter, pgTAP et les workflows CI ne sont pas encore validés par un runner avec étapes/journaux accessibles.
- Les tests complets d'intégration des paiements/webhooks, remboursement multi-vendeurs, retours, transport, mécaniciens, réservations et parcours GPS réels restent absents. Ne pas les simuler avec des écritures en production.
- Suivi Linear RIA-27 remis en cours ; critères de sortie production inchangés.



### AUD-18 — premier relevé capacité / backups / restore — 7 novembre 2026

- Snapshot de production en lecture seule : PostgreSQL 17.6.1, base environ 80 MB, `max_connections=60`, 3 slots réservés, 11 connexions clientes observées à l'instant du snapshot.
- Sur les logs PgBouncer 24 h : aucune occurrence de limite de client, client-login-timeout ou épuisement de connexions ; 71 fermetures serveur étaient des expirations idle timeout.
- Aucun deadlock, replication slot ni connexion de réplication actuellement observé. `pg_stat_archiver` a 33 222 fichiers archivés et 0 échec depuis le reset du 25 août, dernier archivage 6 novembre 21:25:50 UTC. Cet indicateur ne certifie pas un backup quotidien ou PITR restaurable.
- Base métier presque vide (0 Auth users, 0 profils, 0 produits, 0 objets Storage). Pas de dataset représentatif pour mesurer une charge réelle.
- Compute exact/plan/pooler max clients et pool size non retournés par le connecteur ; à confirmer dans Dashboard. Les limites officielles du pooler varient par compute (200 clients sur Nano/Micro jusqu'à 12 000 sur 16XL). Aucune montée de compute ni augmentation de pool n'a été faite.
- Script k6 préparé : `tests/load/k6_readonly_supabase_categories.js`. Il est lecture seule, refuse le ref de production et exige `TARGET_ENV=staging`. Il prévoit les paliers 100, 1 000 et 10 000 VUs. Aucun test n'a été lancé, aucun trafic de charge généré.
- Backups : le projet n'a pas exposé la liste des sauvegardes/restore points via les outils. Le plan reste à vérifier dans Billing. 17.6 est éligible à la sauvegarde physique Supabase, mais ne prouve pas le plan ni les backups actifs. Les objets Storage nécessitent une sauvegarde indépendante ; 0 objet actuellement.
- Restauration réelle non testée. Runbook `docs/runbooks/aud-18-capacity-backup-restore.md`. Ticket RIA-32 en attente pour tester sur staging et documenter RPO/RTO. Aucun compute, plan, backup, objet ou donnée métier n'a été modifié.


### AUD-19 — récupération email du mot de passe ajoutée — 7 novembre 2026

- Le formulaire de connexion contient maintenant le lien « Mot de passe oublié ? » qui ouvre /auth/forgot-password.
- Ce formulaire appelle resetPasswordForEmail avec redirectTo marketplaceburkina://auth/recovery et retourne un message générique qui ne révèle pas si l'adresse existe.
- Un écouteur global démarre immédiatement après Supabase.initialize() et attend AuthChangeEvent.passwordRecovery. L'écran /auth/recovery ne donne pas accès au champ du nouveau mot de passe sans cet événement et une session.
- Le nouveau mot de passe est confirmé deux fois, avec un minimum de 8 caractères, via auth.updateUser(UserAttributes(password: ...)).
- Android : filtre deeplink pour marketplaceburkina://auth/recovery. iOS : le schéma personnalisé était déjà déclaré.
- Une route alias /recovery est conservée pour les parseurs mobiles qui exposent seulement le chemin.
- Tests ajoutés : 3 tests pour le marqueur de récupération et extension du test de routes. Le dépôt comporte maintenant 7 fichiers de tests Flutter, 3 fichiers SQL pgTAP et 77 assertions déclarées.
- À faire dans Supabase Dashboard : ajouter exactement marketplaceburkina://auth/recovery dans Authentication > URL Configuration > Redirect URLs ; vérifier le Reset Password email template et le SMTP. Les outils connectés ne permettent pas de lire/modifier cette allow-list.
- Le SMTP intégré peut être limité/best-effort ; aucun SMTP payant n'a été ajouté. Aucun email réel ni compte utilisateur n'a été créé. Aucun fournisseur SMS n'a été configuré.
- OTP téléphone reporté : nécessite Twilio/MessageBird/Vonage ou autre fournisseur SMS et des frais par message ; aucune activation sans validation du coût.
- Tests réels email/lien sur Android/iOS et exécution CI restent à faire. Runbook : docs/runbooks/aud-19-email-password-recovery.md.

### AUD-20 — vérification des index non scannés — 7 novembre 2026

- Performance Advisor signale 366 unused indexes. La lecture pg_stat_user_indexes / pg_index confirme 366 index non uniques et non primaires sans scan dans public/private ; les 232 autres index public/private non scannés sont primaires/uniques et exclus des candidats.
- Les 366 candidats représentent environ 3,0 MiB ; tous les index public/private sans scan représentent 5,4 MiB. La base a environ 80 MB et la plupart des tables métier ont 0 ligne.
- Stats reset : 25 août 2026 ; dernier autoanalyze : 6 novembre. Des index sur commandes, produits, colis, GPS, messagerie, payouts, paiements et remboursements sont sans scan, parce que leurs tables sont encore vides.
- Aucun index n'a été supprimé et aucune migration DDL créée. Revoir après données staging/production et EXPLAIN ANALYZE. Runbook docs/runbooks/aud-20-unused-index-review.md.

### AUD-21 — vérification des tables RLS sans policy — 7 novembre 2026

- 17 tables sont RLS-enabled sans policy : 15 privées (ACL postgres seule) et 2 publiques médias (delivery_evidence et review_media, service_role seulement).
- has_table_privilege confirme zéro privilège direct CRUD pour anon et authenticated sur les 17 objets. Les fonctions média exposent seulement les avis PUBLISHED à l'anonyme et les preuves DELIVERY de la commande du client authentifié.
- Deux assertions pgTAP ajoutées dans security_regression_test.sql ; ce fichier contient 53 assertions. Total des 3 suites : 79 assertions.
- Aucune policy permissive ou ACL directe n'a été ajoutée ; runbook docs/runbooks/aud-21-rls-no-policy-tables.md.

### AUD-22 — audit et durcissement des fonctions SECURITY DEFINER — 7 novembre 2026

- Catalogue Supabase : 166 fonctions SECURITY DEFINER dans public/private ; 163 détenues par postgres (application), 3 C PostGIS détenues par supabase_admin. 107 exécutables authenticated, 6 anon.
- Les 163 fonctions applicatives ont toutes un search_path explicite ; 48 utilisent search_path='' ; les trois seules fonctions sans search_path sont les surcharges natives PostGIS ST_EstimatedExtent (traitées avec AUD-01/Supabase Support).
- Les six fonctions anon ont été relues : deux helpers média limités aux avis PUBLISHED, private.is_admin() vérifie utilisateur + admin actif + profil ACTIVE, et trois fonctions C PostGIS. Pas de REVOKE global.
- Un scan a identifié 3 types personnalisés non qualifiés dans trois fonctions (verification_status x2, payment_status x1). Migrations appliquées : 20261106220518 (13 fonctions : 12 RPC métier + handle_new_user) et 20261106220850 (process_payment_provider_event). Chemins explicites, pg_catalog en premier, pg_temp en dernier.
- Les fonctions conservent propriétaire et ACL EXECUTE : aucune logique métier, donnée financière, commande, paiement ou stock modifié.
- Validation live : 13/13 fonctions première migration avec chemin exact ; trigger handle_new_user réservé au service_role ; process_payment_provider_event réservé au service_role. 14 fonctions avec pg_temp en dernier ; aucun ancien chemin public / public,private non protégé ne subsiste pour les fonctions du lot.
- 3 assertions pgTAP ajoutées dans security_regression_test.sql ; 56 assertions dans ce fichier, 82 dans les trois suites prévues. Les prédicats sont vrais en lecture seule sur production ; pgTAP complet et Flutter CI ne sont pas exécutés.
- Runbook : docs/runbooks/aud-22-security-definer-search-path-review.md. Les trois fonctions PostGIS sans search_path restent à traiter uniquement après migration de l'extension par Supabase Support.

### AUD-02 — approfondissement du risque ledger et remboursement externe — 7 novembre 2026

- Contrainte unique live `uq_seller_ledger_ref_type(seller_id, entry_type, reference_id)` confirmée. `complete_refund` écrit une ligne REFUND par groupe avec `reference_id = refund_id`. Si un vendeur a plusieurs boutiques/groupes dans la même commande, plusieurs lignes peuvent partager le même triplet seller_id/type/reference et provoquer une violation d'unicité.
- L'Edge Function `execute-payment-refund` contacte Wave avant `complete_refund`. Si Wave confirme puis que le SQL ledger échoue (par exemple unicité), la transaction locale est rollback après remboursement externe réel ; Edge renvoie `refund_completion_failed` et la demande peut rester PROCESSING. Il faut un mécanisme de rapprochement interne sans relancer le prestataire.
- Le catalogue PostgreSQL ne montre aucun appelant SQL, trigger ou job pg_cron des deux finaliseurs vendeur (`finalize_seller_group`, `finalize_seller_group_financials`) ou de `reverse_seller_group`. Recherche code `main` : aucune référence dans Flutter/Edge, uniquement définitions SQL et documentation. Des appelants externes non présents au repo restent à confirmer.
- L'écran client `OrderDetailsPage` ne propose que montant global XOF + motif. Aucun choix boutique/article/quantité, le retour `returns` ne conserve aucune quantité et ne référence aucun refund.
- Tous les comptes métier restent nuls : commandes 0, groupes 0, lignes 0, paiements 0, remboursements 0, retours 0, commissions 0, ledger 0. Aucun risque financier réel n'a été touché dans cet audit.
- Runbook AUD-02 enrichi avec les risques d'unicité et de rapprochement fournisseur. Aucune migration ou fonction financière n'est appliquée ; règles coupon/livraison/commission et convention canonique du ledger à valider sur staging.

### AUD-02 / AUD-03 — capture Wave après annulation et ledger — 7 novembre 2026

- Le chemin `process_payment_event` pour une capture reçue après commande CANCELLED crée une demande refund REQUESTED de la partie payée restante ; aucune vente n'est finalisée dans ce chemin.
- `complete_refund` n'exige pas la présence d'un crédit SALE et écrit néanmoins des lignes REFUND négatives sur chaque order_group ; il peut donc créer une dette seller sans vente créditée. Au remboursement total, il exclut CANCELLED dans l'UPDATE de la commande parent, mais marque tous les order_groups REFUNDED, créant une incohérence parent/enfants.
- Un index unique `uq_seller_ledger_ref_type(seller_id,entry_type,reference_id)` rend aussi vulnérable le remboursement d'une commande comportant plusieurs boutiques appartenant au même vendeur, puisque complete_refund écrit une ligne REFUND par groupe avec refund_id comme référence.
- Wave refund est appelé avant l'écriture ledger ; si cette écriture échoue, fournisseur remboursé mais transaction DB rollback, demande locale peut rester PROCESSING. Ajouter un état de rapprochement sans répéter l'appel fournisseur.
- Runbook AUD-02 et registre mis à jour. Code financier de production non modifié. Zéro ligne de commande, paiement, refund, retour, commission, seller ledger en base au moment des vérifications.

### AUD-05 — précontrôle du fournisseur avant checkout — 7 novembre 2026

- Les secrets restent absents : dernier moniteur 6 novembre 22:20:04 UTC : Wave NOT_CONFIGURED, CinetPay NOT_CONFIGURED. Aucun KYC marchand ou secret n'a été ajouté.
- Nouvelle Edge Function `check-payment-provider-config` v1 déployée, `verify_jwt=true`. Elle exige la présence API key + webhook secret Wave, ou API key + site ID + secret key CinetPay. Elle ne renvoie que `provider`, `configured`, `status`, jamais les valeurs de secrets.
- Checkout Flutter appelle maintenant ce précontrôle AVANT `checkout_cart`. Si les identifiants server-side du fournisseur choisi manquent, la commande n'est pas créée et le stock n'est pas réservé.
- Classe `PaymentProviderAvailability` ajoutée avec validation stricte de la réponse ; 4 tests unitaires testent l'état configuré/non configuré, normalisation et réponses incohérentes.
- Le précontrôle valide uniquement la présence de secrets, pas l'activation marchande/KYC, le solde ou le fonctionnement du webhook. Test sandbox et test paiement réels restent interdits tant que les comptes ne sont pas activés.
- Runbook AUD-05/06 et docs/payment-integration.md mis à jour. Rien n'a été débité, aucun ordre n'a été créé.

### AUD-06 — dernier état FCM — 7 novembre 2026

- Dernier état live de `private.platform_health_checks` (6 novembre 22:20:04 UTC) : FCM NOT_CONFIGURED, `FCM_SERVICE_ACCOUNT_JSON_missing`, `has_fcm_project_id=false`.
- Logs des dernières 24 h observées : 450 événements `fcm_service_account_missing` dans function_logs. Aucun push réel n'a été envoyé.
- Firebase projet, APNs et service account restent à configurer par le propriétaire dans leurs consoles ; aucune clé n'a été copiée ou modifiée.

### AUD-17 — inventaire tests mis à jour — 7 novembre 2026

- Le dépôt comporte maintenant 8 fichiers de tests Flutter : le nouveau `payment_provider_availability_test.dart` contient 4 tests du contrat de réponse de précontrôle.
- 3 suites pgTAP planifient toujours 82 assertions au total (56 + 13 + 13). Tests Flutter/pgTAP/Deno non confirmés par CI, les runs ne démarrent pas d'étapes.

### AUD-07 — réparer uniquement l'historique de migration — 7 novembre 2026

- Comparaison exacte des timestamps : GitHub 333 migrations, Supabase 332. Unique version locale absente du remote : `20261104020500` (`add_toy_weapon_product_classification.sql`). Aucun autre écart.
- Le fichier crée `private.scan_toy_weapon_products()` et un job cron ; les deux effets existent déjà à l'identique dans Supabase. La fonction est détenue par postgres, SECURITY DEFINER, search_path vide, EXECUTE uniquement postgres. Le job `toy-weapon-classifier` est actif (jobid 5, */10 * * * *, même commande), tables dépendantes présentes.
- Important : ne pas rejouer le SQL de cette migration car il contient `cron.unschedule` puis `cron.schedule` et remplacerait le job existant.
- Workflow manuel préparé `.github/workflows/repair-aud-07-migration-history.yml`, utilisant la CLI Supabase 2.122.1. Il refuse une autre branche, exige la confirmation exacte `REPAIR-HISTORY-20261104020500`, et n'exécute que `supabase migration repair 20261104020500 --status applied`, puis liste l'historique.
- Les secrets `SUPABASE_ACCESS_TOKEN` et `SUPABASE_DB_PASSWORD` doivent être fournis directement dans GitHub Actions > Repository secrets. Ils ne sont pas disponibles à l'agent.
- Workflow préparé mais non déclenché ; l'historique reste 333/332 jusqu'à son lancement par le propriétaire. Aucune insertion manuelle dans `supabase_migrations.schema_migrations`, aucune fonction/cron appelée.
- Runbook : `docs/runbooks/aud-07-reconcile-toy-weapon-migration-history.md`.
