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

Les fichiers Android et iOS officiels sont maintenant présents dans `android/app/google-services.json` et `ios/Runner/GoogleService-Info.plist`. Ils proviennent du projet Firebase `marketplace-multiservices-bf` et correspondent respectivement aux identifiants `com.marketplaceburkina.marketplace_multiservices_burkina` et `com.marketplaceburkina.marketplaceMultiservicesBurkina`. Vérifier que le fichier iOS est bien associé à la cible Runner dans Xcode. Le plug-in Google Services Android s'active uniquement lorsque le fichier JSON officiel est présent.

Les configurations clientes Firebase ne remplacent pas le compte de service de l'Edge Function. La clé privée de ce compte reste dans les secrets Supabase sous `FCM_SERVICE_ACCOUNT_JSON`, jamais dans l'app ou dans Railway.

## Firebase natif

Les fichiers Android `google-services.json` et iOS `GoogleService-Info.plist` sont téléchargés depuis le véritable projet Firebase `marketplace-multiservices-bf` et ajoutés à la branche d'intégration. Leurs identifiants d'application ont été contrôlés. Vérifier l'association du fichier iOS à la cible Runner dans Xcode, puis exécuter `flutterfire configure` depuis la racine Flutter pour générer `lib/firebase_options.dart` et vérifier les plateformes sélectionnées. Ne jamais fabriquer ces fichiers à partir de valeurs supposées.

## CI et déclenchement

Le workflow `.github/workflows/native-build.yml` se déclenche sur les pushes de maintenance touchant Android/Flutter et via `workflow_dispatch`. Le job Android APK Debug fonctionne pour les deux événements ; le job iOS Simulator Debug est conditionné à `workflow_dispatch` pour éviter les runners macOS sur chaque push. Les deux builds sont non signés. Aucun job AAB/IPA de publication, upload vers un store ou déploiement n'est configuré dans ce workflow.

Le workflow de validation Flutter est manuel ; les workflows Flutter CI et Supabase Edge Functions CI vérifient aussi la branche de maintenance lors de futurs changements de code. Le workflow Supabase DB demeure manuel et reconstruit uniquement la base locale du runner. Aucun workflow n’a été lancé pendant cette correction.
