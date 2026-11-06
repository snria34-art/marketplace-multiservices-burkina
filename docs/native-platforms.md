# Android et iOS natifs

## Android

Identifiant d’application :

`com.marketplaceburkina.marketplace_multiservices_burkina`

Le niveau minimal Android est API 23.

Permissions configurées :
- Internet
- localisation précise
- localisation approximative
- notifications Android 13+

Deep links :
- `marketplaceburkina://orders/<id>`
- `marketplaceburkina://notifications`

### Signature

Le fichier `android/key.properties.example` sert de modèle. Le vrai `android/key.properties` et le keystore doivent rester hors de Git.

Pour la publication Play Store, créer une clé d’upload, conserver le keystore dans un gestionnaire de secrets et utiliser Play App Signing.

Commandes locales de publication :
```bash
flutter build appbundle --release
flutter build apk --release
```

Le workflow GitHub `.github/workflows/native-build.yml` construit un **AAB Android release**. Il ne produit pas un APK dans son job Android. La signature de publication exige la configuration du keystore et de `key.properties` ; ne pas supposer que le runner peut signer tant que ces éléments ne sont pas fournis de manière sécurisée.

## iOS

Le runner iOS est configuré en Swift avec Swift Package Manager. Deployment Target : iOS 15.

Permissions configurées :
- localisation lorsque l’application est utilisée
- localisation toujours/activité de suivi
- mode background remote-notification
- mode background fetch

Deep link :
- `marketplaceburkina://orders/<id>`

Entitlements APNs :
`ios/Runner/Runner.entitlements` utilise `$(APS_ENVIRONMENT)` pour Debug/Release.

### Push Apple

Pour recevoir FCM sur iPhone, activer Push Notifications et Background Modes dans Xcode et fournir la clé APNs dans Firebase. Ces étapes exigent le véritable compte Apple Developer et le projet Firebase.

### Publication

`flutter build ipa` produit l’IPA destiné à TestFlight/App Store après configuration du compte Apple et de la signature.

Le job iOS du workflow actuel exécute `flutter build ios --simulator --debug`. C’est une compilation de simulateur en debug, **pas** un IPA release et **pas** une archive de publication.

## Firebase natif

Les fichiers `google-services.json` et `GoogleService-Info.plist` dépendent du véritable projet Firebase et ne doivent pas être fabriqués. Après création/enregistrement des applications Android et iOS, exécuter `flutterfire configure` pour générer `firebase_options.dart` et les fichiers natifs appropriés.

## CI et déclenchement

Le workflow `.github/workflows/native-build.yml` est volontairement limité à `workflow_dispatch` (déclenchement manuel). Le déclenchement automatique sur les tags a été retiré pour éviter de consommer les minutes GitHub Actions avant que la signature Android, la configuration Firebase et les prérequis de publication soient prêts.

Le workflow de validation Flutter et le workflow Supabase DB sont également manuels. Aucun workflow n’a été lancé pendant cette correction.
