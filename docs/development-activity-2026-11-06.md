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

### 22. Message d'erreur honnête pour le stock par variante avant déploiement

L'écran vendeur ne présente plus le stock classique comme disponible sans réserve lorsque le chargement des variantes échoue. Le message précise désormais que le stock parent ne peut être utilisé que pour les produits sans stock par variante. Si la RPC serveur renvoie use_variant_stock_editor, l'interface indique clairement que la migration de lecture des variantes n'est pas déployée et qu'aucune quantité n'a été modifiée. Le cas stock_below_reserved dispose aussi d'un message explicite.

Commit : 226cea1fbc0dcefa9b9dc30a2b01f5f971d27fbf.

### 23. Gestion des erreurs des sélecteurs photo/vidéo vendeur

Les callbacks asynchrones de sélection de photo et de vidéo dans la réponse de modération vendeur interceptent désormais les erreurs du système de fichiers, de la caméra/galerie et de l'initialisation du lecteur vidéo. L'utilisateur reçoit un message d'échec au lieu d'une exception asynchrone non gérée. Les mises à jour d'état restent conditionnées au cycle de vie du dialogue, et le contrôleur vidéo est libéré dans finally.

Commit : dfd0760b6194d031dfccd2abf1492edeb8fada2f.

### 24. Garde des actions de remboursement, litige et retour après dialogue

Dans le détail de commande, les parcours de demande de remboursement, d'ouverture de litige et de retour vérifient maintenant que l'écran est toujours monté après la fermeture du dialogue avant de lire les providers ou d'appeler Supabase. Les parcours litige et retour échouent explicitement si le client Supabase n'est pas disponible, au lieu d'afficher un succès avec un identifiant nul.

La logique financière SQL n'a pas été modifiée. RIA-25 confirme que la fonction de finalisation répartit encore les montants sur tous les groupes de la commande sans allocation explicite. La correction de ce calcul reste bloquée par la règle métier d'allocation et des tests isolés obligatoires ; aucune fonction de remboursement, écriture ledger ou transaction fournisseur n'a été exécutée.

Commit : fbc477e2d482e5414e9bc73c4c03f29e69564ad0.

### 25. Sécurisation des derniers sélecteurs média et date produit

- Le sélecteur de date d'expiration d'un produit vérifie désormais que le formulaire est encore monté avant setState après le DatePicker.
- Les sélecteurs photo et vidéo d'un avis client gèrent désormais les exceptions de galerie, de sélection et d'initialisation du lecteur. Ils arrêtent l'opération si le dialogue a été fermé pendant l'attente, et le contrôleur vidéo est toujours libéré dans finally.

Commits :
- 0ea83371cef3f9da61ef1cadce45186d5b44e44b — date d'expiration produit.
- f9bea997a02e7f7f78e9765ce07922be7c59391c — sélection photo/vidéo des avis.

### 26. Validation HTTPS du paiement repris depuis le détail de commande

L'action « Reprendre le paiement » dans le détail de commande ouvrait auparavant l'URL retournée par la session de paiement sans refaire les contrôles appliqués par le checkout initial. Elle valide maintenant l'URL avant ouverture : syntaxe analysable, schéma HTTPS, hôte présent et absence d'identifiants utilisateur intégrés. La reprise du paiement s'arrête aussi si le dialogue de sélection du fournisseur revient après fermeture de l'écran.

Commit : b28667823294af5d8025a17b8a06f53b29cd9d49.

### 27. Arrêt du lancement du guichet si l'écran de paiement a été fermé

Le checkout initial et la reprise du paiement depuis le détail d'une commande vérifient maintenant le cycle de vie de l'écran immédiatement après la création asynchrone de la session de paiement. Si l'utilisateur a quitté l'écran pendant l'appel réseau, le client n'ouvre plus le navigateur externe au retour de la réponse. Les commandes déjà créées restent consultables depuis l'historique ; aucune transaction fournisseur n'est lancée par cette vérification.

Commits :
- 1e8ba491e5621f94e93bcdd0f880531d7a381e40 — checkout initial.
- 5de2cbf62195762d124eaa4558bd17a552ba1aff — reprise depuis le détail de commande.

