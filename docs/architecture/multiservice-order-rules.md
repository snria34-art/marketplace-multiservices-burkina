# Moteur de commandes multiservices : règles fonctionnelles à implémenter

Cette spécification est préparatoire. Elle ne constitue ni une migration Supabase appliquée ni une fonctionnalité activée en production.

## 1. Personnalisation de tous les plats

Le configurateur doit fonctionner pour tout type de nourriture et boisson que le restaurateur publie : riz, tô, couscous, attiéké, brochettes, poisson, viande, poulet, sandwich, burger, pizza, salade, pâtes, desserts, jus et spécialités locales. Ces exemples ne sont pas une liste fermée.

Le vendeur crée librement des groupes d'options : choix du plat/protéine, accompagnements, ingrédients, sauces, préférences et quantités. Exemples : piment, légumes, oignon, tomate, fromage, steak, œuf, mayonnaise, ketchup, sauce soja, sans sel, sans sucre, sans fromage.

Pour chaque option, le vendeur définit :
- libellé et disponibilité ;
- sélection unique ou multiple ;
- minimum et maximum de choix ;
- niveau ou quantité : peu, normal, beaucoup, 1/2/3/4 unités ;
- supplément fixe en FCFA pour chaque niveau ;
- ordre d'affichage et caractère obligatoire/facultatif.

Le vendeur peut ajouter ses propres ingrédients et tarifs sans mise à jour de l'application. Les options utilisées dans une ancienne commande restent conservées dans son historique.

Le client touche une option : le prix affiché augmente immédiatement. Il ne saisit jamais de prix. Formule : prix final = prix de base + somme des suppléments sélectionnés. Le serveur recharge les tarifs depuis la base, vérifie que les options appartiennent au produit, sont actives et respectent les limites, puis recalcule le total au panier et au paiement. Toute tentative d'envoyer un supplément arbitraire est refusée.

Les ingrédients inclus doivent être visibles. « Sans fromage » ou « sans sel » doit être un choix explicite transmis à la cuisine. Deux personnalisations différentes du même produit restent deux lignes distinctes du panier. La commande conserve un snapshot immuable des choix et prix.

## 2. Livraison restaurant : domicile, bureau ou autre lieu

Le client choisit domicile, bureau, autre lieu ou retrait sur place si disponible. Pour le bureau, il renseigne adresse, bâtiment, étage, service et repère, puis choisit une heure précise proposée par le restaurant, par exemple 12:00, 13:00 ou 14:00.

Une heure précise est une demande à confirmer, pas une promesse automatique. Le restaurant reçoit « livraison souhaitée à 12:00 » et accepte ou propose un autre créneau. Le système vérifie les heures d'ouverture, le temps de préparation, le temps de trajet, la zone desservie et la capacité déjà réservée. Les fenêtres de 30, 40, 50 minutes et de 1 à 7 heures restent distinctes des heures fixes.

## 3. Préparation des commandes non alimentaires

Le vendeur peut configurer 4 h, 24 h, 48 h ou un délai personnalisé autorisé. Le délai est figé sur le groupe vendeur au checkout. Il faut distinguer préparation, disponibilité pour enlèvement, trajet et livraison. Les commandes multi-vendeurs possèdent des délais et états indépendants.

## 4. Mécaniciens et dépannage

Le mécanicien déclare uniquement les compétences qu'il possède : motos thermiques/scooters, motos électriques, vélos, vélos électriques, voitures, utilitaires, véhicules électriques/hybrides, camions, tricycles, engins et autres équipements.

Le client ne voit que les spécialités activées par le prestataire. Il choisit le lieu : domicile, bureau, panne sur place avec position GPS et consentement, ou atelier si proposé. Il décrit le véhicule (type, marque/modèle si connu), la panne, l'urgence et peut joindre des photos.

Le mécanicien configure ses horaires, zones, capacités et tarifs indicatifs distincts : déplacement domicile, déplacement bureau, dépannage sur place, diagnostic et réparations connues. Si un problème supplémentaire est découvert, le mécanicien soumet un devis complémentaire ; le client doit l'accepter explicitement avant tout supplément. Le mécanicien ne peut pas augmenter seul le prix déjà accepté.

Après l'heure de fermeture, aucune nouvelle mission n'est proposée, sauf service d'urgence activé par le prestataire.

## 5. États de commande

États par groupe vendeur : demande en attente, acceptée, refusée, attente d'accord client sur nouveau devis/créneau, préparation, prête, livreur affecté, en livraison, livrée, annulée ou expirée.

Chaque transition est contrôlée par rôle, atomique, horodatée et idempotente. Les commandes multi-vendeurs ont des états séparés par groupe.

## 6. Refus et remboursements

Un refus avant capture du paiement ne déclenche pas de remboursement. Si le paiement est déjà capturé, le remboursement doit revenir au moyen de paiement d'origine, selon les capacités réelles du fournisseur.

Avant automatisation : allocations financières immuables par groupe vendeur, liaison paiement/remboursement/fournisseur, clé d'idempotence, webhooks signés, rapprochement et tests sandbox Wave/CinetPay. Ne jamais créditer un portefeuille fictif ni afficher « remboursé » avant confirmation du prestataire. Si le fournisseur ne permet pas l'automatisation, afficher « remboursement en traitement » et ouvrir un suivi support.

## 7. Modèle de données suggéré

- product_option_groups : produit, nom, type de sélection, min/max, obligatoire, ordre ;
- product_options : groupe, nom, supplément, actif, inclus par défaut ;
- product_option_levels : option, niveau/quantité, supplément ;
- snapshot des personnalisations dans chaque ligne de commande ;
- provider_service_capabilities : véhicule/équipement et compétence ;
- provider_service_locations : domicile, bureau, dépannage, atelier ;
- provider_service_prices : tarif de base et frais de déplacement ;
- provider_opening_hours et exceptions ;
- créneaux, capacité et réservations des restaurants ;
- événements de commande avec auteur, horodatage et motif ;
- allocations financières par groupe vendeur.

Les noms et contraintes définitifs doivent être adaptés au schéma Supabase réellement présent avant toute migration.

## 8. Sécurité, performance et tests

RLS : seul le propriétaire modifie ses options ; le client ne lit que les options publiées ; le livreur ne reçoit que les informations nécessaires à sa mission. Prix et disponibilité sont recalculés côté serveur dans une transaction. Stockage des dates en UTC, affichage Africa/Ouagadougou.

Tests obligatoires : suppléments, options inactives, limites min/max, panier avec personnalisations distinctes, vendeur fermé, créneau saturé, livraison bureau à heure fixe, compétence mécanicien incompatible, hors horaires, devis supplémentaire, double acceptation/refus, commande multi-vendeurs et remboursement idempotent.

## 9. Conditions de livraison

La réalisation exige l'inspection préalable du schéma Supabase, des écrans Flutter et des RPC existants, puis une migration additive et des tests isolés. Cette spécification seule ne modifie pas le comportement de l'application. Aucune migration distante, fusion ou publication n'est incluse.
