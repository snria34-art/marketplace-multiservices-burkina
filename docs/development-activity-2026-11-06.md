# Activité de correction et qualité — 6 novembre 2026

## Périmètre

Dépôt privé `adjasanou49-max/marketplace-multiservices-burkina`, branche `main`.

Les corrections ci-dessous ont été envoyées directement dans GitHub puis relues depuis la branche principale. Les contrôles Supabase de cette session sont restés en lecture seule. Aucun workflow GitHub Actions, build Flutter, test automatisé, migration de production, paiement, notification de test ou campagne n'a été lancé.

## Corrections livrées

### 1. Renouvellement des images produits signées

Fichier : `lib/features/catalog/data/catalog_repository.dart`

Les URL signées du bucket `product-media` étaient gardées dans le cache mémoire sans date d'expiration, alors qu'elles sont générées pour une durée d'une heure.

Correction :
- conservation de la requête Future en cours pour éviter les appels Storage concurrents ;
- renouvellement préventif après 55 minutes ;
- suppression du cache lorsqu'une URL n'est pas créée ou qu'une erreur empêche le résultat ;
- aucune modification des buckets, ACL, politiques RLS ou objets Storage.

Commit : `822ace3ef17ef2b2aadf277045275d6b5ce21e51`.

### 2. Désactivation du token avant déconnexion

Fichier : `lib/core/notifications/push_notification_service.dart`

Le listener appelait le RPC de désactivation après l'événement `signedOut`. Cet événement est émis après suppression de la session ; le RPC filtré par `auth.uid()` ne dispose alors plus de l'identité requise.

Correction :
- ajout de `signOutAndDeactivateCurrentDevice()` ;
- appel de `deactivate_notification_device` tant que la session authentifiée existe ;
- déconnexion annulée si la désactivation serveur échoue, pour que l'interface puisse permettre une nouvelle tentative ;
- suppression de l'appel RPC tardif dans le listener `signedOut`.

Commit : `0be8a35f6b95ea8d0d4b36faaf6f80a7ce96aafd`.

**Intégration restante :** toute future interface de déconnexion doit utiliser cette méthode. L'implémentation de l'écran de déconnexion et les essais de session expirée / réseau indisponible restent nécessaires. Linear : RIA-26.

### 3. Gestion des erreurs du flux d'authentification

Fichier : `lib/core/notifications/push_notification_service.dart`

Ajout d'un gestionnaire `onError` à `onAuthStateChange.listen`. Les erreurs de rafraîchissement et de réseau émises par le flux sont maintenant traitées et consignées uniquement en mode debug.

Commit : `a37c20140759e2bd3b9e6b4cf289648468fdf9b0`.

### 4. Documentation des notifications

Fichier : `docs/push-notifications.md`

Le document a été ramené à un état de référence unique : Edge Function version 10, limite de concurrence, secret FCM manquant, absence de validation sur téléphone, limites du suivi par appareil et procédure de désactivation avant déconnexion. Les paragraphes contradictoires d'anciennes versions ont été retirés.

Commits documentaires :
- `089c35672ad365d3920636723df5d3595173a407`
- `193eb19dd9babaec864af9e4db29036122f62792`
- `9c91904c339be1008907f3a0096d5a211aef148d`

## Risques toujours ouverts

### Remboursements partiels multi-boutiques — priorité haute

La fonction serveur `public.complete_refund(uuid,text)` répartit le remboursement au prorata sur tous les groupes vendeurs de la commande. Le modèle `refunds` actuel ne conserve pas le groupe ni les articles réellement concernés. Cela peut créer un débit dans le ledger d'un vendeur non concerné par le remboursement.

La fonction reste réservée à `postgres` et `service_role` ; ce constat est un défaut d'allocation métier/financière, pas une permission RPC accordée au client.

Aucune fonction de paiement, aucun ledger ni solde n'a été modifié. Une tâche prioritaire a été créée dans Linear : RIA-25.

### FCM non configuré

La fonction `dispatch-push-notifications` est en version 10 ACTIVE. Les journaux observés indiquent `fcm_service_account_missing` et `hasFcmProjectId: false`. Les secrets `FCM_SERVICE_ACCOUNT_JSON` et `FCM_PROJECT_ID` manquent dans l'environnement observé.

Le code conserve HTTP 503 plutôt que de marquer à tort les notifications comme envoyées. La réception sur appareil n'est pas validée. Aucun secret Firebase n'a été lu ou écrit. La connexion Firebase n'est pas nécessaire pour les corrections indépendantes livrées ici.

