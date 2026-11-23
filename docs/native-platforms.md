# Android et iOS natifs

## Android

Identifiant d’application :

`com.marketplaceburkina.marketplace_multiservices_burkina`

Le niveau minimal Android est API 23. Les validations natives actuelles utilisent Flutter 3.47.2, AGP 9.1.0, Gradle 9.3.1 et Java 17. Ne pas utiliser une version Flutter supérieure à la plage déclarée dans `pubspec.yaml` avant la mise à niveau coordonnée de la toolchain.

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

Le workflow GitHub `.github/workflows/native-build.yml` exécute un build Android Debug non signé sur les pushes de la branche de maintenance lorsque des fichiers Android, Flutter ou le workflow natif changent. Il peut aussi être lancé manuellement depuis GitHub Actions.

```bash
flutter build apk --debug
```

Ce contrôle ne produit pas d'AAB, ne signe pas une release et ne publie rien. Le build de publication Play Store reste une opération future séparée, à préparer uniquement après configuration sécurisée du keystore et autorisation explicite.

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

Le job iOS du workflow de validation s'exécute uniquement lors d'un déclenchement manuel (`workflow_dispatch`) ; il n'est pas lancé par les pushes de maintenance. Il exécute `flutter build ios --simulator --debug`. C’est une compilation de simulateur en debug, **pas** un IPA release et **pas** une archive de publication. Ce job n'est pas une étape de déploiement.


## Identifiants d'applications Firebase

Les identifiants à utiliser pour rattacher les applications clientes au projet Firebase existant sont :

- Android : `com.marketplaceburkina.marketplace_multiservices_burkina`
- iOS (Bundle ID) : `com.marketplaceburkina.marketplaceMultiservicesBurkina`

Le fichier Android officiel `google-services.json` est maintenant présent dans `android/app/`. Il provient du projet Firebase `marketplace-multiservices-bf` et son package correspond à `com.marketplaceburkina.marketplace_multiservices_burkina`. Le fichier Apple `GoogleService-Info.plist` devra être téléchargé depuis ce même projet, placé dans `ios/Runner/` et associé à la cible Runner dans Xcode. Le plug-in Google Services Android s'active uniquement lorsque le fichier JSON officiel est présent.

Les configurations clientes Firebase ne remplacent pas le compte de service de l'Edge Function. La clé privée de ce compte reste dans les secrets Supabase sous `FCM_SERVICE_ACCOUNT_JSON`, jamais dans l'app ou dans Railway.

## Firebase natif

Le fichier Android `google-services.json` est déjà téléchargé et ajouté à la branche d'intégration depuis le véritable projet Firebase. Le fichier iOS `GoogleService-Info.plist` reste à télécharger depuis ce projet après enregistrement de l'application iOS avec le Bundle ID exact. Ensuite, exécuter `flutterfire configure` depuis la racine Flutter pour générer `lib/firebase_options.dart` et vérifier les configurations des plateformes sélectionnées. Ne jamais fabriquer ces fichiers à partir de valeurs supposées.

## CI et déclenchement

Le workflow `.github/workflows/native-build.yml` se déclenche sur les pushes de maintenance touchant Android/Flutter et via `workflow_dispatch`. Le job Android APK Debug fonctionne pour les deux événements ; le job iOS Simulator Debug est conditionné à `workflow_dispatch` pour éviter les runners macOS sur chaque push. Les deux builds sont non signés. Aucun job AAB/IPA de publication, upload vers un store ou déploiement n'est configuré dans ce workflow.

Le workflow de validation Flutter est manuel ; les workflows Flutter CI et Supabase Edge Functions CI vérifient aussi la branche de maintenance lors de futurs changements de code. Le workflow Supabase DB demeure manuel et reconstruit uniquement la base locale du runner. Aucun workflow n’a été lancé pendant cette correction.
