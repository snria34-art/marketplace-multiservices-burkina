# Audit ciblé — paramètres globaux et mobilité

**Date :** 28 novembre 2026  
**Dépôt inspecté :** `snria34-art/marketplace-multiservices-burkina`  
**Référence de départ :** PR #6, branche `feature/customer-orders-experience-20261127`, commit `d2682a0f3b10d01061deb02ee1e294419e26a90a`.  
**Portée :** inspection statique GitHub du code et des migrations. Les fichiers locaux non commités de Cloud Shell ne sont pas accessibles dans cette inspection.

## Résumé exécutif

Le dépôt ne part pas de zéro : le socle de catégories, de prestataires, de véhicules, de demandes de trajet, de transport interurbain et de location est déjà présent dans PostgreSQL. En revanche, le produit Flutter n'expose pas encore un parcours unifié et complet de gestion de tous ces prestataires.

Les écarts les plus visibles sont :
1. absence d'un écran d'administration dédié aux paramètres globaux, malgré les tables `platform_settings`, `feature_flags`, `service_categories` et `service_category_fields` ;
2. le parcours Taxi/Moto permet de demander un trajet et de consulter ses propres demandes, mais n'affiche pas un vrai catalogue de chauffeurs/prestataires disponibles ;
3. aucune interface Flutter dédiée à l'inscription et à la gestion de flotte des compagnies, conducteurs et propriétaires de véhicules n'a été trouvée dans les routes et pages inspectées ;
4. transport interurbain dispose d'un écran client de départs et de billets, mais le parcours entreprise (compagnie, agences, lignes, flotte, conducteurs, horaires, tarifs et contrôle d'embarquement) n'est pas démontré dans l'interface inspectée.

## 1. Ce qui existe déjà

### Paramètres et administration
- `platform_settings(key,value,updated_by,updated_at)` et `feature_flags` existent depuis la migration de configuration plateforme.
- Les catégories dynamiques et leurs champs existent : `service_categories` et `service_category_fields`.
- Les modules marketplace existent dans `marketplace_modules`, avec activation/désactivation sécurisée par `admin_set_marketplace_module_enabled`.
- Le tableau de bord administrateur affiche les métriques et permet d'activer/désactiver les modules.
- L'accès administrateur est contrôlé par le route guard et `private.is_admin()`.

### Prestataires et mobilité
- `service_providers` contient un propriétaire utilisateur, un type de prestataire, un nom public, une description, un statut de vérification et un état actif.
- `provider_vehicles` et `vehicle_inspections` constituent une base de flotte et d'inspection générique.
- `vehicle_rentals` et `vehicle_rental_bookings` couvrent la publication et la réservation de véhicules de location ; la RPC de réservation vérifie notamment la période, l'activité, la vérification du loueur et les chevauchements.
- `ride_requests` et `ride_assignments` représentent les demandes de taxi et leurs affectations.
- `transport_companies`, `transport_stations`, `transport_routes`, `transport_vehicles`, `transport_trips`, `transport_drivers`, `transport_bookings`, `transport_tickets`, les sièges et les contrôles d'embarquement forment un socle interurbain.
- Les rôles `SERVICE_PROVIDER`, `DRIVER` et `TRANSPORT_COMPANY` sont définis.

## 2. Lacunes observées dans l'interface

### Taxis, moto-taxis et chauffeurs
- `VerticalDiscoveryPage` traite `rides` comme une demande de trajet : point de départ et destination, puis appel à `create_ride_request`.
- La configuration `rides` de `VerticalRepository` lit `ride_requests` propres au client. Elle ne présente pas une liste de chauffeurs vérifiés avec véhicule, disponibilité, tarif estimatif, distance et note.
- La table `ride_assignments` prévoit `OFFERED/ACCEPTED/REJECTED/COMPLETED`, mais le parcours fournisseur pour accepter/refuser, suivre l'approche, démarrer et terminer une course n'est pas exposé dans la page client inspectée.
- Les variantes taxi, moto-taxi, VTC/chauffeur privé et transport adapté ne sont pas encore exposées comme un catalogue structuré et administrable dans l'interface consultée.

### Propriétaires et loueurs de véhicules
- La recherche et la réservation client sont présentes via `vehicle_rentals`.
- Le dépôt comporte une table de flotte générique, mais aucun parcours Flutter complet de création/édition de véhicule, dépôt des documents, contrôle d'assurance/visite technique, calendrier de disponibilité, règles de caution et gestion des réservations du loueur n'a été confirmé dans les fichiers inspectés.

### Compagnies de transport et bus
- `TransportPage` affiche les départs programmés et les billets du client.
- Les tables de compagnies, gares, lignes, véhicules, conducteurs, trajets, sièges et billets existent.
- Les écrans de gestion des compagnies et des conducteurs, la création de ligne, le calendrier, l'assignation véhicule-chauffeur, la gestion des sièges, les annulations et le contrôle complet d'embarquement restent à vérifier/compléter dans l'interface.

### Fret, logistique et livraison
- `freight_requests` et `freight_quotes` existent ; le module Colis, les livreurs et le suivi de livraison ont aussi leur propre socle.
- Il faut réunir les offres de transporteurs, le suivi de mission, les preuves, les incidents, les tarifs par zone/poids/volume et le règlement des litiges dans un parcours cohérent.

## 3. Paramètres globaux

