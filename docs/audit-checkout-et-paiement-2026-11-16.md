# Audit panier, checkout et sessions de paiement — 16 novembre 2026

## Périmètre examiné

Revue statique de la branche `maintenance/audit-01-07-2026-11-15` :
- Flutter : `CartRepository`, `CartPage`, `CheckoutRepository`, `CheckoutPage` et le modèle de disponibilité des fournisseurs ;
- SQL : `checkout_cart`, validation de l'adresse, calcul serveur des frais, réservation/consommation/libération de stock par variante, création d'intention de paiement et préparation de session ;
- Edge Functions : création des sessions Wave et CinetPay v3, contrôle de configuration, webhooks et validations communes ;
- contrat pgTAP : `supabase/tests/database/order_delivery_contract_test.sql`.

## Contrôles statiques satisfaisants

1. Le checkout exige un utilisateur authentifié et un panier actif lui appartenant. La clé d'idempotence est obligatoire.
2. L'adresse n'est pas acceptée sur la seule base des coordonnées fournies par le mobile : la RPC recharge une adresse appartenant au client.
3. Les prix sont relus depuis le catalogue. Le calcul final des frais de livraison est effectué côté serveur.
4. Le stock est réservé par variante lorsque le stock par variante est configuré. Si un produit a commencé à utiliser des stocks par variante, une variante non configurée ne retombe pas silencieusement sur le stock parent.
5. Les fonctions de consommation et de libération du stock tiennent compte de la variante dans les chemins examinés.
6. Les fonctions de paiement vérifient le propriétaire de la commande, l'état du paiement, le montant et la devise XOF. Les webhooks contrôlent la signature et valident les montants avant le traitement SQL.
7. Les appels Edge Functions utilisent le contexte d'authentification du client ; les références et statuts sont ensuite vérifiés côté serveur.

Ces constats proviennent de la lecture des définitions et migrations présentes dans Git. Ils ne remplacent pas une exécution de la base ni des tests sur les fournisseurs sandbox.

## Défauts corrigés sur la branche

### PAN-01 — Variante absente du résumé du panier

Le dépôt conservait `variant_id` et le prix unitaire, mais la requête Flutter ne lisait pas `product_variants.name`. L'écran du panier n'affichait donc que le nom du produit et le prix : le client ne pouvait pas vérifier visuellement l'option choisie avant le checkout.

Correction :
- ajout de `product_variants(name)` à la requête du panier ;
- affichage du nom de variante dans le sous-titre de chaque article, lorsqu'une variante existe.

### PAY-01 — Préparation concurrente de plusieurs sessions pour un même paiement

Les Edge Functions Wave/CinetPay peuvent être appelées concurremment. Avant ce correctif, deux appels pouvaient lire un paiement à l'état `PENDING`, créer une session fournisseur chacun, puis entrer successivement dans `prepare_payment_processing`. La RPC verrouillait la ligne, mais acceptait encore un paiement déjà `PROCESSING` avec une référence différente : le champ de référence conservait la première valeur via `coalesce`, tandis que les métadonnées pouvaient être remplacées par celles du second appel.

Correction :
- nouvelle migration `20261116120000_prevent_competing_payment_sessions.sql` ;
- la RPC verrouille toujours la ligne de paiement ;
- lorsqu'une référence est déjà enregistrée, une référence différente déclenche `payment_session_already_prepared` ; la même référence reste idempotente ;
- l'assertion de contrat pgTAP couvre le verrouillage, le refus d'une référence concurrente et les privilèges de la RPC.

La migration a été ajoutée au dépôt, mais n'a pas été exécutée sur Supabase distant.

## Validation et limites

- Les fichiers modifiés ont été relus depuis GitHub après écriture.
- Le fichier pgTAP annonce désormais 14 assertions de contrat.
- Aucun lancement local de `flutter analyze`, `flutter test`, Deno tests ou pgTAP n'a été effectué dans cette passe.
- Le dernier statut combiné GitHub consulté pour le commit de travail ne rapporte aucun status check (`statuses: []`). Il ne faut donc pas considérer cette passe comme validée par CI.
- Aucun paiement réel, remboursement ou mouvement financier n'a été effectué.
- Aucune migration distante, aucun déploiement et aucune modification de `main` n'ont été effectués.

## État de la branche

Comparaison avec `main` au commit `9b70580f322814d6decf9eeac2e5d93aa01e44e9), avant l'ajout de ce rapport :
- branche de maintenance : 194 commits en avance ;
- branche de maintenance : 1 commit en retard ;
- état : divergé.

Ne pas fusionner automatiquement. Une revue de synchronisation de l'unique commit manquant et une validation CI complète restent nécessaires.
