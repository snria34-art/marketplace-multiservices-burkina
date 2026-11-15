# Plan de mise à niveau professionnelle — 15 novembre 2026

**Dépôt :** `snria34-art/marketplace-multiservices-burkina`  
**Branche de travail :** `maintenance/audit-01-07-2026-11-15`  
**Statut :** feuille de route d'audit et de validation, pas une autorisation de mise en production.

## Objectif

Amener Marketplace Multiservices Burkina au niveau d'exploitation attendu d'une plateforme commerciale multiservices : sécurité démontrable, paiements réconciliés, opérations de livraison fiables, données personnelles maîtrisées, restauration testée et support exploitable.

Une application ne devient pas professionnelle par le seul nombre de fonctionnalités. Chaque parcours doit être éprouvé avec des comptes de test, des scénarios d'échec, des métriques et des procédures de reprise.

## Règles de périmètre

- Toutes les modifications de code restent sur la branche de maintenance.
- Ne pas pousser, fusionner ou réinitialiser `main`.
- Aucune migration distante, modification de données, commande, stock, solde, paiement ou remboursement réel.
- Aucun secret de production, compte marchand ou compte Firebase ne doit être lu ou ajouté au dépôt.
- Aucun déploiement, publication de store, build Release ou test de charge sur la production.
- Les essais de paiement utilisent des fournisseurs simulés puis leurs environnements sandbox, avec des comptes et montants fictifs.
- Les opérations nécessitant un propriétaire Supabase, GitHub ou Firebase sont consignées comme actions externes, et non simulées.

## État de référence vérifié

- Le dépôt couvre déjà le catalogue, le panier/checkout, les commandes multi-vendeurs, les vendeurs, les coursiers, la livraison, les restaurants, les transports et 16 verticales de services.
- Flutter CI a réussi sur le commit `3df89c0a6d345275c7eb1c26a0bf2c57d1f83b38` : analyse, tests et build Web Debug.
- Android APK Debug a réussi sur le même commit ; ce n'est ni une version signée ni une publication.
- La reconstruction Supabase locale et les tests pgTAP ont réussi sur le commit `1323df6c75d1d22b060bde438303d7c81acdd830` : 8 fichiers, 180 assertions.
- La vérification Deno des 22 points d'entrée Edge Functions a réussi sur le commit `cf991b571068db2d7d5cc27a960bae9e8a0863a3`.
- Le commit `3ad203129b270002c384f5853fc7579893169aa4` aligne maintenant l'upload d'images produit avec le format HEIC autorisé par le bucket. Les workflows Flutter et Android lancés pour ce commit doivent être confirmés avant de considérer ce correctif validé.
- `main` reste sur `be9c6407aa384d417f43c20d1492b3b9dcb21cb0`. Le contrôle GitHub consulté retourne `protected=false`, sans contrôles obligatoires configurés. Le contenu de `main` est intact, mais sa protection administrative est à activer par un propriétaire du dépôt.

Ces résultats ne prouvent pas la sécurité de la configuration hébergée, le comportement sur appareils physiques, la disponibilité des prestataires ou la capacité à supporter un trafic de production.

## P0 — Verrouiller le code et les accès privilégiés

### GitHub et chaîne de livraison

- Activer la protection de `main` avec fusion par Pull Request, au moins une validation, contrôles CI obligatoires, interdiction des force-push et suppressions.
- Rendre obligatoires les validations pertinentes avant merge : Flutter analyze/tests, Edge Functions, reconstruction DB/pgTAP, build Android Debug et, lorsqu'un runner Apple est disponible et autorisé, build iOS Simulator.
- Réduire les permissions des workflows au strict nécessaire ; conserver `contents: read` pour les tests.
- Épingler les actions tierces sur des versions ou SHA revus et fixer la version Deno au lieu d'une version flottante.
- Ajouter une procédure de revue de dépendances, de mises à jour de sécurité et de révocation des secrets compromis.