### Exposition PostGIS

L'advisor Supabase continue de signaler `public.spatial_ref_sys` sans RLS. Le propriétaire est `supabase_admin` et la session connectée ne dispose pas des privilèges du propriétaire pour corriger cette table. Aucune tentative de contournement ou modification des catalogues système n'a été faite.

### Instrumentation produit

Le projet PostHog connecté est encore à `ingested_event=false`. Le SDK Flutter n'est pas présent dans `pubspec.yaml`. Son ajout nécessite de mettre à jour le lockfile avec le résolveur Flutter/Pub pour éviter un état de dépendances incohérent ; aucun faux lockfile n'a été écrit. L'intégration PostHog est à planifier, avec filtrage des données personnelles et consentement adapté.

## Baseline de validation observée

- Environ 136 chemins de code sous `lib/`.
- 41 Edge Functions dans le dépôt.
- 3 fichiers de tests Dart.
- 321 migrations recensées dans l'historique de la base Supabase active.
- Historique SQL ancien du dépôt encore incomplet pour démontrer une reconstruction locale intégrale.
- Aucun résultat Flutter analyze, test, build ou CI n'est revendiqué pour les commits de cette intervention.

## Suivi qualité

- Linear RIA-25 : allocation fiable des remboursements partiels multi-boutiques.
- Linear RIA-26 : intégrer la désactivation du token dans chaque interface de déconnexion.
- Linear RIA-27 : validation mesurable des parcours critiques, sécurité, charge et restauration.

Le taux cible de 99 % reste un objectif. Il ne sera annoncé comme atteint qu'après exécution des contrôles définis, fermeture des défauts P0/P1 et mesure reproductible sur un commit candidat.


## Corrections complémentaires — commandes, paiement et livraison

### 5. Événements Realtime limités à la ressource concernée

Fichiers :
- `lib/features/notifications/presentation/notifications_page.dart`
- `lib/features/checkout/presentation/order_details_page.dart`

Les notifications écoutent désormais uniquement les changements de lignes portant le `user_id` de la session. Le détail d'une commande filtre les événements `payments` par `order_id`, `orders` par `id`, les groupes par `order_id` et les colis par les `order_group_id` de la commande. Le rechargement déclenché par n'importe quelle notification de l'utilisateur a été retiré de l'écran de commande, car cette donnée n'est pas nécessaire à son affichage.

Commits :
- `73677a04b22a15cc47cac3f5f58f9ccee4ae4db0`
- `6bb133f80397c5e6bae397a1f78cdec6ba7def6f`

### 6. Protection du lien de paiement

Fichier : `lib/features/checkout/presentation/checkout_page.dart`

Avant d'ouvrir le guichet externe, le client vérifie maintenant que la réponse contient une URL analysable, en HTTPS, avec un hôte et sans identifiants utilisateur intégrés dans l'URL. Une URL non sécurisée ou malformée est rejetée.

Commit : `b1d9eae4b07c645fe93a4c3185af46320c262e44`.

Cette vérification côté client complète les contrôles serveur ; elle ne remplace pas la validation du fournisseur côté Edge Function.

### 7. Reprise du calcul de livraison

Fichier : `lib/features/checkout/presentation/checkout_page.dart`

Si le calcul initial du devis échoue alors que l'adresse est déjà sélectionnée, le client dispose maintenant d'une action explicite pour relancer le calcul. Un état de chargement et un état d'échec sont affichés. Les identifiants de requête conservent la protection contre l'association d'un devis obsolète à une nouvelle adresse.

Commit : `8c0a72ccd481304014f0a823d0820c12817ea691`.

### 8. Chargement des positions et Realtime de livraison

Fichiers :
- `lib/features/delivery/data/delivery_repository.dart`
- `lib/features/delivery/presentation/delivery_tracking_page.dart`

Les positions sont maintenant récupérées une seule fois par livreur distinct, avec des requêtes parallèles, au lieu d'une requête séquentielle par colis. Le suivi choisit uniquement une affectation de livreur active. Les abonnements Realtime sont limités aux identifiants de livreurs et de colis liés à la commande consultée. L'initialisation asynchrone nettoie correctement le canal si l'écran est fermé pendant sa création.

