# Regroupages, délais de préparation et commandes de restauration

## Objectif

Décrire les règles métier nécessaires pour rendre les achats groupés, la préparation des commandes et la personnalisation des plats fiables. Cette spécification est préparatoire : elle n'est ni une migration Supabase appliquée ni une activation en production.

## 1. Achats groupés — état implémenté dans cette branche

La table `group_buys` existante porte déjà :
- `starts_at` et `ends_at` : dates de début et de fin ;
- `target_quantity` et `current_quantity` : objectif et participation ;
- `status` et `group_price`.

Le client Flutter de cette branche affiche maintenant le nom du produit, sa description, le temps écoulé depuis le début, le décompte seconde par seconde jusqu'à la fin, le nombre de participants et une barre de progression.

La page écoute aussi les changements de `group_buys` en Supabase Realtime, avec une actualisation de secours toutes les 45 secondes. **La table n'est pas ajoutée à la publication `supabase_realtime` dans main** : le patch de revue associé contient le bloc SQL requis. Tant que cette migration n'est pas générée puis appliquée, le compteur local fonctionne mais les nouveaux participants des autres clients peuvent apparaître seulement au rafraîchissement de secours.

Règles à conserver :
- l'heure de début/fin vient du serveur, pas d'une horloge cliente ;
- l'inscription à un groupe reste verrouillée transactionnellement par `join_group_buy` ;
- les achats sont bloqués si le groupe a atteint sa capacité ou est terminé ;
- aucun prix ou statut n'est considéré comme confirmé depuis un simple compteur local.

## 2. Produits non alimentaires : préparation 4 h / 24 h / 48 h

Le vendeur doit pouvoir définir un délai de préparation parmi :
- 4 heures ;
- 24 heures ;
- 48 heures.

Le choix est enregistré côté serveur au niveau du produit (valeur par défaut de la boutique possible), puis figé sur la ligne/groupe de commande lors du checkout. Le client voit une heure/date estimée de disponibilité, calculée depuis l'heure de confirmation du paiement et le délai retenu. Pour une commande multi-boutiques, chaque groupe vendeur possède son propre délai.

À ne pas confondre :
- délai de préparation du vendeur ;
- délai de prise en charge du livreur ;
- durée du trajet ;
- fenêtre de livraison promise au client.

La date promise doit être stockée en `timestamptz` UTC et affichée dans le fuseau `Africa/Ouagadougou`. Si la préparation dépasse le délai initial, le vendeur doit transmettre une nouvelle estimation et le client doit recevoir une notification.

## 3. Restaurants : fenêtre souhaitée par le client

Choix proposés au checkout du restaurant :
- 30, 40 ou 50 minutes ;
- 1, 2, 3, 4, 5, 6 ou 7 heures.

La fenêtre représente le délai maximum souhaité par le client à partir de l'acceptation de la demande, sauf si le métier décide explicitement d'en faire une heure de livraison fixe. Le vendeur voit la fenêtre, son temps de préparation configuré et l'heure limite correspondante.

État recommandé du service de réservation :
- `PENDING` : demande envoyée, le restaurant doit répondre ;
- `ACCEPTED` : le restaurant confirme qu'il peut préparer et livrer dans la fenêtre ;
- `REJECTED` : le restaurant ne peut pas respecter la fenêtre ;
- `EXPIRED` : aucune réponse avant la date limite de confirmation.

Une demande doit être liée à un `order_group_id`, pas uniquement à l'ordre global, car une commande peut contenir plusieurs boutiques. Les événements sont auditables et idempotents. Une double pression sur accepter/refuser ne peut pas produire deux transitions.

Avant d'accepter, le serveur vérifie :
1. que le restaurant appartient bien au vendeur connecté ;
2. que le groupe de commande est encore éligible ;
3. que la fenêtre choisie fait partie des valeurs permises ;
4. que le délai de préparation du restaurant et les paramètres de livraison permettent de respecter l'heure limite ;
5. que la commande n'a pas déjà été acceptée, refusée, annulée ou envoyée au livreur.

## 4. Refus et remboursement : verrou financier indispensable

Le flux actuel de production crée une commande, ouvre le paiement, puis le marchand peut intervenir. Le projet possède une table `refunds` et une Edge Function de remboursement, mais l'audit du modèle financier indique :
- le remboursement est actuellement attaché à la commande et au paiement, pas à un groupe vendeur ou à une ligne de commande ;
- la remise du checkout n'est pas ventilée en snapshots financiers par groupe ;
- la routine existante peut ventiler un remboursement partiel au prorata sur les mauvais vendeurs ;
- l'automatisation Edge connue traite Wave ; CinetPay est explicitement renvoyé vers un traitement manuel.