**Critères de sortie :** `main` est protégé dans GitHub Settings/Rulesets ; un push direct et un force-push sont refusés ; une PR sans contrôles verts ne peut pas être fusionnée ; les logs CI ne contiennent aucun secret.

**Action propriétaire :** la lecture GitHub confirme actuellement que la protection de `main` est désactivée. L'outil disponible durant cette passe permet de lire cette configuration, mais pas de la modifier. Ne pas prétendre qu'elle est activée avant confirmation dans GitHub.

### Authentification et administration

- Vérifier dans Supabase Auth les politiques de mot de passe, confirmations email, limites de tentatives, durée des sessions, OTP et restrictions de redirection.
- Activer MFA pour les administrateurs et les comptes qui manipulent les paiements, remboursements, comptes ou paramètres de plateforme.
- Ajouter une réauthentification pour les opérations critiques et une récupération de compte vérifiable.
- Définir une matrice RBAC par domaine : modération, support, finance, comptes, logistique, paramètres plateforme et gestion des rôles.
- Protéger le dernier administrateur propriétaire et journaliser toute élévation, suspension, approbation, modification financière et réparation.
- Conserver le contrôle serveur comme autorité : masquer une route dans Flutter n'est jamais une permission suffisante.

**Critères de sortie :** tests positifs et négatifs pour chaque rôle ; un modérateur ne peut pas effectuer une opération finance ou plateforme ; MFA vérifié sur les comptes administrateurs de staging ; journal d'audit consultable et non modifiable par le rôle qui réalise l'action.

## P1 — Sécuriser l'argent avant les paiements réels

### Remboursements multi-vendeurs

Le runbook `docs/runbooks/aud-02-refund-allocation.md` décrit une anomalie d'allocation : le modèle actuel peut répartir un remboursement entre des groupes vendeurs non concernés par l'article remboursé.

Avant toute correction de schéma ou de code :
1. Faire approuver la règle métier de financement des remises, commissions, frais de livraison et retours.
2. Figer au checkout les prix, quantités, remises et parts financées par chaque partie.
3. Définir les retours par article et quantité, avec verrouillage transactionnel contre les retours concurrents.
4. Enregistrer des allocations de remboursement immuables, traçables jusqu'à la ligne et au groupe vendeur.
5. Garantir que les sommes allouées égalent exactement le montant rendu au client en XOF.
6. Rendre les écritures de ledger idempotentes avec une clé unique par allocation.
7. Prévoir la réconciliation lorsqu'un prestataire confirme le remboursement mais que l'écriture locale échoue.

**Critères de sortie :** pgTAP prouve les cas mono-vendeur, multi-vendeur, plusieurs boutiques d'un vendeur, retour partiel, remboursement complet, remise partagée, événement répété, timeout ambigu et capture tardive. Aucun groupe non concerné n'est débité.

**Interdiction :** ne pas modifier les soldes, le ledger ou les remboursements de production pour faire passer un test.

### Wave et CinetPay

- Vérifier les secrets et paramètres depuis le compte propriétaire, sans exposer leur contenu.
- Créer des adaptateurs de test et simuler signature incorrecte, montant/devise erronés, référence inconnue, doublon, retard, timeout et HTTP 5xx.
- Rejouer ensuite les mêmes cas en sandbox marchand.
- Ajouter le rapprochement périodique entre paiements, commandes, prestataires et ledger.
- Maintenir un état explicite de traitement incertain nécessitant rapprochement ; ne jamais renvoyer aveuglément une requête potentiellement déjà acceptée.
- Vérifier les retours navigateur indépendamment des webhooks : le retour navigateur ne prouve jamais le paiement.

**Critères de sortie :** aucun paiement n'est marqué réussi sans preuve vérifiée côté serveur ; les webhooks répétés ne dupliquent aucune écriture ; chaque cas ambigu aboutit à une procédure de rapprochement.

