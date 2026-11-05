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
- Limite restante : le scope `financial_read` est encore accepté par la fonction de demande, mais ne donne plus de visibilité financière via ces politiques. Il faudra retirer ce scope de la RPC et de l'interface après inspection de ses dépendances.
- Aucun solde, paiement, remboursement ou écriture du registre n'a été modifié. Aucun test avec de vrais fonds n'a été effectué.


### Retrait du scope financier des nouvelles demandes — 6 novembre 2026

- Migration distante `20261105184743_remove_financial_read_from_seller_access_requests` appliquée au projet Supabase actif.
- La RPC `submit_seller_access_request` n'accepte plus que `shop_profile`, `products`, `inventory_read` et `orders_read`. Une nouvelle demande contenant `financial_read` est rejetée.
- Le fichier SQL est versionné dans `supabase/migrations/20261105184743_remove_financial_read_from_seller_access_requests.sql`.
- Les demandes historiques peuvent encore contenir la valeur ancienne, mais les politiques de lecture financière partagée ont déjà été supprimées : ces anciennes autorisations ne donnent plus accès aux tables financières.
- Les migrations ont été appliquées et les fichiers SQL enregistrés. Les tests d'intégration automatisés n'ont pas encore pu être exécutés, car les runners GitHub Actions du dépôt ne s'attribuent pas (`runner_id=0`).
