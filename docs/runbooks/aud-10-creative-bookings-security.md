# AUD-10.1 — Sécurisation du flux des réservations créatives

**Projet :** Marketplace Multiservices Burkina  
**Base Supabase :** \`dzhhsoikzxibmngjzcch\`  
**État :** correctif backend appliqué et vérifié ; intégration Flutter ajoutée ; tests d'exécution complets encore requis.

## 1. Diagnostic confirmé

La table \`public.creative_bookings\` contenait les champs \`service_id\`, \`customer_id\`, \`scheduled_at\`, \`status\` et \`agreed_amount\`.

Avant correction :
- \`authenticated\` avait des droits directs SELECT, INSERT, UPDATE et DELETE ;
- la policy client \`creative_bookings_own\` autorisait le client à muter ou supprimer ses propres réservations ;
- la policy \`active_account_guard\` était déjà de type RESTRICTIVE : elle n'ouvrait donc pas les réservations d'autres clients ;
- aucun workflow RPC ne contrôlait la confirmation par le prestataire ni le montant convenu.

Le problème était donc la mutation directe de l'état commercial par le client, et non un accès général aux réservations de tous les clients.

## 2. Migrations appliquées sur Supabase

1. \`20261106235154_secure_creative_booking_workflow\`
   - retrait des droits directs INSERT, UPDATE et DELETE de \`anon\` et \`authenticated\` ;
   - conservation du SELECT authentifié, filtré par \`customer_id = auth.uid()\` ;
   - remplacement de \`creative_bookings_own\` par \`creative_bookings_customer_read\` ;
   - création des quatre RPC décrites plus bas ;
   - maintien de la policy RESTRICTIVE \`active_account_guard\`.

2. \`20261106235226_fix_creative_booking_decision_normalization\`
   - correction de la normalisation de \`p_decision\` avec \`pg_catalog.btrim\` ;
   - rejet explicite d'une décision nulle ou inconnue.

## 3. Contrat des RPC

### Demande client — \`request_creative_booking(uuid, timestamptz)\`

- exige un compte actif et une session ;
- accepte uniquement un service actif rattaché à un prestataire actif et vérifié ;
- refuse une date passée ;
- affecte \`customer_id\` depuis \`auth.uid()\`, jamais depuis un paramètre fourni par l'application ;
- crée la réservation avec le statut \`REQUESTED\` et sans montant convenu.

### Annulation client — \`cancel_creative_booking(uuid)\`

- le client ne peut annuler que sa propre réservation ;
- seule une réservation encore \`REQUESTED\` peut être annulée ;
- une réservation confirmée ne peut pas être annulée par ce RPC simplifié ; une politique d'annulation après confirmation reste à définir.

### Liste prestataire — \`get_provider_creative_bookings()\`

- renvoie uniquement les demandes associées aux services dont le prestataire appartient à \`auth.uid()\` ;
- exige un compte actif ;
- n'autorise pas le prestataire à consulter les réservations d'un autre prestataire ;
- ne renvoie pas l'identifiant du compte client dans le résultat prestataire.

### Décision prestataire — \`respond_creative_booking(uuid, text, numeric)\`

- le prestataire doit être propriétaire du service concerné ;
- seule une demande \`REQUESTED\` peut être traitée ;
- \`CONFIRM\` exige un montant convenu non négatif et que le service ainsi que le prestataire soient toujours actifs et vérifiés ;
- \`DECLINE\` annule la demande sans pouvoir injecter un montant ;
- toute autre transition est refusée.

Les quatre fonctions sont SECURITY DEFINER, détenues par \`postgres\`, avec \`search_path = ''\`. Elles sont exécutables par \`authenticated\`, pas par \`anon\`. Les contrôles d'identité et de propriété sont dans le code SQL ; ils ne reposent pas seulement sur les boutons Flutter.

## 4. Intégration Flutter

- Le bouton \`Demander\` est activé dans la verticale Créatifs.
- L'interface client affiche \`Mes demandes\` et permet d'annuler une demande encore en attente.
- L'interface prestataire affiche \`Demandes reçues\` ; le prestataire peut confirmer avec un montant ou refuser.
- Le repository appelle les RPC sécurisées ; la lecture des demandes du client reste filtrée par RLS.
- La requête publique du catalogue créatif n'intègre plus le lien \`service_providers(display_name)\`, dont la lecture anonyme n'était pas accordée.

## 5. Vérifications réalisées

- Historique des migrations Supabase : les deux migrations sont présentes.
- Droits de table : authenticated conserve SELECT mais n'a plus INSERT, UPDATE ou DELETE ; anon n'a aucun accès direct à la table.
- Politiques : \`active_account_guard\` reste RESTRICTIVE et la seule policy permissive de la table est la lecture du client propriétaire.
- Quatre RPC : signatures présentes, propriétaire postgres, SECURITY DEFINER, search_path vide, EXECUTE authenticated oui / anon non.
- Compilation à la première invocation : les quatre fonctions ont été appelées sans session dans un bloc de test qui attendait \`account_not_active\` ; cela a forcé PostgreSQL à compiler les corps sans effectuer de mutation.
- Dix contrôles SQL équivalents aux assertions du fichier pgTAP : 10/10 vrais.

## 6. Tests non exécutés et limites restantes

Le fichier \`supabase/tests/database/creative_bookings_security_test.sql\` contient 10 assertions pgTAP. L'extension pgTAP n'est pas installée sur la base hébergée et le binaire Supabase CLI n'est pas disponible dans cet environnement ; le fichier pgTAP n'a donc pas été exécuté. Les dix prédicats correspondants ont été évalués directement en lecture seule sur la base hébergée.

Aucun compte client ou prestataire réel n'est présent dans la base hébergée. Les scénarios de bout en bout avec deux utilisateurs distincts, les essais sur appareil Flutter et l'analyse Dart/Flutter restent à exécuter.

Fonctionnalités métier qui restent à compléter :
- conversation client-prestataire et description détaillée du besoin ;
- proposition de devis avant acceptation ;
- durée, disponibilité et prévention des chevauchements de créneaux ;
- politique d'annulation après confirmation ;
- notifications et journal détaillé des transitions ;
- paiement, acompte, remboursement et rapprochement. Aucun paiement n'est traité par ce correctif.

## 7. Fichiers

- Migration : \`supabase/migrations/20261106235154_secure_creative_booking_workflow.sql\`
- Correction de décision : \`supabase/migrations/20261106235226_fix_creative_booking_decision_normalization.sql\`
- Tests : \`supabase/tests/database/creative_bookings_security_test.sql\`
- Repository : \`lib/features/verticals/data/vertical_repository.dart\`
- Interface : \`lib/features/verticals/presentation/vertical_discovery_page.dart\`

**Conclusion :** le client ne peut plus modifier directement le montant, le statut ou supprimer une réservation via la Data API. Le workflow backend et les principaux boutons Flutter sont en place. AUD-10.1 reste partiellement ouvert jusqu'aux tests réels client/prestataire et aux règles métier complémentaires ci-dessus.
