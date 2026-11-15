# Audit GPS, notifications et plateformes natives — 16 novembre 2026

**Branche de travail :** `maintenance/audit-01-07-2026-11-15`  
**Tête de référence :** `9891504b09bb077f4de78bf7a4a39ab1ff19620e`  
**Nature :** revue statique des sources versionnées et vérification des exécutions GitHub Actions déjà disponibles. Aucun appareil physique, compte Firebase/APNs ou projet Supabase hébergé n'a été testé.

## 1. GPS livreur

### Éléments présents
- Le partage GPS est proposé seulement après lecture des missions et confirmation qu'une mission active existe.
- Le consentement est demandé avant la permission de localisation en arrière-plan.
- Le service exige `LocationPermission.always` pour activer le suivi continu.
- Android utilise une notification persistante de premier plan, une précision élevée, un filtre de 25 mètres et un intervalle cible de 15 secondes.
- iOS active les mises à jour de localisation en arrière-plan, désactive la pause automatique et affiche l'indicateur système.
- Chaque position est envoyée via la RPC `record_courier_location`; une affectation devenue inactive provoque l'arrêt du partage côté écran.
- Le dépôt contient un test widget qui vérifie qu'aucune permission GPS n'est demandée lorsqu'aucune mission active n'existe.

### Limites et validations manquantes
- Le test widget GPS actuel couvre uniquement le cas « aucune mission » ; il ne simule pas le flux natif de position.
- Aucun essai sur appareils Android/iOS n'a été exécuté dans cette passe : permission « Toujours », écran verrouillé, passage arrière-plan/avant-plan, perte réseau, arrêt forcé et redémarrage restent à tester.
- La conservation, la durée de rétention et la purge des positions GPS côté base hébergée n'ont pas été vérifiées.
- La compilation iOS Simulator Debug n'a pas été exécutée dans le dernier run natif : le job iOS était ignoré car ce run provenait d'un push et le workflow le réserve à `workflow_dispatch`.

## 2. Notifications push

### Éléments présents
- Firebase est initialisé uniquement sur Android/iOS ; si la configuration native manque, les notifications sont désactivées sans bloquer le démarrage.
- Les erreurs d'initialisation, permissions, réception au premier plan et synchronisation de session sont interceptées et journalisées en debug.
- Le token FCM est enregistré après authentification et lors de son renouvellement.
- La déconnexion utilise `signOutAndDeactivateCurrentDevice()` : la session n'est fermée qu'après confirmation serveur de désactivation du token.
- Les notifications ouvertes depuis l'application, depuis l'arrière-plan et depuis le lancement initial ont des chemins de navigation distincts.

### Limites et validations manquantes
- Aucun envoi FCM réel, test APNs sur iPhone ou test de réception sur appareil n'a été réalisé.
- La présence des fichiers Firebase natifs, de la clé APNs et des secrets de serveur n'est pas certifiée.
- Les parcours de rotation de token, désactivation après déconnexion, réseau indisponible et réinstallation doivent être validés sur appareils de test.

## 3. CI native vérifiée

- Flutter CI run [43764285828](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43764285828) : succès, analyse, tests et build Web Debug ; 50 tests confirmés dans le rapport de suivi.
- Android Debug run [43764125828](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43764125828) : APK Debug non signé réussi.
- iOS Simulator Debug dans ce même run : ignoré, car le workflow ne l'exécute que sur déclenchement manuel.
- Supabase Edge CI run [43753543111](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43753543111) : succès, tests partagés et vérification de tous les points d'entrée.
- PostgreSQL/pgTAP run [43754031145](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43754031145) : succès sur base locale isolée.
- La tête de maintenance `9891504` ne possède aucun status check associé ; ces succès concernent des commits antérieurs et ne doivent pas être présentés comme une validation de cette tête.

## 4. Actions restantes

1. Déclencher, lorsque l'accès GitHub le permet, le workflow natif manuellement pour obtenir le build iOS Simulator Debug.
2. Tester les scénarios GPS Android/iOS sur appareils physiques, y compris écran verrouillé, réseau interrompu, arrêt forcé et mission terminée.
3. Vérifier les politiques de rétention/purge GPS et les autorisations de lecture des positions avec accès Supabase autorisé, en lecture seule d'abord.
4. Tester FCM et APNs avec les vrais projets et appareils de test, sans utiliser de paiement ni de données client réelles.
5. Ajouter des tests ciblés pour le démarrage/arrêt GPS, les erreurs de flux et le cycle de vie des tokens push.

## 5. Périmètre de sécurité

Aucun déploiement, aucune publication, aucun merge vers `main`, aucune migration distante, aucun paiement réel, aucune modification de solde et aucun appel marchand n'ont été effectués.
