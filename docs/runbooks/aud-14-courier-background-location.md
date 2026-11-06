# AUD-14 — Suivi GPS livreur pendant une mission active

**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina` — branche `main`  
**État au 7 novembre 2026 :** flux mobile et protection serveur ajoutés ; tests sur appareils physiques et validation App Store / Google Play restant requis.

## 1. Architecture mise en place

### Flutter

- `DeviceLocationService.positionStream()` utilise le flux natif continu `Geolocator.getPositionStream()` au lieu d'un `Timer.periodic` attaché à la page.
- La fréquence Android souhaitée est de 15 secondes et la distance minimale de 25 mètres.
- L'activation du suivi est volontaire, depuis l'espace livreur, et précédée d'un écran d'explication.
- Le partage n'est pas activable lorsque `get_courier_assignments()` retourne zéro mission active.
- Sur Android, Geolocator démarre un service de premier plan avec notification persistante `Suivi de livraison actif`.
- Sur iOS, `AppleSettings.allowBackgroundLocationUpdates=true`, la mise en pause automatique est désactivée pendant le suivi, et l'indicateur système d'activité de localisation est demandé.
- Un seul flux GPS est accepté à la fois ; l'interface empêche les doubles appuis pendant le démarrage.
- L'action « arrêter le partage » annule l'abonnement natif et fait cesser le service.
- Après chaque transition d'état d'un colis, l'application recharge les affectations. Si aucune mission active ne reste, elle arrête le partage.
- Si le serveur renvoie `active_courier_assignment_required`, le suivi s'arrête immédiatement.
- À la destruction de la page (par exemple après déconnexion), l'abonnement est annulé.

### Autorisations Android

Le manifeste déclare :
- `ACCESS_FINE_LOCATION` et `ACCESS_COARSE_LOCATION` ;
- `ACCESS_BACKGROUND_LOCATION` pour recevoir les mises à jour lorsque l'application est en arrière-plan ;
- `FOREGROUND_SERVICE` et `FOREGROUND_SERVICE_LOCATION` pour le service GPS de premier plan.

La configuration Geolocator demande une notification de service persistante et n'active ni WakeLock ni WifiLock. Le livreur voit un écran d'explication avant le lancement du flux ; le système peut lui demander d'autoriser la localisation « Toujours / Autoriser tout le temps ». Il peut couper le suivi depuis l'application.

### Autorisations iOS

Le fichier `ios/Runner/Info.plist` conserve les descriptions `NSLocationWhenInUseUsageDescription` et `NSLocationAlwaysAndWhenInUseUsageDescription`. Le mode `location` a été ajouté à `UIBackgroundModes` en plus de `fetch` et `remote-notification`.

La permission `Always` est requise pour le suivi continu lorsque l'application est en arrière-plan. La configuration `AppleSettings` active le mode background et l'indicateur système bleu. Le comportement doit être testé sur un iPhone réel, avec l'application activée en premier plan avant le passage en arrière-plan.

## 2. Sécurité serveur

La migration `20261106205236_require_active_courier_assignment_for_location_updates.sql` met à jour `public.record_courier_location(latitude, longitude, accuracy)`.

La RPC exige désormais :
1. une session authentifiée et un compte actif ;
2. le rôle `COURIER` ;
3. une latitude/longitude valides et une précision non négative ;
4. au moins une affectation appartenant au livreur avec statut `ASSIGNED`, `ACCEPTED`, `PICKED_UP` ou `IN_TRANSIT` ;
5. un colis `READY_FOR_PICKUP`, `PICKED_UP` ou `IN_TRANSIT` ;
6. un groupe non annulé et une commande ni annulée ni remboursée.

La fonction insère la géographie dans le schéma PostGIS `extensions`, conserve `SECURITY DEFINER` et le `search_path = pg_catalog, extensions, public`. `anon` n'a pas EXECUTE ; `authenticated` et `service_role` l'ont.

L'enregistrement GPS est donc impossible pour un simple compte portant le rôle COURIER sans mission active. Une fois la dernière affectation terminée ou annulée, le prochain envoi est rejeté par le serveur ; l'application ferme alors le flux.

## 3. Données réellement présentes

Au moment de l'audit :
- `public.courier_locations` : 0 ligne ;
- `public.delivery_assignments` : 0 ligne.

Aucun utilisateur livreur, aucune mission, aucune position GPS n'a été créé pour tester sur la base hébergée. La vérification SQL porte sur la définition et les ACL de la RPC.

## 4. Confidentialité et conservation des positions

Aucune tâche de purge des anciennes lignes `courier_locations` n'a été trouvée. Comme les positions GPS exactes sont des données personnelles sensibles, il faut définir la durée de conservation avant la mise en production.

Suivi : [RIA-31 — définir la conservation et la purge des positions GPS livreur](https://linear.app/faso/issue/RIA-31/confidentialite-definir-la-conservation-et-la-purge-des-positions-gps).

Aucune durée n'a été fixée arbitrairement et aucune purge n'a été ajoutée dans cette correction. La décision doit tenir compte du besoin de preuve/litige, de la politique de confidentialité et de la réglementation applicable au Burkina Faso. La purge devra être une tâche serveur contrôlée, sans toucher aux commandes, preuves de livraison ou écritures financières.

## 5. Tests à exécuter avant production

### Tests Flutter / CI

Un test widget est ajouté pour vérifier qu'en l'absence d'affectation active, l'interface refuse le partage avant de présenter l'écran d'autorisation GPS. Le test doit encore être exécuté par GitHub Actions.

### Android — appareils réels

1. Compte livreur actif avec affectation `ASSIGNED`.
2. Activation du partage depuis l'espace livreur, autorisations précises et « Autoriser tout le temps ».
3. Vérifier la notification persistante et l'arrivée d'une position toutes les 15 secondes environ pendant le déplacement (au mieux, avec filtre de 25 mètres).
4. Verrouiller l'écran et ouvrir une autre application ; vérifier que le suivi continue.
5. Terminer la dernière mission ; vérifier que la notification et le flux s'arrêtent.
6. Réessayer avec aucune mission, une mission annulée ou une permission refusée ; aucune position ne doit être écrite.
7. Vérifier batterie / mode économie d'énergie et permissions révoquées.

### iOS — iPhone réel

1. Vérifier le dialogue « Toujours » et la transparence de l'utilisation.
2. Démarrer le suivi en premier plan avec une mission active.
3. Mettre l'application en arrière-plan et verrouiller l'écran ; contrôler l'indicateur système et les positions reçues.
4. Terminer ou annuler la mission ; vérifier l'arrêt du flux.
5. Révoquer la permission et vérifier que le serveur n'accepte aucune écriture lorsque le flux ne peut plus être maintenu.

### Contrôles de sécurité

- Le rôle COURIER seul, sans affectation, ne peut pas appeler la RPC avec succès.
- Un livreur ne peut pas écrire une position pour un autre utilisateur.
- Après fin/annulation de toutes les missions, aucune nouvelle position ne doit être insérée.
- Un client peut lire seulement la dernière position du livreur qui lui est affecté sur une mission active selon la policy `courier_locations_read`.
- Les positions ne sont jamais exposées à un client après fin/annulation de sa mission.

## 6. Limites de réalisation

- Code de flux continu et paramètres natifs ajoutés sur `main`.
- Contrôle serveur d'affectation active appliqué et vérifié.
- Test de refus sans mission ajouté.
- Aucun test Flutter exécuté : les premiers runs GitHub Actions ne démarraient pas de runner.
- Aucun APK/IPA n'a été construit ni installé sur un appareil pendant cet audit.
- App Store / Google Play : les permissions de localisation en arrière-plan demandent un examen dédié et une justification conforme à la fonction principale de livraison. La présence des clés natives ne garantit pas l'approbation des stores.
- La politique de conservation GPS est encore à définir (RIA-31).
