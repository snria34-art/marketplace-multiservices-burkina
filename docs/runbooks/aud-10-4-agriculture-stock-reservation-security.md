# AUD-10.4 — Annonces agricoles, commandes et réservation de stock

**Projet :** Marketplace Multiservices Burkina  
**Dépôt :** \`adjasanou49-max/marketplace-multiservices-burkina\`, branche \`main\`  
**Base Supabase :** \`dzhhsoikzxibmngjzcch\`  
**Migrations :**
- \`20261107001842_secure_agriculture_listing_and_stock_reservation_workflow\`
- \`20261107002105_harden_agriculture_order_acceptance_and_fulfillment\`
- \`20261107002124_minimize_public_agriculture_catalog_seller_identity\`
- \`20261107002316_minimize_public_agriculture_catalog_stock_and_seller_ids\`
- 20261107002512_move_agriculture_catalog_definer_to_private

**État :** backend appliqué ; Flutter raccordé ; contrôles SQL de structure/droits et appels sans session réussis ; essais métier multi-comptes et compilation Flutter encore non exécutés.

## 1. Diagnostic confirmé

- La table \`agriculture_listings\` existait mais ne possédait pas de stock réservé ni de table de commandes.
- Les annonces publiques étaient visibles dès qu'elles étaient actives, sans vérifier le statut du vendeur.
- Les vendeurs ne pouvaient pas gérer leurs annonces agricoles depuis ce vertical Flutter ; l'écran n'avait pas d'action de commande.
- Le parcours commerce classique ne pouvait pas être réutilisé directement : \`order_items.product_id\` référence \`products\`, tandis que le produit agricole est dans \`agriculture_listings\`.
- Les tables agricoles et vendeurs étaient vides au moment de l'inspection. Aucun compte ni listing de démonstration n'a été créé.

## 2. Catalogue et protection des vendeurs

- Le vendeur public doit avoir un statut \`VERIFIED\` et son profil doit rester \`ACTIVE\`.
- Un helper \`private.is_verified_active_seller(uuid)\` vérifie ces deux conditions.
- L'accès anonyme direct à \`sellers\` est limité à \`id\`, \`business_name\` et \`verification_status\`. Les colonnes \`user_id\` et \`business_phone\` ne sont pas accessibles à \`anon\`.
- Les clients authentifiés ne reçoivent pas une policy générale sur les vendeurs, ce qui évite de révéler les champs privés des autres comptes.
- Le catalogue passe par get_public_agriculture_listings(), une RPC publique SECURITY INVOKER qui délègue à private.get_public_agriculture_listings_internal(), fonction de lecture privilégiée non exposée dans le schéma public. Elle retourne uniquement les champs publics : identifiant de l'annonce, nom de l'entreprise, catégorie, nom, description, prix, unité, quantité disponible, visibilité et date. Elle ne retourne ni identifiant vendeur, ni nombre réservé, ni téléphone, ni identifiant utilisateur. Cette séparation évite d'exposer une RPC publique SECURITY DEFINER à anon.
- Les listes directes d'annonces restent filtrées par vendeur vérifié.

## 3. Stock et modèle de commande

Une colonne \`reserved_quantity\` a été ajoutée à \`agriculture_listings\`, avec contraintes :
- quantité réservée non négative ;
- quantité réservée ne dépassant pas le stock total.

Une table \`agriculture_order_requests\` a été ajoutée avec demandeur, vendeur, annonce, nom/catégorie du produit capturés, quantité, unité, prix unitaire, total XOF, statut et horodatages.

Statuts : \`REQUESTED\`, \`ACCEPTED\`, \`REJECTED\`, \`CANCELLED\`, \`FULFILLED\`.

Cycle de stock :
1. À la demande, le serveur verrouille la ligne de l'annonce et le vendeur, vérifie le stock libre puis augmente \`reserved_quantity\` et crée la demande dans la même transaction.
2. Le vendeur accepte : la quantité reste réservée. Il refuse : la réservation est libérée.
3. Le client annule une demande en attente ou acceptée : la réservation est libérée.
4. Le vendeur marque la remise effectuée : le serveur réduit à la fois le stock total et le stock réservé, puis clôture la demande.
5. Le vendeur ne peut pas réduire son stock en dessous des réservations déjà détenues.

La réservation est protégée par verrouillage transactionnel de la ligne d'annonce. Les contrôles de disponibilité et transitions vendeur/client utilisent des verrous de lignes pour éviter les doubles réservations et les courses.

## 4. RPC ajoutées

- \`create_agriculture_listing\` : publication par vendeur actif et vérifié ; vendeur dérivé de \`auth.uid()\`.
- \`update_agriculture_listing\` : modification par le propriétaire du listing ; stock ne pouvant descendre sous le stock réservé.
- \`get_my_agriculture_listings\` : gestion des annonces du vendeur courant avec stock total, réservé et libre.
- \`create_agriculture_order_request\` : réservation atomique pour un client actif ; prix et unité capturés depuis le listing.
- \`cancel_agriculture_order_request\` : annulation par le demandeur et libération du stock.
- \`get_my_agriculture_order_requests\` : commandes du client courant.
- \`get_seller_agriculture_order_requests\` : boîte de réception des demandes des propres annonces du vendeur ; aucun UUID client n'est renvoyé.
- \`respond_agriculture_order_request\` : acceptation/refus par le propriétaire ; refus libère le stock.
- \`fulfill_agriculture_order_request\` : clôture d'une commande acceptée et déduction du stock.

Les neuf RPC sont SECURITY DEFINER, possédées par \`postgres\`, utilisent \`search_path\` vide et sont exécutables uniquement par \`authenticated\`. Aucun privilège direct d'écriture n'est accordé aux clients sur les annonces ou les commandes.

## 5. Interface Flutter

Fichiers modifiés :
- \`lib/features/verticals/data/vertical_repository.dart\`
- \`lib/features/verticals/presentation/vertical_discovery_page.dart\`

Fonctionnalités raccordées :
- catalogue agricole avec vendeur public et stock libre ;
- bouton \`Commander\` ;
- demande de quantité décimale, avec contrôle local du stock disponible et contrôle serveur autoritaire ;
- \`Mes commandes agricoles\`, état de la commande et annulation ;
- \`Commandes agricoles reçues\` pour le vendeur, accepter/refuser et marquer la remise effectuée ;
- \`Mes annonces agricoles\`, publication et modification du nom, catégorie, description, prix, unité, quantité et visibilité.

## 6. Limites de paiement et validation

- Aucun paiement Mobile Money, acompte ou débit n'est déclenché par ce workflow.
- \`FULFILLED\` signifie que le vendeur marque la remise/commande comme honorée et que le stock est consommé dans l'inventaire. Cela ne certifie pas un paiement.
- La livraison GPS, l'expédition, le chat acheteur-vendeur, les notifications et l'intégration au grand livre financier ne sont pas inclus dans cette correction.
- Le fichier \`supabase/tests/database/agriculture_stock_reservation_security_test.sql\` prévoit 25 assertions pgTAP ; il n'a pas été exécuté car pgTAP n'est pas installé sur la base hébergée.
- Les contrôles SQL live de droits, RLS, RPC, catalogue public et exécution des gardes sans session ont réussi. Aucun listing, vendeur ou compte de test n'a été créé.
- \`dart format\`, \`flutter analyze\`, tests Flutter et build mobile ne sont pas validés ; les jobs GitHub Actions se terminent actuellement sans runner attribué (\`runner_id=0\`, aucune étape exécutée).

Ces limites doivent être levées avant de qualifier ce vertical de prêt pour une exploitation commerciale complète.
