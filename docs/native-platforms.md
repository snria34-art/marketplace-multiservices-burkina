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

### Validation pendant la maintenance

Le workflow GitHub `.github/workflows/native-build.yml` est maintenant limité à une validation manuelle non signée :
```bash
flutter build apk --debug
```

Il ne produit pas d'AAB, ne signe pas une release et ne publie rien. Le build de publication Play Store reste une opération future séparée, à préparer uniquement après configuration sécurisée du keystore et autorisation explicite. Ne pas déclencher le workflow pendant la phase actuelle.

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

Le job iOS du workflow de validation exécute `flutter build ios --simulator --debug`. C’est une compilation de simulateur en debug, **pas** un IPA release et **pas** une archive de publication. Ce job n'est pas une étape de déploiement et ne doit pas être lancé tant que la maintenance CI n'est pas débloquée.

## Firebase natif

Les fichiers `google-services.json` et `GoogleService-Info.plist` dépendent du véritable projet Firebase et ne doivent pas être fabriqués. Après création/enregistrement des applications Android et iOS, exécuter `flutterfire configure` pour générer `firebase_options.dart` et les fichiers natifs appropriés.

## CI et déclenchement

Le workflow `.github/workflows/native-build.yml` est volontairement limité à `workflow_dispatch` et ne réalise plus que des builds de validation Debug non signés (Android APK Debug et iOS Simulator Debug). Aucun job AAB/IPA de publication, upload vers un store ou déploiement n'est configuré dans ce workflow.

Le workflow de validation Flutter est manuel ; les workflows Flutter CI et Supabase Edge Functions CI vérifient aussi la branche de maintenance lors de futurs changements de code. Le workflow Supabase DB demeure manuel et reconstruit uniquement la base locale du runner. Aucun workflow n’a été lancé pendant cette correction.