Commits :
- `094f062026c04b8e648d5c0caab63e406ebb5bf2`
- `3b02859742c059636da68d052f5acfd6dc41057a`
- `ff9fd5dde0760946133c287c8867abfa93677a71`
- `8f2b9bf92394b6b7591471dc29e0fe717cfe9702`

### Contrôle des fichiers

Chaque fichier modifié a été relu depuis `main` après l'écriture. Le SDK Dart/Flutter n'est pas disponible dans l'environnement d'exécution de cette session : aucune analyse de compilation ni test n'est déclaré réussi. Aucun workflow, build, test payant, paiement réel, push ou migration de production n'a été déclenché.

### 9. Sélection de l’adresse nouvellement créée au checkout

Fichier : `lib/features/checkout/presentation/checkout_page.dart`

Après l'enregistrement d'une nouvelle adresse, le checkout conservait auparavant l'adresse déjà sélectionnée. Le devis et la commande pouvaient donc rester associés à l'ancienne adresse malgré l'ajout de la nouvelle.

Correction :
- récupération de la ligne réellement créée par `createAddress` ;
- validation de la présence de son identifiant ;
- sélection immédiate de cette adresse dans l'écran ;
- invalidation de l'ancien devis puis recalcul sur la nouvelle adresse ;
- protection conservée contre les réponses asynchrones obsolètes grâce au compteur de requêtes existant.

Commit : `fd8462b3752337bcc2b69ed29831b328a7184761`.

Le changement a été relu depuis `main`. Aucun test Flutter ni build n'a été exécuté dans cette session, faute de SDK Flutter/Dart disponible.

### 10. Protection des écrans vendeur pendant les opérations asynchrones

Fichier : `lib/features/seller/presentation/seller_products_page.dart`

Plusieurs opérations de création de produit, de sélection de photos et de modification du stock reprenaient l'exécution après des `await` sans vérifier que l'écran était toujours monté. Une navigation pendant le chargement ou l'ouverture du sélecteur pouvait conduire à l'utilisation d'un `BuildContext` démonté ou d'un provider après destruction du widget.

Correction :
- vérification de `mounted` après le chargement des boutiques et catégories ;
- arrêt de la suite du formulaire si l'écran est fermé avant son retour ;
- contrôles après les sélecteurs d'images et avant l'ouverture des dialogues d'emballage ;
- vérification après le dialogue de stock avant de relire le provider.

Commit : `51f4251f073b575212f303dc773f17c5b112d59d`.

Le fichier a été relu sur `main`. Les tests et l'analyse Flutter restent à exécuter dans un environnement disposant du SDK.

### 11. Message exact en cas d’échec après création du produit

Fichier : `lib/features/seller/presentation/seller_products_page.dart`

Le produit est créé côté serveur avant la sélection et le téléversement de ses photos. En cas d'échec d'une étape ultérieure, l'ancienne interface affichait à tort un échec global de création, alors que le produit existait déjà en brouillon. Cela pouvait provoquer la création de doublons lors d'une nouvelle tentative.

Correction :
- mémorisation de l'identifiant retourné après la création ;
- rejet d'un identifiant vide ou égal à `null` ;
- message distinct selon que la création elle-même a échoué ou que les photos/la validation ont échoué après création ;
- indication explicite de ne pas recréer le produit et de reprendre l'ajout des photos depuis la liste.

Commit : `7472cdc366a3f7faa89b1ff28b0341847605b36a`.

Le fichier a été relu depuis `main`. Aucun test automatisé ou build Flutter n'a été exécuté.

### 12. Rafraîchissement de la sélection initiale du checkout

Fichier : `lib/features/checkout/presentation/checkout_page.dart`

Les valeurs locales de l'adresse sélectionnée et du devis étaient calculées avant la construction du `FutureBuilder`. Quand le chargement automatique des adresses se terminait, le `FutureBuilder` pouvait reconstruire sa propre zone avec les anciennes valeurs capturées, alors que l'état interne contenait déjà une adresse. Le bouton de commande pouvait donc rester désactivé.

Correction :
- lecture de l'adresse sélectionnée, du montant, de la distance et du nombre d'arrêts à l'intérieur du callback `builder` ;
- chaque reconstruction du `FutureBuilder` relit maintenant l'état courant au lieu d'utiliser des valeurs capturées avant le chargement.

Commit : `cec45abff5a772b3c0cae067b01be0d61dbdc715`.

Le changement a été relu sur `main`. Le comportement reste à valider par test Flutter sur appareil ou émulateur.

### 13. Messages de connexion après retour réseau