## P1 — Stabiliser la livraison, les notifications et la géolocalisation

### Notifications FCM

- Configurer Firebase pour Android/iOS via le propriétaire, sans déposer les fichiers privés de service account dans Git.
- Gérer les tentatives et résultats par appareil : un appareil en échec ne doit pas perdre sa notification parce qu'un autre appareil l'a reçue.
- Empêcher les doublons pour les appareils déjà servis, gérer tokens invalides et révocations.
- Tester notification en premier plan, arrière-plan, application fermée, déconnexion, changement de compte et token renouvelé.

**Critères de sortie :** chaque destinataire a un état vérifiable ; les échecs sont rejouables sans renvoyer en double aux appareils ayant déjà reçu le message.

### GPS et vie privée

- Fixer avec le responsable métier la durée de conservation et la finalité des positions GPS ; documenter l'information donnée au coursier.
- Tester sur Android et iPhone réels : arrière-plan, écran verrouillé, économie de batterie, permission refusée/révoquée, mission terminée et déconnexion.
- Vérifier qu'aucun client ne lit la position d'un livreur hors de sa mission active.
- Mettre en place la purge serveur contrôlée après validation de la durée légale et métier.

**Critères de sortie :** arrêt côté client et refus côté serveur à la fin de mission ; isolation entre clients ; politique de rétention approuvée et purge testée en staging.

## P1 — Terminer les opérations Supabase

### PostGIS

Le runbook `docs/runbooks/aud-01-postgis-schema-move.md` décrit PostGIS installé dans `public`, avec des privilèges excessifs rapportés sur `spatial_ref_sys`. Le déplacement non destructif dépend de Supabase Support, car l'extension appartient à `supabase_admin`.

- Ouvrir le ticket Support avec le texte du runbook.
- Ne pas utiliser `DROP EXTENSION`, de déplacement forcé, de trigger de contournement ou de REVOKE supposé suffisant.
- Après intervention Support, vérifier le schéma d'installation, les trois colonnes geography, les index GiST, les RPC, les droits et Security Advisor.

**Critères de sortie :** contrôles post-intervention tous verts et preuve documentée du Support.

### Historique, sauvegardes et reprise

- La reconstruction locale de la base et les 180 tests pgTAP ont réussi dans le workflow isolé ; conserver cette validation comme base reproductible.
- Réconcilier l'historique distant des migrations sans exécuter de migration SQL à l'aveugle.
- Vérifier le plan de sauvegarde, la rétention et les points de restauration dans le Dashboard.
- Sauvegarder séparément les objets Supabase Storage.
- Restaurer une sauvegarde dans un projet isolé et mesurer le RPO/RTO réel.
- Ne pas annoncer une capacité de 1 000 ou 10 000 utilisateurs sans test de charge représentatif.

**Critères de sortie :** restauration complète démontrée sur staging ; vérification des tables, fonctions, rôles, RLS, Storage et intégrations après restauration ; test de charge approuvé et budget accepté.

## P2 — Prouver la qualité des parcours et préparer le marché

### Tests de bout en bout

Construire une matrice de tests avec comptes factices distincts :
- client : inscription, recherche, panier, adresse, checkout sandbox, commande, avis, retour ;
- vendeur : demande d'accès, publication, modération, stock, commande, commission, demande de paiement ;
- coursier : disponibilité, acceptation, prise en charge, preuve, GPS, livraison, fin de mission ;
- modérateur : modération uniquement ;
- administrateur : comptes, finance, paramètres et actions de plateforme selon sa permission.

Inclure les doubles clics, appels concurrents, perte réseau, expiration de session, appareils multiples et reprise après interruption.

### Qualité mobile et architecture

