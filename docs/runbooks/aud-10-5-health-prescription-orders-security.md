# AUD-10.5 — Santé, ordonnances et délivrance en pharmacie

**Projet :** Marketplace Multiservices Burkina  
**Dépôt :** \`adjasanou49-max/marketplace-multiservices-burkina\`, branche \`main\`  
**Base Supabase :** \`dzhhsoikzxibmngjzcch\`

**Migrations :**
- \`20261107004702_secure_health_prescription_order_workflow\`
- \`20261107005319_restrict_health_product_catalog_to_verified_pharmacies\`

**État :** backend appliqué ; catalogue, client, pharmacie et gestion de stock raccordés dans Flutter ; contrôles SQL live de structure, droits, rôles et gardes sans session réussis. Compilation Flutter et essai métier multi-comptes non exécutés.

## 1. Diagnostic

- \`health_products\` et \`health_providers\` existaient, mais aucune table de commande santé ni de traitement d'ordonnance n'existait.
- Le contrôle initial du prestataire se limitait à \`health_providers.active/verified\` et n'exigeait pas simultanément un prestataire parent actif/vérifié, un compte profil actif et une référence de licence.
- Le catalogue utilisait un embedding relationnel direct et les tables de santé accordaient la lecture aux rôles API.
- Il n'existait pas de stock réservé, de commande, de décision de pharmacie, de preuve de remise ou de dépôt privé dédié aux ordonnances.
- Les tables produits/prestataires étaient vides lors de l'audit ; aucun compte, document, produit ou commande de démonstration n'a été créé.

## 2. Vérification pharmacie et catalogue

La fonction privée \`private.is_verified_active_health_provider(uuid,text)\` exige :
- fiche santé active et vérifiée ;
- référence de licence non vide ;
- type de prestataire requis lorsqu'il est fourni ;
- prestataire parent actif et vérifié ;
- compte du prestataire en état \`ACTIVE\`.

Le catalogue public est maintenant limité aux produits actifs des pharmacies qui satisfont ces critères. Il retourne seulement le nom commercial, nom/description du produit, prix, indicateur d'ordonnance, quantité disponible et type de prestataire ; pas d'ID du prestataire ni de référence de licence.

Les tables de santé ne sont plus directement lisibles via anon/authenticated. Le catalogue passe par une RPC publique \`SECURITY INVOKER\`, qui délègue à un lecteur privilégié privé et contrôlé. L'application ne peut pas écrire directement sur les tables médicales.

## 3. Documents d'ordonnance

Bucket \`health-prescriptions\` :
- privé (aucun URL public) ;
- taille maximum 10 Mo ;
- types JPEG/PNG seulement ;
- chemin de fichier dans le dossier UID du client ;
- envoi réservé aux comptes authentifiés actifs.

Les politiques Storage permettent :
- l'upload au propriétaire du dossier UID ;
- la lecture au client propriétaire de la demande ou à la pharmacie assignée, seulement si celle-ci reste vérifiée et active ;
- la suppression par le client seulement lorsqu'aucune demande active/protégée ne référence le document.

La pharmacie ouvre le document par URL signé limité à 300 secondes. Une URL signée émise demeure valide jusqu'à expiration ; une révocation immédiate n'est pas assurée. L'interface actuelle prend en charge une photo JPEG/PNG, pas les PDF. Le client reçoit un message indiquant ce format.

## 4. Stock et cycle de commande

Ajouts :
- \`health_products.reserved_quantity\`, non négatif et toujours inférieur ou égal au stock physique ;
- table \`health_order_requests\` avec client, produit, pharmacie, photo d'ordonnance éventuelle, quantité, prix capturé, statut, note de revue, horodatages et expiration.

États :
- \`PENDING_REVIEW\` : ordonnance envoyée, examen humain requis ;
- \`APPROVED_FOR_DISPENSING\` : ordonnance validée par la pharmacie ; produit non encore remis ;
- \`REQUESTED\` puis \`ACCEPTED\` : commande sans ordonnance, en attente puis acceptée par la pharmacie ;
- \`REJECTED\`, \`CANCELLED\`, \`EXPIRED\` : stock réservé libéré ;
- \`DISPENSED\` : remise enregistrée ; stock physique et réservation décrémentés.

La réservation est appliquée dans la transaction de création après verrouillage de la ligne produit. La pharmacie peut refuser, ce qui libère le stock. Le client peut annuler avant délivrance. La fonction d'expiration utilise \`FOR UPDATE SKIP LOCKED\` et libère le stock en concurrence maîtrisée.

**Expiration :** le nettoyage est opportuniste, appelé lors des listes et créations de commandes/produits. Aucun job cron de balayage permanent n'a été ajouté dans cette correction ; des demandes expirées peuvent rester en statut non actualisé jusqu'au prochain appel de nettoyage.

## 5. RPC et sécurité

Dix RPC publiques en mode \`SECURITY INVOKER\` :
- \`get_public_health_products\`
- \`create_health_product\`, \`update_health_product\`, \`get_my_health_products\`
- \`create_health_order_request\`, \`cancel_health_order_request\`
- \`get_my_health_order_requests\`, \`get_pharmacy_health_order_requests\`
- \`respond_health_order_request\`, \`fulfill_health_order_request\`

Elles délèguent aux fonctions internes du schéma privé. Les fonctions internes qui manipulent les données sensibles sont possédées par \`postgres\`, en \`SECURITY DEFINER\` et avec un \`search_path\` vide ; les rôles API n'ont pas de droits directs sur les tables. Les mutations et listes privées sont disponibles uniquement à \`authenticated\`. Le client ne reçoit pas le chemin du document brut ; la pharmacie reçoit le chemin qui permet uniquement la génération de son URL temporaire après autorisation Storage.

## 6. Interface Flutter

Fichiers modifiés :
- \`lib/features/verticals/data/vertical_repository.dart\`
- \`lib/features/verticals/presentation/vertical_discovery_page.dart\`

Fonctions ajoutées :
- catalogue de produits des pharmacies vérifiées ;
- bouton \`Commander\`, choix quantité, photo d'ordonnance facultative ou obligatoire selon le produit ;
- \`Mes demandes de santé\` avec statut, note pharmacie et annulation ;
- \`Demandes reçues (pharmacie)\` avec lecture temporaire ordonnance, validation/refus, acceptation/refus des demandes sans ordonnance et confirmation de remise ;
- \`Mon catalogue pharmacie\`, création/modification des produits, prix, stock, drapeau d'ordonnance et visibilité.

La validation de l'ordonnance est une action humaine de la pharmacie. L'application n'essaie pas de diagnostiquer, d'interpréter la prescription ou de décider automatiquement si un médicament doit être remis.

## 7. Paiement, conformité et validations restantes

- Aucun paiement, remboursement, Mobile Money ou frais de livraison n'est déclenché ici.
- La délivrance enregistrée \`DISPENSED\` signifie que la pharmacie déclare avoir remis le produit et que le stock est décrémenté ; ce n'est pas une preuve de paiement.
- Le contrôle de licence repose sur la référence conservée et le statut \`verified\` géré par le processus de vérification administratif existant. Cette migration ne valide pas juridiquement la licence auprès d'une autorité externe et ne crée pas d'auto-onboarding santé.
- Le test SQL \`supabase/tests/database/health_prescription_orders_security_test.sql\` prévoit 25 assertions pgTAP ; non exécuté car pgTAP n'est pas installé sur la base hébergée.
- Les contrôles SQL live de structure, de permissions, de catalogue sous anon/authenticated et de refus des RPC sans session ont réussi ; les tables de santé étaient vides.
- \`dart format\`, \`flutter analyze\`, tests Flutter et build mobile ne sont pas validés dans cet environnement. Les GitHub Actions précédentes échouaient avant l'attribution d'un runner.
- Chat/pharmacie, livraison, intégration au registre financier, audit trail clinique plus détaillé, rappels d'expiration et revue juridique locale restent à traiter avant lancement commercial.
