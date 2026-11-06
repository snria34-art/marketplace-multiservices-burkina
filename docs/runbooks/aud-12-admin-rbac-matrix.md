# AUD-12 — Matrice RBAC des administrateurs, modérateurs et associés

**Projet :** Marketplace Multiservices Burkina  
**Base :** Supabase `dzhhsoikzxibmngjzcch`  
**État au 7 novembre 2026 :** réduction des privilèges excessifs du rôle `MODERATOR` appliquée ; matrice complète des rôles `admin_roles` à concevoir/appliquer avant le provisionnement des associés. Aucun utilisateur administrateur n'a été créé.

## 1. État réellement déployé

### Helpers et tables

- `private.is_admin()` : vrai si le demandeur possède une ligne `admin_users.active = true` et un profil `ACTIVE`.
- `public.is_admin_actor()` : vrai pour un profil actif avec l'un des rôles `ADMIN`, `SUPER_ADMIN` ou `MODERATOR` dans `public.user_roles`.
- `public.admin_users` contient `user_id`, `admin_role_id`, `active`.
- `public.admin_roles` contient `id`, `name`, `description`.
- `admin_roles` et `admin_users.admin_role_id` n'étaient référencés par aucune fonction d'autorisation inspectée.
- Les rôles clients `authenticated` peuvent lire leurs propres lignes via RLS, mais n'ont pas de droits INSERT/UPDATE/DELETE sur `user_roles`, `admin_roles` ou `admin_users`. Aucun rôle d'administration n'est présent en base actuellement.

### Correction AUD-12 déjà appliquée

Migration : `20261106204520_restrict_platform_admin_actions_to_registered_admins`.

Les opérations suivantes exigent maintenant `private.is_admin()`, donc une ligne administrateur active dans `admin_users` :

- tableau de bord et métriques générales ;
- surveillance de la santé plateforme ;
- lancement, audit et rollback des réparations automatiques ;
- lecture et modification des délais de retour ;
- modifications des statuts sensibles du profil ;
- validation des champs de contrôle des documents vendeur.

Les actions de modération du catalogue et des avis conservent `public.is_admin_actor()`, afin que le rôle `MODERATOR` puisse toujours traiter ces deux files.

Le routeur Flutter suit la même limite :
- administrateur enregistré : accès aux routes `/admin/*` ;
- modérateur sans entrée `admin_users` : seulement `/admin/catalog-moderation` et `/admin/reviews` ;
- autres chemins admin refusés.

Les écrans et RPC serveur appliquent tous deux ces contrôles. Le routeur n'est jamais la seule frontière de sécurité.

## 2. Matrice de permissions recommandée

La matrice ci-dessous est la proposition de référence à utiliser pour exploiter réellement `admin_role_id`. Les permissions doivent être codées dans la base, jamais uniquement dans Flutter.

| Rôle proposé | Catalogue / avis | Comptes / vendeurs | Finance / remboursements | Livraison / logistique | Paramètres / santé / réparations | Gestion des rôles |
|---|---|---|---|---|---|---|
| `OWNER` / `SUPER_ADMIN` | Complet | Complet | Complet | Complet | Complet | Complet, y compris désignation d'un autre propriétaire sous contrôle d'audit |
| `ADMIN` | Complet | Complet | Lecture + opérations approuvées | Complet | Paramètres métier, sans réparations système | Aucun changement de propriétaire ou de super-administrateur |
| `MODERATOR` | Modérer catalogue et avis | Aucun | Aucun | Aucun | Aucun | Aucun |
| `FINANCE` | Lecture limitée au contexte du remboursement | Aucun accès aux statuts de compte/document vendeur | Remboursements, commissions, rapprochements et paiements vendeurs selon ACL dédiées | Lecture frais de livraison uniquement | Aucun | Aucun |
| `LOGISTICS_ADMIN` | Lecture limitée au contexte logistique | Aucun accès aux dossiers privés vendeur sauf besoin opérationnel | Lecture frais de livraison, pas de remboursement ni payout | Affectations, colis, suivi, livreurs et tarifs logistiques | Paramètres logistiques dédiés | Aucun |
| `SUPPORT` | Lecture contextuelle d'annonces signalées | Support et actions limitées explicitement autorisées | Aucun | Lecture état de livraison sans mutation financière | Aucun | Aucun |

**Principe propriétaire :** le rôle `OWNER` / `SUPER_ADMIN` doit recevoir toutes les permissions, y compris administration des associés, mais aucun compte ne doit être créé automatiquement par une migration ou par le seed de production. Le propriétaire initial doit être provisionné par une procédure sécurisée après création/validation de son compte Auth.

Les rôles FINANCE, LOGISTICS_ADMIN et SUPPORT peuvent correspondre aux valeurs déjà présentes dans `public.user_role`, mais ne doivent pas recevoir automatiquement de privilèges administrateur généraux. Leur autorisation doit passer par des permissions explicites et les fonctions métier dédiées.