- Confirmer la compilation iOS Simulator Debug sur runner macOS autorisé.
- Installer la version Debug sur appareils physiques Android et iOS pour tester permissions, notifications, liens profonds, caméra, GPS et réseau instable.
- Découper progressivement `vertical_discovery_page.dart` (écran très volumineux) par verticale et parcours ; ne pas faire de réécriture globale.
- Vérifier accessibilité, contraste, zoom, lecteurs d'écran, petits écrans et langues/français.
- Garder les limites de taille, signatures binaires, politiques Storage privées et inspection serveur des médias.

### Différenciation produit au Burkina Faso

À considérer après stabilisation des parcours fondamentaux :
- assistant WhatsApp et interactions vocales pour les utilisateurs à faible aisance numérique ;
- dispatch coursier plus transparent, disponibilité réelle et estimation fiable des délais ;
- regroupement de commandes/livraisons avec consentement et calcul clair des économies ;
- moyens Mobile Money adaptés au marché, avec rapprochement systématique ;
- vérification visible des vendeurs/prestataires, réclamations, assistance humaine et résolution traçable ;
- expérience légère sur réseau lent, reprise d'upload et limitation de consommation de données.

Chaque fonctionnalité commerciale doit être validée avec des commerçants et clients pilotes avant d'être généralisée.

## Portes de sortie avant lancement public

Le lancement public n'est autorisable que si :
- aucun risque P0/P1 de sécurité ou de comptabilité ne reste ouvert ;
- `main` est protégé et la fusion exige des contrôles CI réussis ;
- Flutter, Android et iOS sont validés sur les cibles publiées ;
- reconstruction DB, tests pgTAP et tests E2E sont verts ;
- paiements et remboursements sont validés en sandbox et rapprochés ;
- notifications et livraison sont validées sur appareils réels ;
- PostGIS et Security Advisor ne montrent plus de risque critique non accepté ;
- sauvegardes/restauration et processus support/incidents sont prouvés ;
- politique de confidentialité, rétention GPS et documents de conformité ont été approuvés.

## Limites

Ce plan ne certifie pas l'application et ne garantit pas l'absence absolue de défauts. Une validation professionnelle exige des preuves reproductibles, des tests indépendants et des contrôles de configuration dans les consoles des fournisseurs. Toute action sur la production ou tout changement financier doit être séparément autorisé et testé sur environnement isolé au préalable.


---

## Vérification ciblée complémentaire — 15 novembre 2026

Cette section complète l'état de référence ci-dessus après vérification GitHub, recherche dans le code et contrôle de disponibilité des connecteurs.

### Builds du correctif HEIC

Commit de code testé : `3ad203129b270002c384f5853fc7579893169aa4`.

- Flutter CI `43730338406` : **success**, y compris analyse, tests et build Flutter Web Debug.
- Android Debug `43730338472` : **success**, y compris l'étape `flutter build apk --debug`.
- iOS Simulator Debug : job **skipped**. Le workflow ne le lance que sur `workflow_dispatch` et utilise un runner macOS. Aucun build iOS n'est donc validé.
- Le commit `0cb9448d7ba9b34c2cb79f51e3b3d4b0565a23aa` ajoute uniquement cette feuille de route/documentation après ces validations ; les fichiers applicatifs validés restent ceux du commit `3ad2031`.

### Sécurité réellement active en production

**Non vérifiée dans cette passe.** Le connecteur Supabase actuellement disponible retourne une liste de projets vide. Aucun projet n'a donc été sélectionné et aucun Security Advisor, réglage Auth/MFA, paramètre Storage, log ou métrique de base hébergée n'a été consulté. Les anciens runbooks décrivent des observations historiques et ne remplacent pas un contrôle live daté.

Le contrôle GitHub de la branche indique toujours :
- `main` = `be9c6407aa384d417f43c20d1492b3b9dcb21cb0` ;
- protection de branche désactivée (`protected=false`, aucun status check requis) ;
- le contenu de `main` n'a pas été modifié.

