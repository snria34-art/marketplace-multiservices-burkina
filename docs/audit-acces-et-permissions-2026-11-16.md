# Audit des accès applicatifs et des permissions — 16 novembre 2026

**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Périmètre :** revue statique de `app_router.dart`, `route_access.dart`, leurs tests Flutter et de la suite SQL `security_regression_test.sql`.  
**Limite :** aucun test Flutter/pgTAP n'a été relancé dans cette passe et aucune base distante n'a été consultée.

## 1. Contrôle des routes

Les familles de routes sensibles recensées dans le routeur sont couvertes par le contrôle de session :
- client : panier, portefeuille, checkout, commandes, livraison, favoris, achats groupés, messagerie et notifications ;
- vendeur : toutes les routes sous `/seller`, dont finances, paiements, commissions et paramètres ;
- administration : toutes les routes sous `/admin` ;
- livreur : `/courier`.

Les routes de découverte et les parcours de récupération de compte restent accessibles publiquement. Les tests existants couvrent les familles de routes, la séparation administrateur/modérateur et la classification des chemins.

## 2. Contrôle des rôles

La garde du routeur :
- exige un profil dont le statut est `ACTIVE` pour les routes protégées ;
- réserve l'administration générale à un compte présent et actif dans `admin_users` ;
- limite un modérateur non administrateur à la modération du catalogue et des avis ;
- exige à la fois le rôle `SELLER` et un profil vendeur pour `/seller` ;
- exige le rôle `COURIER` pour `/courier` ;
- échoue en mode fermé si la vérification du profil ou du rôle échoue.

**Point de vigilance :** cette garde Flutter protège la navigation et l'interface, pas les données à elle seule. Les politiques RLS et les contrôles des fonctions SQL doivent rester la frontière de sécurité effective.

## 3. Redirections après connexion

`sanitizeInternalLocation` refuse les URL absolues, les autorités externes, les chemins relatifs, les doubles slash initiaux, les antislashs, les segments de traversée `.`/`..` (y compris encodés), les séquences d'encodage invalides et les boucles vers `/auth` ou `/access-status`. Les tests couvrent déjà les principaux cas de contournement et conservent les query strings internes valides.

## 4. Permissions SQL et régressions

La suite `security_regression_test.sql` annonce 57 assertions pgTAP. La partie examinée vérifie notamment :
- la non-lecture directe de tables privées et de preuves de livraison par `anon`/`authenticated` ;
- les RPC de paiement, remboursement et notification réservées à `service_role` lorsqu'elles doivent être serveur uniquement ;
- l'accès authentifié aux opérations utilisateur et les contrôles administrateur internes ;
- la confidentialité du bucket de documents vendeurs ;
- l'absence de partage financier général et les protections contre les doubles traitements de remboursements.

La migration de phase 1 crée aussi un registre privé de rapprochement des remboursements avec RLS activé et aucun privilège direct pour les rôles API.

## 5. Résultat et actions

**Aucun contournement critique n'a été confirmé par cette revue statique.** Ce constat n'est pas une certification de sécurité : les contrôles SQL doivent être exécutés sur la tête actuelle et les politiques RLS effectives doivent être vérifiées dans une base de test.

Actions restantes :
1. Exécuter Flutter analyze et les tests ciblés de routage sur la tête actuelle.
2. Exécuter les 57 assertions pgTAP sur une base locale reconstruite depuis toutes les migrations.
3. Ajouter des tests d'intégration du routeur avec utilisateurs actifs/inactifs, administrateur, modérateur, vendeur et livreur.
4. Vérifier les RLS effectives des tables `profiles`, `admin_users`, `user_roles` et `sellers`, sans exposer de données personnelles.
5. Tester les RPC sensibles avec les rôles PostgreSQL `anon`, `authenticated` et `service_role`.

## 6. Sécurité opérationnelle

Aucun code applicatif ou SQL n'a été modifié dans cet audit. Aucun merge vers `main`, aucune migration distante, aucun déploiement et aucune opération financière n'ont été effectués.