Par conséquent, **il ne faut pas brancher un bouton de refus qui crédite un portefeuille ou déclenche un remboursement prétendument automatique aujourd'hui**. Il n'existe pas de table de portefeuille client dans le schéma inspecté. Un remboursement doit rendre l'argent au moyen confirmé lors du paiement, pas créditer arbitrairement un solde interne.

Deux architectures possibles :
A. Pré-acceptation du restaurant avant le paiement définitif (la plus simple pour éviter un remboursement après refus), à condition que le prestataire de paiement supporte réellement l'autorisation/capture différée et que le flux multi-boutiques soit adapté.
B. Paiement puis décision du restaurant, avec allocations immuables par groupe, remboursement provider idempotent, suivi des statuts, rapprochement des callbacks et traitement distinct Wave/CinetPay. Ce parcours nécessite de corriger le modèle AUD-02 avant activation.

Aucune annulation financière automatique ne doit être activée tant que les allocations exactes et le parcours fournisseur ne passent pas les tests isolés.

## 5. Personnalisation des plats et menus

Le restaurant configure chaque produit avec des groupes d'options. Exemples :

- **Choix du plat** : soupe poisson, viande ou poulet ; taille/portion ;
- **Ingrédients** : piment, sauce soja, légumes, salade, fromage, steak ;
- **Sauces** : mayonnaise, ketchup, sauce piquante, autres sauces ;
- **Préférences** : sans sel, sans sucre, sans fromage, sans piment ;
- **Quantité d'un ingrédient** : peu, normal, beaucoup.

Modèle de données recommandé :
- `product_option_groups` : produit, nom, type de choix (unique/multiple), minimum et maximum sélectionnables, caractère obligatoire, ordre d'affichage ;
- `product_options` : groupe, nom, disponibilité, delta de prix, ingrédient inclus par défaut ou ajout facultatif ;
- `product_option_levels` : option, niveau (LESS/NORMAL/EXTRA), delta de prix configuré par le vendeur ;
- `cart_item_customizations` ou un snapshot JSON validé : choix exacts et tarifs utilisés ;
- snapshots de personnalisation sur `order_items` pour conserver ce qui a effectivement été commandé.

Calcul proposé :
`prix final = prix du produit/variante + somme des suppléments configurés`.

Le prix affiché évolue immédiatement quand le client choisit les options, mais **le serveur recalcule et valide toujours le prix au panier et au checkout**. Le client ne peut pas envoyer un delta de prix arbitraire. Le serveur vérifie que chaque option appartient bien au produit, est active, que les groupes obligatoires sont remplis et que les limites min/max sont respectées.

Les quantités « peu / normal / beaucoup » doivent être de vrais niveaux tarifés configurés par le vendeur. « Sans fromage » doit être un choix explicite de retrait, pas une note libre que la cuisine risque de manquer.

Deux configurations différentes du même produit doivent rester deux lignes distinctes du panier. L'index unique actuel `(cart_id, product_id, variant_id)` ne suffit pas : il faudra une clé de configuration stable et un RPC de panier sécurisé qui valide les options et calcule le prix côté serveur.

## 6. Perf, disponibilité et expérience

- Une seule requête de lecture paginée pour les campagnes actives ; pas de polling fréquent quand l'écran est fermé.
- Realtime uniquement sur les champs du groupe ; actualisation de secours 45 s sur l'écran de regroupage actif.
- Compte à rebours calculé localement entre deux synchronisations, sans appel API chaque seconde.
- Index sur les colonnes de filtrage `status, starts_at, ends_at` déjà existant.
- Les prix des options et le snapshot de commande sont calculés dans une transaction serveur.
- Les événements d'acceptation/refus, de préparation et de remboursement sont idempotents et horodatés.
- Ne pas recharger la totalité du catalogue à chaque modification d'option.
- Ne pas redessiner les écrans finaux avant les captures de référence promises par le propriétaire.

## 7. Conditions de sortie avant production

- migration générée via `supabase migration new` (la CLI n'est pas disponible dans l'environnement de modification actuel) ;
- tests PostgreSQL isolés : ownership vendeur, double accept/refuse, capacité groupe, inventaire, prix option, carte multi-options, annulation multi-boutiques, refund provider idempotence ;
- tests Flutter de compte à rebours, cartes d'options, choix d'heures et changements de prix ;
- validation sandbox Wave et CinetPay ; le remboursement CinetPay reste manuel tant qu'une intégration de sortie d'argent n'est pas développée et approuvée ;
- exécution Flutter CI / Supabase CI confirmée ;
- seulement ensuite revue, fusion et déploiement autorisés.
