# AUD-10.3 — Workflow sécurisé des professionnels et des devis

**Projet :** Marketplace Multiservices Burkina  
**Dépôt :** \`adjasanou49-max/marketplace-multiservices-burkina\`, branche \`main\`  
**Base Supabase :** \`dzhhsoikzxibmngjzcch\`  
**Migration :** \`20261107001015_secure_professional_quote_request_workflow\`  
**État :** migration appliquée ; Flutter raccordé ; contrôles de droits et de structure live réussis ; compilation Flutter et essais multi-comptes encore non exécutés.

## 1. Diagnostic confirmé

- \`professional_profiles\` était lisible par \`anon\` dès lors que \`active=true\`, sans contrôle du statut de vérification du prestataire.
- Le catalogue Flutter tentait d'embarquer \`service_providers(display_name)\`, alors que les visiteurs anonymes n'avaient aucun droit de lecture sur cette table : ce chemin de requête pouvait échouer pour les visiteurs.
- Les tables génériques \`service_requests\` et \`service_quotes\` existaient déjà, mais elles ne pouvaient pas cibler directement \`professional_profiles\`.
- Les clients ne disposaient pas d'un parcours Flutter complet pour envoyer une demande de devis, consulter les offres et les accepter/refuser ; les prestataires ne disposaient pas d'une boîte de réception professionnelle raccordée.
- Les tables \`professional_profiles\`, \`services\`, \`service_requests\`, \`service_quotes\` et \`service_bookings\` étaient vides au moment de l'inspection. Aucun compte ni profil fictif n'a été créé.

## 2. Catalogue public et moindre privilège

- La policy publique du profil professionnel exige maintenant \`professional_profiles.active=true\` et un prestataire lié à la fois actif et vérifié.
- \`anon\` reçoit uniquement des privilèges SELECT par colonne sur \`service_providers.id\`, \`display_name\`, \`active\` et \`verification_status\`.
- Une policy dédiée \`anon\` ne rend visibles que les prestataires actifs et vérifiés.
- Les colonnes \`user_id\`, \`provider_type\` et \`description\` restent non lisibles par \`anon\`. Le catalogue peut donc afficher un nom public sans exposer l'identifiant utilisateur ou les champs internes.

## 3. Réutilisation des demandes et devis existants

La migration étend \`service_requests\` au lieu de créer un second moteur de devis :
- \`service_id\` devient nullable pour les seules demandes ciblant un profil professionnel ;
- ajout de \`professional_profile_id\` et d'une clé étrangère ;
- contrainte qui impose exactement une cible : service générique ou profil professionnel ;
- index pour retrouver les demandes d'un profil professionnel par statut et date.

La table \`service_quotes\` est réutilisée :
- ajout de \`message\` pour expliquer le devis ;
- longueur limitée à 1 000 caractères ;
- index unique partiel qui empêche deux devis \`PROPOSED\` simultanés du même prestataire pour une demande.

Les droits directs INSERT/UPDATE/DELETE des clients sur \`service_requests\` et \`service_quotes\` sont retirés. Les écritures passent par les RPC d'autorisation.

## 4. Contrat des six RPC

- \`create_professional_service_request(uuid,text,timestamptz)\` : demande créée pour un profil actif et un prestataire actif/vérifié ; demandeur tiré de \`auth.uid()\` ; description requise (2 000 caractères maximum) ; date souhaitée facultative et future (maximum 180 jours) ; refus de sa propre prestation.
- \`cancel_professional_service_request(uuid)\` : le demandeur peut annuler sa demande tant qu'elle est \`REQUESTED\` ou \`QUOTED\` ; les devis proposés sont expirés.
- \`get_my_professional_service_requests()\` : demandes du client courant avec historique des devis.
- \`get_provider_professional_service_requests()\` : demandes du professionnel courant, filtrées par le propriétaire réel du profil ; aucun UUID client n'est retourné.
- \`create_professional_service_quote(uuid,numeric,text)\` : seul le propriétaire d'un profil actif et vérifié peut proposer un devis à une demande \`REQUESTED\` ; montant non négatif en XOF ; commentaire facultatif (1 000 caractères maximum) ; une seule proposition active.
- \`respond_professional_service_quote(uuid,text)\` : le client propriétaire de la demande peut accepter ou refuser un devis \`PROPOSED\`. L'acceptation passe la demande à \`ACCEPTED\`; le refus remet la demande à \`REQUESTED\` pour permettre une nouvelle offre.

Les RPC sont SECURITY DEFINER, possédées par \`postgres\`, utilisent un \`search_path\` vide, sont exécutables uniquement par \`authenticated\`, et ne sont pas exécutables par \`anon\` ou \`PUBLIC\`. Les transitions verrouillent les lignes du profil, du prestataire, de la demande et du devis lorsque nécessaire.

## 5. Interface Flutter

Fichiers raccordés :
- \`lib/features/verticals/data/vertical_repository.dart\`
- \`lib/features/verticals/presentation/vertical_discovery_page.dart\`

Le parcours propose :
- catalogue public avec nom affichable du prestataire, sans champ privé ;
- bouton \`Demander un devis\` ;
- formulaire décrivant le besoin et date souhaitée facultative ;
- écran client \`Mes demandes professionnelles\`, historique des devis, annulation avant acceptation, acceptation ou refus ;
- écran professionnel \`Demandes professionnelles reçues\`, création d'un devis avec montant XOF et commentaire.

**Frontière métier :** accepter un devis ne débite aucun paiement et ne confirme pas un rendez-vous. L'organisation du créneau, le contrat de prestation, le paiement et la clôture de l'intervention restent des étapes distinctes.

## 6. Contrôles et limites

Vérifications SQL live :
- policy du catalogue qui filtre les profils selon le statut actif/vérifié du prestataire ;
- accès anonyme limité à quatre colonnes publiques ; \`user_id\`, \`provider_type\` et \`description\` restent interdits ;
- droits directs d'écriture refusés sur demandes et devis ;
- six RPC présentes, propriétaire \`postgres\`, SECURITY DEFINER, \`search_path\` vide ;
- EXECUTE authentifié vrai ; EXECUTE anon/PUBLIC faux ;
- les six corps PL/pgSQL franchissent le garde d'authentification lorsqu'ils sont appelés sans session ; aucun profil ou demande réel n'a été créé.

Le fichier \`supabase/tests/database/professional_service_quotes_security_test.sql\` prévoit 18 assertions pgTAP. Il n'a pas été exécuté : l'extension pgTAP n'est pas installée sur la base hébergée.

Non vérifié ici :
- \`dart format\`, \`flutter analyze\`, tests Flutter et build mobile : le SDK Flutter/Dart n'est pas disponible dans cet environnement ;
- essais multi-comptes réels et parcours devis de bout en bout ;
- notifications côté prestataire, messagerie, rendez-vous/agenda avec vérification des chevauchements, contrat, acompte, paiement et suivi d'intervention ;
- test de charge et validation de la livraison en production.

Ces limites restent à traiter avant de qualifier le vertical de prêt pour la production.