Fichier : `lib/features/auth/presentation/sign_in_page.dart`

La page pouvait afficher un SnackBar après le retour d'une requête d'inscription ou de connexion, même si l'utilisateur avait déjà quitté l'écran. Le helper `_show` utilise maintenant `mounted` avant d'accéder au `ScaffoldMessenger`.

Commit : `8dc8dd7a65b21cf55854daa37f4d52f54ca654a8`.

### Vérification des chemins de déconnexion

La recherche du code Flutter ne retrouve pas de commande `auth.signOut()` appelée depuis une interface. La méthode `PushNotificationService.signOutAndDeactivateCurrentDevice()` existe, mais aucun écran de déconnexion n'a été identifié à brancher. RIA-26 reste donc ouvert : il faudra intégrer cette méthode au moment où les commandes de déconnexion seront ajoutées, puis tester les cas session expirée et réseau indisponible. Aucune déconnexion réelle n'a été exécutée.


### 14. Suppression sécurisée des articles du panier

Fichiers :
- `lib/features/cart/data/cart_repository.dart`
- `lib/features/cart/presentation/cart_page.dart`

L'ancienne méthode de suppression exécutait un `DELETE` direct sur `cart_items`. La base dispose déjà d'une RPC `set_cart_item_quantity` qui vérifie la propriété du panier, refuse les articles ne relevant pas du client connecté et met à jour `carts.updated_at`. Cette RPC supprime l'article lorsque la quantité demandée vaut zéro.

Correction :
- `CartRepository.remove` passe désormais par la RPC existante avec quantité zéro ;
- l'interface affiche une action explicite « Retirer du panier » ;
- le chemin de suppression de l'interface utilise cette méthode sécurisée ;
- le contrôle serveur de propriété, de compte actif et la mise à jour de la date du panier restent centralisés dans la fonction SQL existante.

Commits :
- `4553f9be92ce0566433ec9c013f1777a53473460`
- `7687962fa64a9368f7cc6fd88fce96aad3225c40`
- `a071ac53fc62e9e8404b3eb7857e23927eaea51e`

La fonction SQL et son comportement ont été vérifiés en lecture seule sur Supabase. Les deux fichiers Flutter ont été relus depuis `main`. Aucun test Flutter, analyse statique ni build n'a été exécuté dans cette session.


### 15. Audit du stock par variante — point fonctionnel ouvert

Fichiers examinés :
- `lib/features/seller/data/seller_products_repository.dart`
- `lib/features/seller/presentation/seller_products_page.dart`
- fonctions Supabase `set_seller_stock` et `set_seller_variant_stock`

Le serveur possède déjà une RPC dédiée au stock par variante, avec contrôle de propriété vendeur, contrôle des quantités réservées et journalisation des mouvements. L'interface Flutter actuelle ne charge ni les variantes ni leur inventaire et ne propose que l'édition du stock parent. Or la RPC `set_seller_stock` bloque explicitement le stock parent lorsqu'un produit utilise le stock par variante.

