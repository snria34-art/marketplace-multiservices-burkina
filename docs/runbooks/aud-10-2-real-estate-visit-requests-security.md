# AUD-10.2 — Sécurisation des demandes de visite immobilière

**Projet :** Marketplace Multiservices Burkina  
**Dépôt :** \`adjasanou49-max/marketplace-multiservices-burkina\`, branche \`main\`  
**Base Supabase :** \`dzhhsoikzxibmngjzcch\`  
**Migration :** \`20261106235956_secure_real_estate_visit_request_workflow\`  
**État :** migration appliquée ; repository et interface Flutter raccordés ; contrôles structurels live passés ; compilation Flutter et tests de parcours utilisateur non exécutés.

## 1. Diagnostic

- \`real_estate_listings\` exposait les annonces actives et vérifiées en lecture publique.
- Aucun bouton d'action immobilier n'était présent dans \`_hasAction\`, donc l'utilisateur ne pouvait pas demander une visite depuis l'écran.
- Aucune table ni RPC immobilier ne gérait les demandes de visite ou de contact.
- La propriété d'une annonce est portée par \`real_estate_listings.provider_id\`, qui référence \`service_providers.id\` ; le compte propriétaire est \`service_providers.user_id\`.
- Les annonces existantes étaient au nombre de zéro au moment de l'inspection. Aucun compte ou enregistrement de démonstration n'a été créé.

## 2. Schéma et sécurité appliqués

Nouvelle table : \`public.real_estate_visit_requests\`.

Champs : identifiant, annonce, demandeur, date/heure souhaitée facultative, message facultatif, statut, horodatages.

Statuts autorisés : \`REQUESTED\`, \`ACCEPTED\`, \`DECLINED\`, \`CANCELLED\`.

Mesures de protection :
- Les contrôles d'état verrouillent l'annonce et le prestataire : `FOR SHARE` à la création, `FOR UPDATE` à l'acceptation, afin de prévenir les courses avec une désactivation ou un changement de vérification.
- RLS activée ; politique RESTRICTIVE de compte actif pour \`authenticated\`.
- Aucun privilège direct SELECT/INSERT/UPDATE/DELETE pour \`anon\` ou \`authenticated\`.
- \`service_role\` conserve les privilèges de service.
- Index unique partiel : un seul état \`REQUESTED\` par couple annonce/demandeur.
- Clés étrangères vers l'annonce et \`auth.users\`.
- Message limité à 1 000 caractères ; date souhaitée future et limitée à 180 jours.
- Une personne ne peut pas demander une visite de sa propre annonce.
- L'annonce et le prestataire doivent être actifs et vérifiés au moment de la demande.
- Les fonctions prennent l'identité depuis \`auth.uid()\` ; aucun identifiant de demandeur ou propriétaire fourni par le client n'est utilisé pour établir les droits.
- Les fonctions ont un \`search_path\` vide, appartiennent à \`postgres\`, et leur EXECUTE est accordé uniquement à \`authenticated\`. EXECUTE est révoqué à \`PUBLIC\` et \`anon\`.

## 3. Contrat des RPC

Migration de durcissement complémentaire : `20261107000545_lock_real_estate_listing_state_during_request_transitions` — elle remplace les fonctions de création et de réponse pour verrouiller les lignes annonce/prestataire pendant les contrôles de disponibilité.


- \`request_real_estate_visit(uuid,timestamptz,text)\` : crée une demande depuis un compte actif ; vérifie annonce, prestataire, date et message.
- \`cancel_real_estate_visit(uuid)\` : le demandeur peut annuler uniquement sa propre demande encore \`REQUESTED\`.
- \`get_my_real_estate_visit_requests()\` : liste les demandes du demandeur courant.
- \`get_provider_real_estate_visit_requests()\` : liste les demandes liées aux annonces appartenant au prestataire courant ; le résultat n'expose pas l'UUID du compte demandeur.
- \`respond_real_estate_visit(uuid,text)\` : seul le propriétaire de l'annonce peut accepter ou refuser une demande \`REQUESTED\`. L'acceptation revalide l'état actif et vérifié de l'annonce et du prestataire.

## 4. Intégration Flutter

Fichiers modifiés :
- \`lib/features/verticals/data/vertical_repository.dart\`
- \`lib/features/verticals/presentation/vertical_discovery_page.dart\`

Le module immobilier propose maintenant :
- bouton \`Visiter / contacter\` sur chaque annonce ;
- formulaire de demande avec message et date/heure souhaitée facultative ;
- écran \`Mes demandes immobilières\`, avec annulation des demandes en attente ;
- écran \`Demandes reçues pour mes annonces\`, avec acceptation ou refus.

Le message et la date souhaitée ne créent pas un rendez-vous définitif. L'acceptation signifie que le propriétaire accepte de poursuivre la prise de contact ; l'heure exacte doit encore être convenue.

## 5. Vérifications et limites

Vérifié sur la base hébergée :
- table créée et RLS activée ;
- aucun accès direct Data API pour \`anon\` et \`authenticated\` ;
- policy active-account bien RESTRICTIVE ;
- deux clés étrangères, trois contraintes CHECK et quatre index présents ;
- cinq RPC présentes, propriétaire \`postgres\`, SECURITY DEFINER, \`search_path\` vide ;
- EXECUTE authentifié vrai ; EXECUTE anon/PUBLIC faux ;
- les cinq corps PL/pgSQL ont franchi le garde d'authentification en appels sans session ; les requêtes SQL internes ont aussi été exécutées en transaction avec identifiants aléatoires et rollback, sans mutation persistante ;
- les contrôles de disponibilité utilisent des verrous transactionnels sur l'annonce et le prestataire ; le conseiller sécurité signale les cinq RPC dans la catégorie générique « Signed-In Users Can Execute SECURITY DEFINER Function » ; c'est intentionnel puisque ce sont les points d'entrée authentifiés, avec vérification de compte et de propriété. Aucun EXECUTE anon/PUBLIC n'est ouvert.

Le fichier \`supabase/tests/database/real_estate_visit_requests_security_test.sql\` prévoit 13 assertions pgTAP, mais pgTAP n'est pas installé sur la base hébergée et le fichier n'a donc pas été exécuté.

Non vérifié ici :
- \`dart format\`, \`flutter analyze\`, tests Flutter et build Android/iOS : SDK Dart/Flutter absent de l'environnement ;
- tests multi-comptes réels : aucun compte test/propriétaire créé ;
- notification push/email, chat intégré, téléphone du demandeur, paiement, agenda avec créneaux réellement disponibles et contrôle des chevauchements ;
- acceptation de demande ≠ réservation d'un créneau confirmé.

Ces limites restent des tâches distinctes et ne doivent pas être présentées comme livrées.