Il faut donc conserver le statut **sécurité de production incomplètement vérifiée**. La protection GitHub de `main` est un constat actuel confirmé ; les paramètres Supabase live restent inconnus, pas supposés vulnérables ou sûrs.

### Exploitation commerciale

**Non démontrée à partir des données disponibles.** Aucun projet Supabase n'étant exposé au connecteur, aucune statistique de comptes, boutiques actives, commandes, paiements, livraisons, réclamations ou rétention n'a pu être extraite. Le dépôt ne fournit pas de preuve d'activité commerciale réelle. L'API GitHub des Releases retourne une liste vide ; cela ne permet pas d'exclure une distribution par un autre canal.

Les chiffres d'activité doivent être fournis par des métriques de production ou un rapport d'exploitation daté, anonymisé et vérifiable. Les nombres de modules, fichiers, tests ou commits ne sont pas des indicateurs de traction commerciale.

### Vérification des avantages concurrentiels dans le code

- **WhatsApp : non trouvé.** La recherche du dépôt pour `whatsapp` et `wa.me` ne retourne aucun résultat de code. Une intégration WhatsApp Business/API ou un assistant conversationnel n'est donc pas démontré.
- **Livraison groupée multi-commandes : non trouvée comme fonction dédiée.** Le dépôt contient `group_buy`, qui porte sur l'achat groupé, et la gestion de colis/affectations de livraison. Cela ne prouve pas un regroupement d'ordres indépendants dans une tournée mutualisée, une optimisation de route ou un calcul de réduction de coût partagé.
- **Portefeuille : partiellement présent.** Le dépôt expose un solde vendeur calculé depuis `seller_ledger` et des demandes de payout. La recherche ne démontre pas de portefeuille client prépayé, de dépôt/retrait client ou de transfert entre utilisateurs. Ne pas assimiler le ledger vendeur à un wallet client.
- **Réseau opérationnel : base technique présente, réseau réel non prouvé.** Les fonctions vendeur, prestataire, coursier, vérification et affectation sont présentes dans le code. Sans données live, il est impossible de confirmer le nombre de boutiques, professionnels, livreurs ou partenaires réellement actifs, leur couverture par ville et leurs délais de service.

### Contexte concurrentiel WhatsApp

GO AI CORP a annoncé Jclick AI à Ouagadougou, avec une présentation/lancement indiqué au 12 mai 2026 et une publication de l'entreprise datée du 23 août 2026. LeFaso a également relaté le lancement et cité les fonctions revendiquées par son promoteur : commandes multiservices et recherche de vendeurs/livreurs via WhatsApp. Ce sont des annonces et descriptions publiques, pas un audit indépendant de disponibilité ou de volumes d'utilisation.

Sources publiques :
- GO AI CORP : https://goaicorporation.org/lancement-agent-ia-jclick-ai
- LeFaso : https://lefaso.net/?id_article=146450&page=impression

**Conséquence stratégique :** WhatsApp n'est pas une différence concurrentielle théorique à surveiller plus tard : un acteur local l'a déjà annoncé. Marketplace Multiservices Burkina doit soit intégrer une expérience WhatsApp réellement reliée aux commandes et au support, soit se différencier autrement par son réseau de prestataires vérifiés, sa fiabilité de livraison, ses prix transparents et son service client mesurable.

### Conclusion corrigée

- Builds Flutter/Web Debug et Android Debug : confirmés réussis sur le correctif HEIC.
- iOS : non compilé, job ignoré ; ne pas le présenter comme validé.
- Sécurité Supabase live : non vérifiable avec la connexion actuelle ; protection GitHub de `main` confirmée désactivée.
- Exploitation commerciale : aucune preuve métrique accessible dans cette passe.
- WhatsApp, livraison groupée multi-commandes et wallet client : non démontrés dans le code examiné.
- Solde/ledger vendeur, achat groupé et workflow logistique des colis : présents, mais ce sont des fonctions différentes.
