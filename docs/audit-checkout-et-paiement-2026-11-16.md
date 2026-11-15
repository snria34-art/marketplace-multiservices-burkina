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

Une première inspection de la version antérieure des migrations a fait suspecter qu'un second appel pouvait remplacer les métadonnées d'une session de paiement déjà préparée. La vérification de la migration plus récente `20261115191336_phase1_commerce_integrity_final.sql` a montré que ce cas est déjà traité : la fonction `prepare_payment_processing` verrouille la ligne de paiement, conserve la première référence fournisseur et rejette une référence concurrente avec `payment_checkout_reference_conflict`. Elle traite aussi de manière idempotente une notification de paiement réussi pour la même référence.

Le test `supabase/tests/database/phase1_commerce_integrity_test.sql` vérifie déjà ce contrat. Le fichier `order_delivery_contract_test.sql` contient également une assertion qui contrôle l'immuabilité de la référence enregistrée. Une migration supplémentaire candidate créée pendant cette passe a été supprimée après cette découverte, afin de ne pas écraser le comportement plus complet déjà présent. **Aucun nouveau correctif SQL de session de paiement ne subsiste dans cette passe.**

## Validation et limites

- Les fichiers modifiés ont été relus depuis GitHub après écriture.
- Le fichier `order_delivery_contract_test.sql` annonce 14 assertions, dont une sur l'immuabilité de la référence fournisseur ; `phase1_commerce_integrity_test.sql` annonce 20 assertions complémentaires. Ces fichiers n'ont pas été exécutés dans cette passe.
- Aucun lancement local de `flutter analyze`, `flutter test`, Deno tests ou pgTAP n'a été effectué dans cette passe.
- Le dernier statut combiné GitHub consulté pour le commit de travail ne rapporte aucun status check (`statuses: []`). Il ne faut donc pas considérer cette passe comme validée par CI.
- Aucun paiement réel, remboursement ou mouvement financier n'a été effectué.
- Aucune migration distante, aucun déploiement et aucune modification de `main` n'ont été effectués.

## État de la branche

Dernière comparaison vérifiée avec `main` au commit `9b70580f322814d6decf9eeac2e5d93aa01e44e9` (avant le dernier addendum documentaire) :
- branche de maintenance : 207 commits en avance ;
- branche de maintenance : 1 commit en retard ;
- état : divergé.

Ne pas fusionner automatiquement. Une revue de synchronisation de l'unique commit manquant et une validation CI complète restent nécessaires.

## Addendum — vérification des références de session concurrentes (16 novembre 2026)

Relecture de l'arbre Git de la branche après l'ajout de cet audit :

- Le fichier `supabase/migrations/20261116120000_prevent_competing_payment_sessions.sql` **n'est pas présent dans l'arbre actuel**. Une migration candidate de ce nom a été créée temporairement pendant l'audit, puis supprimée après découverte du garde plus complet déjà présent.
- La migration existante `20261115191336_phase1_commerce_integrity_final.sql` définit déjà `prepare_payment_processing` avec un verrou `FOR UPDATE` et une garde qui refuse toute nouvelle référence quand `provider_reference` est déjà non vide, quel que soit le statut courant, via `payment_checkout_reference_conflict`. Cette garde ne doit pas être remplacée par une condition limitée à `PROCESSING`.
- Le contrat pgTAP `order_delivery_contract_test.sql` annonce **14 assertions** et inclut un contrôle statique de cette immutabilité. Ce test n'a pas été exécuté dans cette passe ; aucun nouveau run n'a été déclenché.

### Risque fournisseur résiduel

La création de session Wave/CinetPay précède l'appel à `prepare_payment_processing`. Deux requêtes concurrentes peuvent donc encore créer deux objets externes avant que la ligne de paiement ne soit verrouillée. La garde SQL empêche que la seconde référence remplace la première et l'Edge Function refuse de retourner l'URL concurrente, mais l'objet fournisseur perdant peut rester ouvert/orphelin. La résolution complète exige un protocole serveur de réservation idempotente avant l'appel fournisseur, ou une annulation/expiration vérifiée de l'objet perdant lorsque l'API le permet, plus des tests de concurrence et de rapprochement.

Les chemins de réutilisation des sessions existantes dans les Edge Functions v3 sont actuellement déclenchés lorsque le paiement est `PROCESSING`. Une référence non vide avec un statut incohérent `PENDING` doit être traitée comme un état de rapprochement, pas comme une autorisation de créer une nouvelle session. Ce cas doit être couvert dans les prochains tests d'intégration.

**Portée :** audit, correction Flutter du panier et assertion pgTAP de contrat conservés sur la branche de maintenance. Aucune migration Supabase distante, session fournisseur, transaction financière ou donnée utilisateur n'a été modifiée.