Aucune modification hasardeuse du schéma ou des fonctions SQL n'a été faite. Le manque est dans l'interface et le repository Flutter. Une tâche dédiée a été créée dans Linear : [RIA-28 — édition du stock par variante](https://linear.app/faso/issue/RIA-28/catalogue-ajouter-ledition-du-stock-par-variante-dans-lespace-vendeur).

### Vérification de suppression du panier

La fonction SQL `set_cart_item_quantity` a été consultée en lecture seule. Elle vérifie que l'article appartient au panier actif du client connecté, exige un compte actif, supprime l'article si la quantité vaut zéro et met à jour `carts.updated_at`. Le client utilise maintenant cette RPC pour retirer un article, plutôt qu'un `DELETE` direct.

Les modifications Flutter ont été relues sur `main`. Aucun test ni build n'a été exécuté.


### 16. Édition du stock par variante — code ajouté, migration en attente

Fichiers ajoutés/modifiés :
- `supabase/migrations/20261106180000_add_secure_seller_variant_inventory_read.sql`
- `lib/features/seller/data/seller_products_repository.dart`
- `lib/features/seller/presentation/seller_products_page.dart`

La table `product_variant_inventory` refuse la lecture directe aux rôles clients. Pour ne pas ouvrir cette table, une RPC `get_seller_product_variant_inventory(uuid)` a été ajoutée dans une migration versionnée. Elle :
- exige un compte actif et une session authentifiée ;
- vérifie côté serveur que le produit appartient au vendeur connecté ;
- renvoie uniquement les variantes de ce produit et leurs quantités totale/réservée ;
- n'accorde l'exécution qu'au rôle `authenticated`, sans accès `anon`.

Le repository Flutter appelle cette RPC pour lire les stocks et appelle la RPC existante `set_seller_variant_stock` pour modifier une variante. L'écran vendeur oriente automatiquement vers l'éditeur par variante lorsque le produit possède des variantes ; le stock parent reste utilisé pour les produits sans variante. Après une modification, la liste est fermée et rechargée depuis le serveur.

**Important :** la migration est seulement enregistrée dans GitHub. Elle n'a pas été appliquée au projet Supabase de production. Tant qu'elle n'est pas appliquée, la lecture des variantes peut échouer ; l'interface conserve alors l'éditeur de stock classique et la RPC serveur continue de refuser une modification parent si le produit utilise le stock par variante. Ne pas déclarer cette fonctionnalité opérationnelle en production avant application contrôlée de la migration et tests avec deux comptes vendeurs.

Commits :
- `d25595f1188dc8fa50701aabf304e5db1a01d2e0` — migration RPC lecture propriétaire
- `113cf3b9b3966477d51e5b1b84ee5522d5e8b771` — repository
- `1d5319e14061e02a00c2e659c2ed2d4673176ac8` — interface
- `22e9d810c313392810ac6b1fcf367ccb047a411c` — repli sûr avant déploiement de la migration

Aucun changement SQL n'a été appliqué à la base de production et aucun test Flutter/build n'a été exécuté.

### 17. Corrections des branches switch et vérification réelle de la migration vendeur

Fichiers :
- lib/core/notifications/push_notification_service.dart
- lib/features/verticals/presentation/vertical_discovery_page.dart

Les branches non vides des deux instructions switch asynchrones ont été terminées explicitement. Cela retire les fins de branche ambiguës qui empêchaient une validation Dart fiable et garantit qu'une action d'un module vertical ne continue pas dans le cas suivant.

Commits :
- 975df8e74f3d8e2e5bf236ca3c50876dd46bc4db — terminaison des branches d'état d'authentification FCM.
- ca2c46af9ed0076b7d040a5fe1927c1100b4eeb3 — terminaison des actions des modules verticaux.

Vérification Supabase en lecture seule du 6 novembre 2026 :
- les colonnes utilisées par get_seller_product_variant_inventory existent ;
- les contraintes de stock interdisent les quantités négatives et les réservations supérieures au stock ;
- la table product_variant_inventory interdit l'accès direct des rôles anon et authenticated ;
- la fonction public.get_seller_product_variant_inventory(uuid) est absente de la base ;
- la version de migration 20261106180000 est absente de supabase_migrations.schema_migrations.

Conséquence : le code Flutter et la migration sont dans GitHub, mais la lecture sécurisée des variantes n'est pas encore disponible dans le projet Supabase actif. Le stock par variante reste bloqué en production tant que cette migration n'est pas déployée et testée. Aucune migration n'a été appliquée pendant cet audit.

Aucun test Dart/Flutter ni analyse statique n'a été exécuté : le SDK n'est pas installé dans l'environnement de cette session. Les deux corrections doivent être validées avec flutter analyze, les tests et un build sur un environnement Flutter avant d'être considérées comme certifiées.

### 18. Protection des actions asynchrones après navigation

Les parcours concernés vérifient maintenant que l'écran est toujours monté après le retour d'une boîte de dialogue ou d'un sélecteur avant d'accéder à Riverpod, au contexte Flutter ou de poursuivre une action sensible. Les corrections couvrent :
- demandes de trajets, fret, colis et suivi dans les modules verticaux ;
- captures de preuves de retrait/livraison et saisie des codes par les livreurs ;
- demande de paiement vendeur ;
- création de demandes de service et de transport ;
- création/modification de boutique, paramètres vendeur, coupons et promotions ;
- décisions de modération, blocage/réactivation des comptes et actions de remboursement administrateur ;
- ajout d'un associé après vérification du paiement.

Commits de cette série :
- de9e82490f0ea3d5881f51f478c5e0b4f2967b90
- c14878b6ee553e5d3c3cfa93790be56385a4799e
- a61d72f24aab31201f89ec2f794813a3343b56be
- c8e57a8ad0a09641867d230f49e7dfbf6c49f89e
- 3b1d7202a6acd37fccfe364434f591519349a9c5
- 20839ddbcb8565bf516b90ed48c03d456273d5c9
- f621f99a22bcb11eb61f6ce8ff8533d66088cd34
- fe190c38e5fd400c77dbc4a95310477e2c107526
- cc6820aed129d261c148c1734879feb068ea544e
- fdd9958766142417f88c077ab15a0fe4f444e849
- 8bb3ff30fbcba7c1480129e88bfd7d3e79861d16
- bd750a29ab759ff33fbc83e3132c15822bb81ec8
- af4152bc439fcf0d2c9f0eddde64203b1d24eb2e
- c532ead2d67961434b532872e3b054618c0488a2
- 7939ba264c3b68582129b0a63481c72761ffcc99

Ces modifications limitent les opérations déclenchées après fermeture d'un écran. Elles ne remplacent pas les contrôles d'autorisation et de validité exécutés par les RPC serveur. Les parcours financiers doivent encore être testés sur environnement isolé avant validation.

### 19. Isolation des erreurs de la pile FCM et confirmation du risque de remboursement

Fichier : lib/core/notifications/push_notification_service.dart

Les initialisations des notifications locales, des permissions, de l'affichage au premier plan et du handler d'arrière-plan sont maintenant isolées. Les callbacks des notifications au premier plan, à l'ouverture et au démarrage interceptent aussi leurs propres erreurs. Les détails ne sont écrits qu'en mode debug. Une panne de plugin ne doit donc plus devenir une erreur asynchrone non gérée dans le démarrage de la pile push.

Commit : 819c7d007c118d274ac3a11ec5aca36c7e2f0504.

Contrôle financier en lecture seule :
- admin_complete_manual_refund appelle public.complete_refund ;
- execute-payment-refund appelle aussi public.complete_refund après confirmation Wave ;
- complete_refund répartit chaque remboursement au prorata sur tous les order_groups de la commande ;
- la table refunds ne permet pas d'identifier le groupe ou l'article réellement remboursé.

Le risque de RIA-25 est donc confirmé dans les deux parcours de finalisation présents dans l'application. Une demande partielle ciblée sur un vendeur peut débiter les autres vendeurs de la même commande. Aucune finalisation de remboursement, aucun paiement fournisseur et aucune écriture de ledger n'ont été exécutés. Les parcours financiers restent non certifiés jusqu'à la correction du modèle d'allocation et aux tests isolés.

### 20. Annulation correcte des congés mécanicien et garde des derniers dialogues

L'écran mécanicien n'enregistre plus une période de congé lorsque le mécanicien annule la saisie du motif. L'annulation conserve la disponibilité précédemment choisie, ne crée pas de congé et la page peut tout de même rafraîchir son état. Le contrôleur du motif est désormais libéré après la fermeture du dialogue. Le chargement du profil mécanicien est aussi suivi d'une vérification du cycle de vie avant d'ouvrir la suite des dialogues.

Les derniers parcours protégés après fermeture d'un écran sont : réponse de modération vendeur avec média, ajout d'adresse au checkout, rédaction d'un avis, et choix de disponibilité/congé mécanicien.

Commits :
- 966a02349042015d702e70c209545ff8e8e1d8d8 — vérifications additionnelles des dialogues des modules verticaux.
- c0501ffa312c0d69aaa427e2c1fda7f63956c68c — protection du dialogue de réponse de modération et des sélecteurs média.
- 60862986f7df605e9c06e6febb8a2f24242e7e9f — protection après création d'adresse.
- 75e70e3b4aa22757358f64d854444e43668f62c4 — protection après dialogue d'avis.
- a50769addacaf7b4ec8b9d8458a73ed65b5ea84b — protection des dialogues mécanicien et libération du contrôleur.
- 88c6183ca152b38a126eec18d0288463206a1946 — annulation effective du congé mécanicien.
- 7613ddac0b3d30751e2a3e1f551c91ab3823e527 — formatage du bloc RPC de congé.

Aucune action de congé, de modération, de remboursement ou de paiement n'a été exécutée pour valider ces changements ; ils restent à tester sur un environnement de test.

### 21. Dernière garde du rendez-vous beauté

Le formulaire de réservation beauté vérifie maintenant que l'écran est toujours monté après le sélecteur de date/heure avant de poursuivre l'enregistrement. Cela aligne ce parcours avec les autres réservations des modules verticaux.

Commit : 3e3d0834cfda979737241256593655ca7d65408d.
