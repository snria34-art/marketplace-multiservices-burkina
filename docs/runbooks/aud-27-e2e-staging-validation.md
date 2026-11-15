# AUD-27 — Parcours E2E de validation en staging

**Projet :** Marketplace Multiservices Burkina  
**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Date :** 16 novembre 2026  
**Statut :** scénarios et critères rédigés ; aucune exécution réelle faute d'environnement staging, de comptes de test actifs et de configuration fournisseur.

## 1. Préconditions

- Projet Supabase staging isolé, avec la même version de migrations que le commit candidat.
- Flutter Web Debug et build Android/iOS Debug provenant du même commit.
- Comptes de test séparés : client, vendeur A, vendeur B, coursier, administrateur et modérateur.
- Boutiques, produits, variantes, stock, adresses et commandes fictifs ; aucune donnée personnelle réelle.
- Wave/CinetPay uniquement via l'environnement et les clés de test confirmés par les fournisseurs.
- FCM via un projet Firebase de test et des appareils de test autorisés.
- Logs expurgés des secrets, tokens, coordonnées GPS exactes et documents personnels.

Ne pas exécuter ce plan contre le projet Supabase de production. Ne pas utiliser de paiement, remboursement ou payout réel.

## 2. Parcours client et commande

1. Créer un compte client, se connecter, se déconnecter puis se reconnecter ; vérifier l'expiration/récupération de session.
2. Parcourir le catalogue paginé, ouvrir un produit, sélectionner une variante et ajouter/modifier/retirer le panier.
3. Vérifier que le prix, le stock, les coupons et la livraison sont recalculés côté serveur ; modifier les données côté client ne doit pas changer le total serveur.
4. Créer une commande fictive multi-boutiques ; vérifier une seule réservation de stock par ligne, les groupes vendeurs et les colis associés.
5. Envoyer deux checkouts concurrents sur le dernier exemplaire ; une seule réservation doit réussir.

## 3. Paiements — callbacks simulés

1. Configuration fournisseur absente : le précontrôle doit bloquer le checkout avant commande/réservation.
2. Signature invalide, paiement lié à une autre commande, montant ou devise incorrects : rejet sans transition.
3. Callback XOF valide : un seul passage à `SUCCEEDED`, paiement/commande synchronisés.
4. Rejouer le même identifiant d'événement : réponse idempotente, aucune seconde mutation.
5. Envoyer deux événements distincts pour la même session ; vérifier que l'identité d'événement ne se confond pas avec la référence stable du checkout.
6. État intermédiaire, notification retardée et événements dans le désordre : aucun faux succès ni régression de statut.
7. Simuler timeout/5xx après création de session : garder l'état ambigu pour rapprochement, sans créer aveuglément une deuxième session.

## 4. Vendeur, livraison et GPS

1. Connexion vendeur A : vérifier que seules ses boutiques, commandes, produits et finances sont accessibles.
2. Connexion vendeur B : confirmer l'absence d'accès aux données de A.
3. Affecter un colis au coursier ; vérifier que l'acceptation, le retrait, le démarrage et la preuve de livraison suivent les transitions autorisées.
4. Essayer les RPC coursier sans mission, avec mission d'un autre compte, après annulation et après livraison ; les écritures GPS doivent être refusées hors affectation active.
5. Démarrer le suivi volontairement, passer en arrière-plan et verrouiller l'appareil ; vérifier la continuité, la notification de service Android et l'indicateur iOS.
6. Terminer la dernière mission, revenir au premier plan et vérifier l'arrêt du flux ainsi que la disparition de l'accès client à la position.
7. Vérifier la consommation batterie, les permissions révoquées et la rétention/purge définie par politique approuvée.

## 5. Retours et remboursements

1. Un retour demandé doit appartenir à la commande et aux lignes du client.
2. Une quantité approuvée ne peut pas dépasser la quantité achetée moins les quantités déjà retournées/remboursées.
3. Un remboursement ne doit pas débiter un vendeur absent des lignes allouées.
4. Vérifier coupon plateforme, coupon vendeur, cofinancement, commission et livraison avec des allocations exactes en XOF.
5. Un remboursement confirmé chez le fournisseur mais non comptabilisé doit entrer en rapprochement interne ; ne pas rappeler le fournisseur pour « réparer » le ledger.
6. Tant que `PENDING_ALLOCATION` subsiste, les retraits concernés et le nouveau remboursement suivant la règle de la migration restent bloqués.

## 6. Notifications et rôles

1. Notification créée, préférences actives, un appareil Android et un iPhone enregistrés : vérifier la réception, le titre, le contenu et la route interne.
2. Préférence désactivée : aucune notification push ne part pour cette catégorie.
3. Token expiré : il est désactivé sans exposer sa valeur dans les logs.
4. Test multi-appareils avec succès partiel : aujourd'hui le worker ne suit pas durablement l'état par appareil ; ce test doit rester bloquant jusqu'à la mise en place du suivi idempotent par appareil décrit dans `docs/push-notifications.md`.
5. Vérifier l'interdiction des actions finance/compte par un modérateur non habilité et les refus Storage pour les rôles non propriétaires.

## 7. Preuves et critères de sortie

Pour chaque cas, conserver :
- SHA Git exact, version Flutter/Dart et plateforme ;
- identifiant de test non personnel, étape et résultat attendu/observé ;
- logs CI et rapport de test sans secrets ;
- vérification des données et des statuts finaux ;
- preuve d'absence de double paiement, double stock, double remboursement et accès inter-comptes.

Un parcours ne peut être marqué réussi que si le scénario a été exécuté dans staging et que le résultat est observé. La présence d'une route, d'une RPC, d'une migration ou d'un test unitaire n'est pas une preuve E2E.

## 8. État au 16 novembre 2026

- Tests Flutter automatisés : CI couvre les tests unitaires/widget présents ; le nouveau test de reprise du livreur doit être exécuté sur le prochain run.
- Builds natifs Debug : Android a déjà un résultat réussi sur une révision antérieure ; iOS Simulator reste non exécuté.
- Base locale : un ancien run pgTAP a réussi sur un commit antérieur ; aucun nouveau workflow DB manuel n'a été déclenché dans cette passe.
- Paiements, FCM, GPS appareil réel et E2E staging : **non exécutés**.