- Garde complémentaire dans le checkout : après la création de la commande, le client vérifie désormais que l'écran existe toujours avant de créer la session de paiement. Cela évite de poursuivre le flux externe après une navigation pendant l'enregistrement de la commande. Commit : 814e5dbc0d78bd01514b4b1d3bbf86d69721f692.

### 28. Cycle de vie du GPS livreur, de Realtime et du catalogue

- Le démarrage du partage GPS vérifie maintenant que la page livreur est encore montée après le premier envoi de position, avant d'activer l'état UI et le timer. Le chargement GPS s'arrête aussi si l'écran est quitté pendant l'obtention des coordonnées. Un contrôle redondant après la sélection de photo de livraison a été retiré.
- Le suivi de livraison vérifie le cycle de vie du widget dans son callback post-frame avant d'initialiser Realtime/le timer. Le canal Realtime est désormais retiré via une routine asynchrone protégée, lancée sans laisser d'exception non gérée depuis dispose().
- Le chargement initial des catégories du catalogue s'arrête après la réponse réseau si la page a déjà été détruite, avant de muter l'état local ou de lancer le chargement produit suivant.

Commits :
- 6ff4812db44f3991c47a46d04058dc48ba87c616 — GPS livreur.
- f7c022732b8a214271bd96c5cc619ca9ace55472 — canal Realtime du suivi livraison.
- f2c832d61065fb74bf36a9aab9de39f92a40103d — chargement du catalogue.

### 29. Gestion des erreurs de messagerie et notifications, nettoyage Realtime

- La messagerie ferme l'ancien canal Realtime de façon protégée avant d'ouvrir une nouvelle conversation. Les erreurs de `markRead` sont maintenant affichées à l'utilisateur plutôt que de devenir des futures non gérées depuis le callback de navigation.
- Le nettoyage du canal de messagerie lors de `dispose()` est asynchrone, best-effort et encapsulé ; aucune Future de `removeChannel` n'est abandonnée sans gestion d'erreur.
- L'envoi d'un message vérifie désormais `mounted` juste après l'appel réseau avant de toucher au contrôleur de texte ou à `setState`.
- La page de notifications protège aussi le retrait du canal Realtime et affiche un état d'erreur avec action de reprise lorsque le chargement échoue. Le marquage comme lu est protégé et présente une erreur lisible au lieu de laisser échapper une exception.

Commits :
- 076348276e109dfa05e089ea2a03d647e0c04b8e — messagerie.
- c7a9e0ffe1f49cba68b39d40d487fd79bf42bf55 — notifications.

### 30. Fin de vie des canaux Realtime des commandes, messages et notifications

- Le détail de commande retire désormais son canal Realtime de façon asynchrone protégée pendant dispose(). Les erreurs de souscription initiale sont interceptées et affichées, sans casser le détail de commande ni interrompre les autres éléments de l'écran.
- La messagerie protège la création des abonnements Realtime, coupe le timer et retire le canal lorsqu'on revient à la liste des conversations. Les erreurs de marquage « lu » et de nettoyage ne deviennent plus des Futures non gérées.
- La page de notifications intercepte désormais les erreurs de création de son abonnement Realtime. En cas d'échec, la liste reste utilisable avec l'actualisation manuelle et les erreurs de marquage sont affichées.

Commits :
- b274d10bbda9dc50dc11d990b763a9e85bc36a4a — canal du détail de commande.
- 2e157e0346f9df875504ac936e4f82d014af3d5b — canal de messagerie et retour à la liste.
- 03450f394a47b404fd8263de374b006059a19f71 — initialisation Realtime des notifications.

### 31. Vérification RLS des variantes — alerte écartée après lecture des politiques

Contrôle Supabase en lecture seule : `product_variants.active_account_guard` est bien une politique `RESTRICTIVE` pour `authenticated`, et non une politique permissive. Elle impose donc un compte actif en plus de la politique permissive `product_variants_public_read`, qui ne permet la lecture que des produits actifs, boutiques actives et vérifiées, et articles non expirés. Le droit SQL SELECT ne contourne pas ces conditions RLS.

`product_variant_inventory` conserve RLS activé et aucun privilège SELECT/INSERT/UPDATE/DELETE direct pour `authenticated`; son accès de lecture vendeur passe par la RPC propriétaire dédiée, qui reste en attente du déploiement de sa migration. Aucun changement de politique RLS n'était nécessaire ; aucune modification de production n'a été effectuée.

