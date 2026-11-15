# AUD-28 — Validation iOS Debug et préparation appareil

**Projet :** Marketplace Multiservices Burkina  
**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Date :** 16 novembre 2026  
**Statut :** configuration statique relue ; compilation iOS Simulator et test sur iPhone non exécutés.

## 1. Configuration statique constatée

- Le workflow `.github/workflows/native-build.yml` contient un job `macos-latest` qui exécute `flutter build ios --simulator --debug` après installation Flutter 3.47.2 et résolution verrouillée.
- Le job iOS est explicitement réservé à `workflow_dispatch` ; il est ignoré sur les événements push.
- `ios/Runner/Info.plist` contient les descriptions `NSLocationWhenInUseUsageDescription` et `NSLocationAlwaysAndWhenInUseUsageDescription`, ainsi que le mode `location` dans `UIBackgroundModes`.
- `ios/Runner/Runner.entitlements` définit `aps-environment` via `$(APS_ENVIRONMENT)`. Le projet Xcode référence cet entitlements file pour les configurations applicatives et définit le Bundle ID `com.marketplaceburkina.marketplaceMultiservicesBurkina`.
- La cible minimum iOS statique observée est 15.0.

## 2. Configuration manquante pour les notifications

Le dépôt ne contient pas `ios/Runner/GoogleService-Info.plist` ni un fichier généré de configuration Firebase. La valeur APNs et l'association Firebase restent à confirmer dans le projet Firebase du propriétaire. Ne jamais fabriquer le plist, une clé APNs, un certificat ou un identifiant d'équipe.

## 3. Suite de validation à effectuer sur macOS

1. Lancer uniquement le job iOS Simulator Debug après approbation du propriétaire, sur le commit candidat exact.
2. Conserver le résultat de `flutter pub get --enforce-lockfile` et du build Debug.
3. Installer l'app dans un simulateur compatible ; contrôler navigation, routes, permissions non disponibles et gestion des erreurs Firebase absentes.
4. Sur un iPhone réel, vérifier demande de localisation « Toujours », passage en arrière-plan, verrouillage, arrêt après fin de mission et révocation de permission.
5. Après configuration Firebase/APNs par le propriétaire, tester l'enregistrement du token, une notification ciblée et l'ouverture de la bonne route.
6. Vérifier que les entitlements APNs de développement utilisés en Debug sont ceux attendus ; ne pas produire d'archive Release, IPA ou publication pendant la maintenance.

## 4. État au 16 novembre 2026

La lecture des fichiers confirme les déclarations de permission et l'entitlements file, mais ne prouve ni la réussite de la compilation Xcode, ni le fonctionnement GPS en arrière-plan, ni la réception push. Le job iOS n'a pas été déclenché dans cette passe. Aucun certificat, profil de provisioning, secret Firebase/APNs ou compte Apple n'a été modifié.
