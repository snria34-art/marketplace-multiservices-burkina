# Architecture SaaS multi-boutiques

Date : 5 novembre 2026

## État du modèle existant

- Un compte vendeur possède un profil dans public.sellers.
- public.shops.seller_id n'est pas unique : un vendeur peut déjà posséder plusieurs boutiques.
- public.shops.normalized_name est unique : les noms normalisés des boutiques sont réservés globalement.
- Le partage d'accès par boutique existe dans private.seller_access_requests, avec approbation administrative, expiration, audit et quelques scopes de lecture.
- Le flux de partage actuel cible un utilisateur qui possède déjà un compte actif. Il ne fournit pas encore un véritable système d'invitation par e-mail ni un RBAC complet d'employés.
- Aucun catalogue de plans, abonnement vendeur, quota commercial de boutiques ou allocation payée d'emplacements n'a été identifié dans le schéma inspecté.

## Modèle de données cible

### seller_plans

Catalogue contrôlé par la plateforme :
- id, code unique, name, description ;
- price_xof, billing_interval (MONTHLY, QUARTERLY, YEARLY) ;
- included_shop_slots, max_staff_per_shop ;
- feature_flags JSON validé côté serveur ;
- active, sort_order, created_at, updated_at.

Les prix et limites sont des valeurs serveur. Le client ne peut ni créer ni modifier un plan.

### seller_subscriptions

Abonnement au niveau du profil vendeur :
- id, seller_id, plan_id ;
- status (PENDING_PAYMENT, TRIALING, ACTIVE, PAST_DUE, SUSPENDED, CANCELLED, EXPIRED) ;
- purchased_shop_slots, current_period_start, current_period_end ;
- cancel_at_period_end, provider, provider_reference ;
- created_at, updated_at.

Un vendeur ne doit pas pouvoir créer lui-même un abonnement ACTIVE. Le passage à ACTIVE doit provenir d'un webhook fournisseur vérifié ou d'une opération administrative auditée.

### shop_subscription_allocations

Allocation d'un emplacement payé à une boutique :
- id, subscription_id, seller_id, shop_id ;
- status (ACTIVE, RELEASED) ;
- allocated_at, released_at ;
- unique(shop_id) pour empêcher qu'une boutique consomme deux emplacements actifs.

Une transaction serveur verrouille l'abonnement, compte les allocations actives et vérifie le quota avant toute allocation. Une boutique existante non allouée reste conservée mais ne peut pas recevoir de nouvelles commandes si le modèle commercial exige un emplacement actif ; les commandes et historiques restent accessibles.

### shop_invitations

Invitations à un collaborateur :
- id, shop_id, invited_email_normalized, invited_user_id nullable ;
- role_code, permission_codes ;
- invited_by, token_hash, status, expires_at, accepted_at, revoked_at.

Ne jamais stocker le jeton d'invitation en clair. L'e-mail ne doit être envoyé qu'après création serveur d'une invitation à durée limitée. L'acceptation doit exiger une session authentifiée dont l'e-mail vérifié correspond à l'e-mail invité.

### shop_memberships

Droits effectifs par boutique :
- id, shop_id, user_id, role_code, permission_codes ;
- status, invited_by, activated_at, revoked_at ;
- unique(shop_id,user_id).

Le propriétaire reste le seul à pouvoir transférer la propriété. Un membre ne peut pas s'accorder lui-même un rôle supérieur, modifier le propriétaire ou attribuer les permissions plateforme.

### subscription_events

Journal append-only des changements :
- subscription_id, actor_id, event_type ;
- old_state, new_state, provider_event_id, metadata ;
- created_at.

Les événements fournisseur doivent être idempotents via un identifiant externe unique. Les événements d'audit ne doivent pas être modifiables par les rôles clients.

## Permissions proposées par boutique

- SHOP_PROFILE_READ / SHOP_PROFILE_UPDATE
- PRODUCTS_READ / PRODUCTS_CREATE / PRODUCTS_UPDATE / PRODUCTS_ARCHIVE
- INVENTORY_READ / INVENTORY_UPDATE
- ORDERS_READ / ORDERS_FULFILL
- CUSTOMERS_READ
- PROMOTIONS_MANAGE
- REVIEWS_READ / REVIEWS_REPLY
- FINANCE_READ
- PAYOUT_REQUEST

Les permissions financières, paiements et retraits ne doivent pas être accordées par défaut. Le propriétaire approuve les droits. L'administrateur plateforme ne doit pas devenir automatiquement propriétaire d'une boutique.

## Règles RLS et RPC

1. Toutes les tables d'abonnement, invitations et audit sont protégées par RLS.
2. Les tables privées ne donnent aucun accès direct anon/authenticated.
3. Les lectures client passent par des vues/RPC qui filtrent par seller_id, shop_id et membership actif.
4. Les mutations sensibles passent par des RPC transactionnelles avec contrôle du compte actif, de la propriété et de la permission exacte.
5. Les vérifications de quota utilisent un verrou sur seller_subscriptions pour empêcher deux créations concurrentes de dépasser le quota.
6. Le serveur calcule prix, période, taxes et limites ; aucune valeur client ne peut activer un plan.
7. Révocation et expiration doivent invalider immédiatement l'accès RLS.
8. Les opérations d'abonnement et d'allocation doivent être idempotentes.
9. Le propriétaire conserve accès aux commandes et à l'historique après expiration ; seules les nouvelles opérations commerciales sont limitées.
10. Aucune permission SUPER_ADMIN ou ADMIN de la plateforme ne peut être attribuée par un vendeur.

## Tests d'acceptation obligatoires

- Un vendeur avec quota 1 ne peut pas activer une deuxième boutique.
- Un paiement vérifié qui achète deux emplacements permet deux allocations, pas trois.
- Deux demandes simultanées ne dépassent jamais le quota.
- Un paiement échoué ou un webhook non signé ne peut pas activer l'abonnement.
- Un webhook dupliqué ne double pas le quota.
- Une invitation expirée ou envoyée à un autre e-mail ne peut pas être acceptée.
- Un membre d'une boutique A ne lit ni ne modifie les données de la boutique B.
- Un membre sans FINANCE_READ ne lit ni ledger, ni commissions, ni retraits.
- La révocation d'un membre coupe immédiatement ses accès.
- Un vendeur ne peut pas attribuer un rôle plateforme.
- L'expiration ne supprime aucune commande, facture ou donnée historique.

## Séquence d'implémentation

1. Générer une migration versionnée avec Supabase CLI.
2. Créer les tables, contraintes, index, fonctions privées et politiques RLS.
3. Ajouter les RPC transactionnelles de plans, abonnements, allocation, invitations, acceptation et révocation.
4. Ajouter des tests pgTAP positifs, négatifs et concurrents.
5. Ajouter les repositories et écrans Flutter.
6. Tester sur une base locale reconstruite et une branche de développement.
7. N'appliquer à la base de production qu'après validation explicite et sauvegarde.

## Limite de cette livraison

Ce document décrit la cible et les critères de sécurité. Il ne crée aucune table, aucun abonnement, aucune invitation et ne change aucune donnée Supabase. L'implémentation attend une migration générée avec Supabase CLI et sa validation locale.