Le schéma de paramètres était présent, mais aucune page admin dédiée n'était raccordée aux routes inspectées. Le tableau de bord gérait surtout l'activation des modules ; les paramètres vendeur étaient séparés.

Une première tranche isolée est préparée dans la branche de travail :
- identité publique de la marketplace (nom ; Burkina Faso, XOF, français et fuseau Africa/Ouagadougou verrouillés) ;
- contacts support (téléphone, WhatsApp, e-mail), avec validation serveur ;
- annonce publique (activation, titre, message et niveau), avec validation et limites de longueur serveur ;
- lecture publique strictement limitée à ces trois clés ;
- journal d'audit des modifications ;
- aucune clé de commission, frais ou fournisseur de paiement n'est exposée par la RPC.

Cette première tranche n'ajoute pas de sélecteur Wave/CinetPay et ne modifie aucune logique de paiement. L'annonce est fournie par une RPC publique sûre ; son affichage dans les écrans clients reste une étape d'intégration séparée.

## 4. Architecture recommandée pour la suite mobilité

1. **Référentiel prestataire commun :** profil prestataire, statut KYC, contact, ville/zone, catégories de service, horaires et disponibilité.
2. **Sous-profils par métier :** taxi, moto-taxi, VTC/chauffeur privé, location de voitures/motos, compagnie de bus, transport de marchandises et coursier.
3. **Véhicules et conformité :** type, marque, modèle, immatriculation, capacité, photos, carte grise, assurance, visite technique, permis conducteur et dates d'expiration ; documents privés, accès restreint et tâches de revue admin.
4. **Catalogue client :** filtres par ville, zone, type de véhicule, capacité, disponibilité, note, prix estimatif et délai de prise en charge.
5. **Réservation et dispatch :** demande, offre, acceptation/refus, expiration d'offre, affectation atomique, arrivée, début, fin, preuve et historique horodaté.
6. **Tarification transparente :** tarif de base, distance/temps, zones, minimum de course, frais d'attente, devis fret, caution location ; règles en XOF et affichage du total avant confirmation.
7. **Sécurité :** RLS par propriétaire/prestataire/compagnie/client, RPC transactionnelles, contrôle de capacité, anti-double réservation, idempotence, journal d'audit et accès GPS seulement pendant la mission avec consentement.
8. **Confiance :** notes et commentaires après mission terminée, signalement, incidents, support, annulation/no-show et politique de remboursement conforme aux règles existantes.
9. **Administration :** validation des prestataires et documents, suspension, zones, catégories, commissions et paramètres par métier, avec historique. Les règles financières ne doivent pas être modifiées sans tests comptables dédiés et accord séparé.
10. **Tests :** pgTAP RLS/RPC, tests Flutter des formulaires, concurrence d'affectation et de réservation, expirations, annulations, réseau faible et scénarios multi-rôles.

## 5. Ordre recommandé de livraison

- **P0 — Paramètres centraux :** écran admin, contact support, annonce publique, configuration des catégories et journal d'audit.
- **P1 — Onboarding prestataires :** demande d'inscription, type de prestataire, dépôt privé des justificatifs et revue admin.
- **P2 — Flotte :** véhicules, conducteurs, documents, disponibilité et zones.
- **P3 — Taxi/Moto/VTC :** catalogue de chauffeurs, devis, dispatch, mission et suivi.
- **P4 — Location :** calendrier propriétaire, disponibilité, cautions, contrats et restitution.
- **P5 — Bus/interurbain :** gestion entreprise, agences, lignes, horaires, flotte, sièges et billets/QR.
- **P6 — Fret et coursiers :** devis transporteur, suivi, preuve, incidents et facturation.
- **P7 — Qualité :** avis, modération, analytics, tests charge/restauration et audit de sécurité final.

## 6. Évolution ajoutée après le premier audit : inscription prestataire

Une première étape d'onboarding est maintenant présente sur la branche de travail :
- entrée « Devenir prestataire » depuis la page Services ;
- formulaire authentifié pour Taxi, Moto-taxi, VTC/chauffeur privé, location de véhicules, compagnie de transport/bus, fret et coursier ;
- RPC serveur qui exige un profil actif, applique une liste blanche des types, valide les longueurs et refuse les doublons ;
- création du profil avec vérification `PENDING` et `active=false` ; attribution contrôlée du rôle `SERVICE_PROVIDER` ;
- aucun document sensible n'est encore téléversé et aucun prestataire n'est publié automatiquement.

**Limite fonctionnelle majeure :** l'interface de revue/approbation administrative, le dépôt sécurisé des pièces (identité, permis, carte grise, assurance, visite technique), la gestion de flotte et les commandes de missions restent à développer. Tant que cette revue n'est pas livrée et testée, le parcours d'inscription ne constitue pas un onboarding complet de production.

## 7. Limites et éléments non vérifiés

- Audit statique du contenu disponible via GitHub ; les changements non commités de Cloud Shell n'ont pas été lus.
- Aucun accès à une base Supabase distante, aucune donnée n'a été modifiée et aucune migration n'a été appliquée à un environnement.
- Aucun build Flutter, analyse Dart, test pgTAP ou test E2E n'a été exécuté dans cette exécution.
- Les validations CI de la branche de travail doivent être consultées avant toute fusion.
- L'audit global du 7 novembre reste pertinent pour les sujets paiements/remboursements, notifications Firebase, configuration des secrets, tests de charge, restauration et livraison native ; son état live ne doit pas être considéré comme actuel sans nouvelle mesure.