### 32. Annulation globale des commandes — nouveau blocage métier confirmé

Audit Supabase en lecture seule : `public.transition_order_status(uuid, order_status, text)` reste exécutable par `authenticated`. Elle accepte l'annulation des commandes payées, libère les réservations, mais ne ferme pas explicitement les colis/affectations pré-ramassage, ne bloque pas explicitement les colis déjà pris en charge et ne crée pas de demande de remboursement pour une commande déjà payée. Aucun trigger actif sur `orders` ne complète automatiquement ces actions. Le webhook des paiements tardifs après annulation ne couvre que le scénario inverse.

La recherche Flutter n'a retrouvé aucun appel direct à cette RPC dans les écrans actuels ; le risque demeure sur le point d'entrée SQL accordé au rôle authenticated et à d'autres clients/intégrations.

Tâche prioritaire créée dans Linear : [RIA-29 — sécuriser l'annulation globale et synchroniser colis, affectations et remboursements](https://linear.app/faso/issue/RIA-29/commande-securiser-lannulation-globale-et-synchroniser-colis).

Aucune fonction de transition, réservation de stock, table de commande ou remboursement n'a été modifiée. Une correction de production reste bloquée jusqu'à la définition du traitement des commandes payées et aux tests transactionnels isolés ; elle doit être coordonnée avec RIA-25.

### 33. Vérification finale du cycle de stock et de l'ancienne RPC checkout

Contrôles Supabase en lecture seule :
- `checkout_cart` (RPC accessible à `authenticated`) réserve chaque ligne par `reserve_variant_inventory(product_id, variant_id, quantity)` ;
- `checkout_active_cart` utilise également cette fonction, mais EXECUTE est retiré à `authenticated` et à `anon` : seul `service_role` peut l'appeler ;
- `consume_order_inventory` et `consume_package_inventory` consomment le stock avec `consume_variant_inventory(product_id, variant_id, quantity)` ;
- `cancel_unpaid_order`, les échecs de paiement et l'annulation d'un groupe utilisent `release_variant_inventory` ;
- `package_inventory_consumptions(package_id)` a une clé primaire, ce qui rend la consommation d'un même colis idempotente ;
- les deux fonctions checkout sont les seules fonctions applicatives actuellement trouvées qui insèrent des lignes dans `order_packages`, avec un colis créé par groupe vendeur.

Le constat historique d'octobre selon lequel les commandes utilisaient encore le stock parent est donc dépassé : la réservation, la consommation et la libération par variante sont présentes dans les fonctions actives. Aucune modification du stock ou des fonctions de réservation n'a été nécessaire durant cette vérification.

L'annulation globale par `transition_order_status` reste le défaut SQL ouvert, suivi par Linear RIA-29. Ne pas la confondre avec le chemin `cancel_unpaid_order`, qui est distinct et n'accepte que les commandes en attente de paiement.


### Mise à jour après déploiement AUD-04 — 7 novembre 2026

- Le diagnostic précédent du 6 novembre indiquait correctement que la RPC `get_seller_product_variant_inventory(uuid)` était absente de la base active à ce moment-là.
- La migration a depuis été appliquée via Supabase et inscrite sous le numéro généré `20261106201211`. Le fichier de dépôt a été réaligné sur ce numéro : `supabase/migrations/20261106201211_add_secure_seller_variant_inventory_read.sql`.
- Contrôle SQL après déploiement : la fonction existe, vérifie compte actif et propriété vendeur, autorise EXECUTE à `authenticated` uniquement parmi les rôles clients ; `anon` ne peut pas l'appeler. Les droits directs sur `product_variant_inventory` restent refusés à `anon` et `authenticated`.
- `SellerProductsPage` appelle déjà le lecteur de variantes et la RPC de mise à jour sécurisée. Le chemin de secours vers le stock parent est maintenant interdit lorsqu'une lecture des variantes échoue ; l'interface affiche une erreur et s'arrête sans modifier le stock.
- Une assertion pgTAP a été ajoutée ; `security_regression_test.sql` comporte 45 assertions. Elles n'ont pas été exécutées. Le flux UI doit encore être testé avec un compte vendeur et des variantes de test.
- Aucun stock réel n'a été modifié et aucun compte vendeur n'a été créé.



### AUD-13 — intégration du parcours de déconnexion — 7 novembre 2026

- Création de `lib/core/widgets/account_session_action_button.dart`, ajouté à l'accueil et aux tableaux de bord vendeur, administration et coursier.
- La page d'accès restreint utilise également `signOutAndDeactivateCurrentDevice(client:)`.
- Suppression de la dépendance des écrans à un appel direct `auth.signOut()`; le service commun désactive le token avant de supprimer la session.
- Le service récupère le token FCM courant si Firebase est initialisé mais que le cache local est vide ; il exige ensuite le booléen de confirmation du serveur.
- Un échec du RPC ou de la récupération du token annule la déconnexion et laisse un message de nouvelle tentative.
- Le compte suspendu/bloqué doit pouvoir se déconnecter malgré le guard RLS actif. Migration Supabase appliquée : `20261106203915_secure_notification_device_deactivation_for_blocked_accounts`. La fonction SQL devient `SECURITY DEFINER`, vérifie `auth.uid()`, limite l'UPDATE au token de ce même utilisateur et renvoie un succès idempotent seulement si aucune entrée active correspondante ne reste. Anon n'a pas EXECUTE.
- Tests ajoutés : un test d'interface sans Supabase configuré et une assertion pgTAP ; le fichier de régression SQL passe de 47 à 48 assertions. Tests encore non exécutés faute de runner GitHub opérationnel.
- Aucun token, utilisateur réel ou push n'a été modifié/envoyé.


### AUD-12 — correction des privilèges trop larges du rôle MODERATOR — 7 novembre 2026

- Inspection des fonctions SQL : `public.is_admin_actor()` reconnaissait ADMIN, SUPER_ADMIN et MODERATOR ; ce helper protégeait aussi le tableau de bord général, les réparations/rollback, le health monitor et les règles de retour.
- Application de la migration `20261106204520_restrict_platform_admin_actions_to_registered_admins`. Ces fonctions et les triggers statut profil / documents vendeur exigent maintenant `private.is_admin()`, donc une ligne active dans `admin_users`.
- Les fonctions de modération catalogue et avis conservent la permission `public.is_admin_actor()`.
- Le routeur Flutter distingue désormais les deux routes de modération des autres routes admin. Les modérateurs sans enregistrement admin ne peuvent ouvrir que catalogue et avis.
- Deux tests pgTAP ont été ajoutés ; le fichier atteint 50 assertions (total prévu 63 avec l'autre fichier). Dix tests unitaires de routes couvrent désormais aussi les deux routes modérateur. Aucun test n'a été exécuté car runner CI non attribué.
- Documentation et matrice de permissions créées dans `docs/runbooks/aud-12-admin-rbac-matrix.md`; ticket Linear RIA-30 créé pour la prochaine phase de RBAC.
- Aucun compte propriétaire/administrateur/associé, rôle ni permission n'a été créé dans la base hébergée.



### AUD-14 — implementation du suivi GPS arrière-plan — 7 novembre 2026

- Remplacement de `Timer.periodic(15s)` par le flux natif `Geolocator.getPositionStream()`.
- Dépendances Android/iOS de Geolocator rendues explicites dans `pubspec.yaml` et lockfile : `geolocator_android 5.2.1`, `geolocator_apple 2.4.3`.
- Android : notification persistante de service de premier plan, cadence visée 15 secondes, filtre de déplacement 25 mètres, permissions de localisation précise/approximative et background/foreground service.
- iOS : `AppleSettings.allowBackgroundLocationUpdates=true`, `pauseLocationUpdatesAutomatically=false`, indicateur système actif ; ajout du mode `location` dans `UIBackgroundModes` et description Always qui explique la limitation aux missions de livraison.
- Écran de consentement en app avant le flux GPS. Vérification de mission via `CourierRepository.assignments()` avant la demande d'autorisation. Le flux s'arrête après fin/annulation de la dernière mission, refus serveur, déconnexion ou arrêt manuel. Un indicateur d'attente évite les doubles démarrages.
- Sécurisation serveur précédente consolidée : migration `20261106205236_require_active_courier_assignment_for_location_updates` exige une affectation active liée à un colis et une commande non terminés avant toute insertion GPS.
- Test widget ajouté : `test/features/courier/courier_location_tracking_test.dart` confirme qu'aucun prompt de permission ne s'ouvre si le livreur n'a aucune mission.
- Le fichier pgTAP `security_regression_test.sql` est à 51 assertions. Tests non exécutés faute de runner GitHub ; aucun build mobile ni test en appareil réel n'a été effectué.
- La table `courier_locations` reste vide. Aucune purge/retention n'a été imposée sans validation du métier ; Linear RIA-31 fixe cette décision comme prérequis de production.
- Runbook publié : `docs/runbooks/aud-14-courier-background-location.md`. Ticket de livraison/GPS RIA-11 passe en In Progress.



### AUD-15 — restauration des sources et synchronisation Edge Functions — 7 novembre 2026

- Sources GitHub ajoutées pour `expire-products`, `admin-health-check` et `payment-webhook-gateway`.
- Les deux fonctions admin exigent maintenant un JWT valide, un enregistrement `admin_users.active=true` et un profil `ACTIVE`. Les erreurs de lecture de droits renvoient une erreur serveur et ne donnent jamais accès.
- Le gateway reste un tombstone 410 sans exécution métier.
- Déploiements live vérifiés avec lecture de contenu : `expire-products` v3, `admin-health-check` v3, `payment-webhook-gateway` v4. Le contenu exact confirme les gardes de profil actif et le 410.
- Parité de 21 Edge Functions actives / 21 dossiers sources désormais restaurée.
- CI Deno non confirmé : les runs sont apparus failed mais sans étapes ni journaux exploitables. Aucune preuve de compilation Deno ; relancer lorsque le runner Actions sera opérationnel.
- Pas de suppression de fonction, aucun secret lu/commité, aucun paiement ou produit réel modifié.
- Runbook publié : `docs/runbooks/aud-15-edge-function-source-parity.md`.



### AUD-17 — ajout de tests de contrat checkout/commandes/livraison — 7 novembre 2026

- Inventaire actualisé : 6 fichiers Flutter tests et 3 fichiers SQL, 77 assertions pgTAP planifiées au total.
- Création de `supabase/tests/database/order_delivery_contract_test.sql` avec 13 assertions de contrats sur checkout, annulation impayée, transitions vendeur, stock/coupons, affectations livreur, preuves photo et codes, livraison et ACL/refund.
- Contrôles en lecture seule exécutés sur les fonctions SQL de production pour évaluer les mêmes 13 prédicats : 13/13 vrais.
- Le fichier ne crée aucune commande, aucun paiement, aucun refund ou mouvement de stock ; le contrôle de prédicats ne remplace pas l'exécution pgTAP locale.
- Tests CI Flutter/pgTAP/Deno toujours non exécutés avec une étape lisible. Plus de tests d'intégration réels restent nécessaires avant de mesurer un score de qualité.
- Ticket suivi : RIA-27.



### AUD-18 — mesure de capacité et plan de reprise — 7 novembre 2026

- Relevé Postgres en lecture seule : 80 MB, max_connections 60, 3 réservées, 11 connexions observées.
- Logs PgBouncer 24 h : zéro saturation / connexion client refusée ; les 71 timeouts correspondaient à des connexions serveur inactives.
- Archiver WAL : 33 222 archivages, 0 échec ; aucun slot ni lien de réplication. Cela ne prouve pas la disponibilité de sauvegardes quotidiennes/PITR.
- Base d'essai insuffisante : Auth users 0, profils 0, produits 0, storage objects 0.
- Le test de charge k6 read-only est préparé pour staging uniquement ; aucun test n'a été exécuté et le projet de production n'a reçu aucune charge artificielle.
- Le compute/plan exact, la limite pooler et la présence/rétention des backups doivent être vérifiés dans Supabase Dashboard. Aucun coût compute ou option PITR engagés.
- La restauration et la stratégie RPO/RTO restent non testées. Runbook `docs/runbooks/aud-18-capacity-backup-restore.md`, ticket Linear RIA-32.


### AUD-19 — reset mot de passe par email — 7 novembre 2026

- Ajout de ForgotPasswordPage et AuthRecoveryPage : demande mail, redirection vers marketplaceburkina://auth/recovery, validation du nouveau mot de passe deux fois et appel updateUser.
- Ajout de AuthRecoveryState attaché dès que Supabase.initialize() se termine. Seul AuthChangeEvent.passwordRecovery autorise l'ouverture du formulaire ; le marqueur est effacé après signout ou après réussite.
- Routes /auth/forgot-password, /auth/recovery et alias /recovery. Lien depuis la page sign-in.
- Android intent filter pour host auth + path recovery ; iOS utilise le schéma existant.
- Tests : 3 nouveaux tests unitaires de récupération ; route de récupération ajoutée à la liste des routes publiques. Total Flutter : 7 fichiers.
- Action dashboard requise : Redirect URLs allow-list marketplaceburkina://auth/recovery, Reset Password email template et SMTP. La configuration Auth URL/SMTP n'est pas accessible par l'intégration Supabase MCP.
- SMS OTP non configuré pour éviter d'activer un fournisseur facturé sans décision. Aucun email de test/compte réel n'a été créé.
- Runbook docs/runbooks/aud-19-email-password-recovery.md, suivi RIA-8 en cours.

### AUD-20 — audit des index signalés inutilisés — 7 novembre 2026

- Performance Advisor : 366 lints. Comptage réel : public 571 dont 559 sans scan ; private 44 dont 39 sans scan. Parmi 598 index public/private sans scan, 232 sont primaires ou uniques et 366 sont non uniques/non primaires.
- Taille des 366 index potentiellement candidats : 3 031 040 bytes (~2.9 MiB). Dernier stats reset 25 août ; dernière autoanalyse 6 novembre. Tables métier presque toutes vides.
- Index de commandes, produits, colis, GPS, messages, paiement et remboursements conservés car ils couvrent des parcours prévus. Aucune suppression ou migration DDL. Runbook AUD-20 ajouté.

### AUD-21 — tables RLS activées sans policy — 7 novembre 2026

- Audit des 17 tables (15 private, 2 public media). ACL privées limitées à postgres ; tables media publiques accordées à service_role uniquement.
- has_table_privilege vérifié sur toutes les tables : aucun SELECT/INSERT/UPDATE/DELETE direct anon/authenticated. Fonctions SECURITY DEFINER vérifiées pour avis publiés et preuve de livraison appartenant au client.
- Deux assertions pgTAP ajoutées au fichier security_regression_test.sql ; 53 assertions dans ce fichier et 79 au total. Pas d'ajout de policy générique.
- Aucun changement de table/ACL/policy en production. Runbook AUD-21 ajouté.

### AUD-22 — revue SECURITY DEFINER et durcissement search_path — 7 novembre 2026

- Inventaire live : 166 fonctions SECURITY DEFINER ; 163 fonctions app détenues postgres, 3 C PostGIS détenues supabase_admin. 107 EXECUTE authenticated, 6 EXECUTE anon.
- Revue des helpers anon : can_read_published_review_media/get_public_review_media ne révèlent que les médias d'avis publiés ; private.is_admin exige auth.uid, admin_users.active et profiles.status ACTIVE ; trois autres sont les helpers PostGIS natifs.
- 163 fonctions applicatives ont toutes un search_path explicite ; seules les trois fonctions PostGIS C restent sans search_path, rôle propriétaire supabase_admin. 48 fonctions ont search_path vide.
- Deux migrations appliquées et synchronisées : 20261106220518_harden_security_definer_search_paths (12 RPC + trigger handle_new_user) ; 20261106220850_harden_payment_provider_event_search_path (RPC paiement service-role-only). Elles ajoutent pg_temp en dernière position sans changer body, owner, ACL ou données.
- Scan des références relationnelles non qualifiées sur les chemins non vides : aucune relation applicative non qualifiée identifiée. Les trois types personnalisés non qualifiés qui ont été trouvés sont maintenant protégés par pg_temp dernier.
- 14 fonctions avec pg_temp explicitement dernier ; aucun ancien chemin public/public,private non protégé du lot n'existe. 3 tests pgTAP ajoutés ; plan security_regression_test.sql = 56, total des 3 suites = 82.
- Les prédicats ont été évalués en lecture seule et passent. La suite pgTAP/CI complète n'a pas été exécutée car les runners échouent sans steps/logs. Runbook AUD-22 ajouté.

### AUD-02 — contrôle additionnel du ledger et de l'exécution Wave — 7 novembre 2026

- Contrainte unique seller_ledger vérifiée : `(seller_id, entry_type, reference_id)`. complete_refund insère REFUND par groupe avec la même référence refund_id ; un même vendeur multi-boutiques peut donc faire échouer la seconde insertion.
- execute-payment-refund appelle Wave d'abord, puis complete_refund. Si la comptabilisation DB échoue après confirmation du provider, la transaction locale rollback et la refund reste potentiellement PROCESSING avec provider_refund_confirmed true ; le rapprochement doit éviter toute nouvelle demande de remboursement externe.
- Aucun appelant DB / trigger / job pg_cron trouvé pour finalize_seller_group, finalize_seller_group_financials ou reverse_seller_group. Aucun appelant Flutter/Edge trouvé dans la recherche GitHub main ; les appels externes hors repo restent à vérifier.
- L'écran OrderDetailsPage envoie uniquement order_id + amount + reason. Le schéma returns ne stocke pas de quantité ni refund_id. Zéro ordre/paiement/refund/retour/commission/ledger en production à l'heure de l'audit.
- Runbook et rapport AUD-02 enrichis ; aucun changement financier ou DDL de production effectué.

### AUD-02 / AUD-03 — défaut sur paiement capturé après annulation — 7 novembre 2026

- `process_payment_event` crée un refund REQUESTED quand le prestataire capture après que order.status soit CANCELLED. Il ne crédite pas SELLER SALE dans ce chemin.
- `complete_refund` n'a pas de garde empêchant un débit seller si aucun SALE/commission n'a été comptabilisé : il parcourt les groupes annulés et écrit REFUND négatif. Il peut également changer les groupes vers REFUNDED tout en laissant la commande parent CANCELLED.
- La contrainte uq_seller_ledger_ref_type(seller_id,entry_type,reference_id) peut aussi faire échouer un remboursement multi-groupe si même seller_id possède plusieurs shops ; la fonction insère plusieurs REFUND avec reference_id=refund_id.
- Edge refund appelle Wave avant la comptabilisation locale : provider-confirmed + SQL failure laisse un risque de refund en PROCESSING mais déjà remboursé en externe. Le runbook prescrit rapprochement interne sans retry provider.
- Aucun code financier ni ledger touché. Toutes les tables métier concernées restent vides. Runbook AUD-02 complété.

### AUD-05 — bloquer checkout lorsque les credentials paiement manquent — 7 novembre 2026

- Ajout de `check-payment-provider-config` (v1, verify_jwt=true), Edge Function qui renvoie uniquement un booléen de configuration, aucune information de secret.
- Wave configuré = WAVE_API_KEY + WAVE_WEBHOOK_SECRET ; CinetPay = CINETPAY_API_KEY + CINETPAY_SITE_ID + CINETPAY_SECRET_KEY.
- `CheckoutRepository.ensurePaymentProviderConfigured()` appelle la fonction ; `CheckoutPage._checkout()` l'exécute avant `checkout_cart`. Si provider manquant, aucune commande ou réservation de stock n'est créée.
- Model parser `PaymentProviderAvailability` ajouté et 4 tests unitaires ajoutés.
- Déploiement vérifié live : fonction active v1, verify_jwt true ; Supabase expose 22 Edge Functions et main contient maintenant 22 dossiers sources.
- Wave et CinetPay restent NOT_CONFIGURED ; aucun secret, marchand ou paiement test n'a été créé.

### AUD-06 — FCM reste non configuré — 7 novembre 2026

- Health snapshot du 6 novembre 22:20 UTC : FCM NOT_CONFIGURED, service-account manquant, project_id absent. 450 logs `fcm_service_account_missing` sur les dernières 24 h.
- Aucun push d'appareil réel envoyé ; les secrets Firebase/APNs restent à fournir depuis les consoles officielles.

### AUD-17 — nouveau test du précontrôle paiement — 7 novembre 2026

- Total Flutter test files : 8. `payment_provider_availability_test.dart` apporte 4 assertions Flutter pour les réponses valides, non configurées, incohérentes et invalides.
- Suite CI toujours non exécutée : GitHub Actions a échoué avant ses étapes. Le test source est présent sur main mais pas certifié exécuté.