## 3. Modèle technique cible

Créer une table privée `private.admin_role_permissions` :

- `admin_role_id uuid references public.admin_roles(id)`
- `permission_key text`
- `enabled boolean not null default true`
- `created_at timestamptz not null default now()`
- `created_by uuid`

Contrainte unique : `(admin_role_id, permission_key)`.

Créer un helper privé `private.has_admin_permission(p_permission_key text)` qui doit :
1. exiger `auth.uid()` ;
2. exiger un profil `ACTIVE` ;
3. exiger un `admin_users.active = true` ;
4. vérifier la permission explicitement affectée au `admin_role_id` de cet utilisateur ;
5. appliquer un refus par défaut si le rôle ou la permission n'existe pas ;
6. autoriser toutes les permissions seulement pour le rôle `OWNER` / `SUPER_ADMIN` selon une règle fixe, non modifiable par un simple administrateur.

Ne pas utiliser `user_roles.user_metadata` ni des métadonnées client comme source d'autorisation. Les décisions doivent rester basées sur les tables de sécurité de la base et des fonctions SECURITY DEFINER à search_path fixe.

### Permissions recommandées

Exemples de clés stables :

- `catalog.queue.read`, `catalog.finding.decide`, `reviews.queue.read`, `reviews.decide`
- `accounts.read`, `accounts.status.change`, `seller.documents.review`
- `finance.refunds.read`, `finance.refunds.approve`, `finance.refunds.reconcile`
- `finance.payouts.read`, `finance.payouts.mark_paid`, `finance.payouts.mark_failed`
- `logistics.packages.read`, `logistics.assignments.manage`, `logistics.delivery_pricing.manage`
- `platform.modules.manage`, `platform.return_policy.manage`
- `platform.health.read`, `platform.repairs.run`, `platform.repairs.rollback`
- `admin.users.manage`, `admin.roles.manage`

Chaque RPC admin doit exiger une permission précise, pas simplement `is_admin_actor()`. Les triggers doivent appliquer une autorisation correspondant au champ modifié. Les opérations de masse, sensibles ou irréversibles doivent rester réservées à l'OWNER/SUPER_ADMIN ou à une double validation.

## 4. Protections de gouvernance à ajouter

- Interdire la création de tout nouveau `OWNER` / `SUPER_ADMIN` par un administrateur ordinaire.
- Refuser la désactivation du dernier propriétaire actif.
- Exiger une nouvelle authentification/MFA pour les changements de rôle et les actions financières critiques.
- Journaliser chaque attribution/retrait de permission, modification de rôle et action sensible dans un journal immuable avec acteur, cible, avant/après, motif et timestamp.
- Ne pas permettre à un utilisateur de modifier ses propres rôles, permissions, statut de compte, statut de validation ou identité d'audit.
- Prévoir une procédure de récupération propriétaire hors ligne, documentée et journalisée, sans clé `service_role` dans le client.

## 5. Séquence de réalisation avant d'ajouter des associés

1. Valider la matrice d'accès avec le propriétaire et les règles métier.
2. Créer les tables/helpers de permissions via migrations ; aucun utilisateur n'est assigné par cette étape.
3. Ajouter les permissions à chaque RPC admin en fonction de son domaine et tester refus autorisés/interdits.
4. Ajouter les vues conditionnelles aux écrans Flutter ; les données sensibles doivent rester verrouillées par les RPC/RLS.
5. Provisionner l'OWNER initial uniquement après que son compte Auth est créé et vérifié.
6. Ajouter les associés avec le rôle minimal demandé, après contrôle du paiement et validation de l'identité.
7. Tester qu'un MODERATOR ne peut ni accéder au dashboard global, ni modifier un profil/document, ni changer un payout/remboursement, ni lancer un rollback plateforme.
8. Tester qu'un FINANCE ne peut pas modérer un catalogue, changer un compte, ni piloter la livraison.
9. Tester qu'un LOGISTICS_ADMIN ne peut pas approuver un remboursement ou modifier le solde vendeur.
10. Tester que l'OWNER peut exécuter toutes les opérations, y compris la gestion des rôles.

## 6. État de réalisation

- Analyse des helpers, ACL, rôles et appels admin : terminée.
- Séparation du rôle MODERATOR pour les réparations/santé/retours/profils/documents : appliquée et vérifiée.
- Routes de modération Flutter limitées aux deux files de modération : appliquées.
- Rôle `admin_role_id` et permissions granulaires : non implémentés ; décision métier et migrations dédiées restantes.
- Aucun compte propriétaire, administrateur, modérateur ou associé n'a été créé dans la base hébergée pendant ce travail.
- Tests pgTAP / Flutter non exécutés faute de runner CI.
