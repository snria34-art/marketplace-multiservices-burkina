# Revue technique de maintenance — 15 novembre 2026

**Dépôt :** `snria34-art/marketplace-multiservices-burkina`  
**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Base comparée :** `main` du dépôt privé actuel  
**Périmètre :** revue statique Flutter, configuration SDK, workflows CI, plateformes natives, fonctions Edge, migrations, tests, documentation et hygiène des fichiers.

## Résumé

Cette passe a corrigé les incohérences sûres et confirmables dans la configuration de développement. Elle n'est pas une certification sans défaut : les outils Flutter/Dart, Deno, PostgreSQL et Supabase CLI ne sont pas disponibles dans l'environnement d'inspection et les runners GitHub Actions observés échouent avant la première étape. Aucun test runtime n'a donc été exécuté.

## Correctifs enregistrés

### Toolchain Flutter

- Le minimum Dart de `pubspec.yaml` est maintenant `>=3.13.0 <4.0.0`, aligné sur la contrainte Dart inscrite dans `pubspec.lock`.
- La contrainte Flutter est temporairement bornée à `>=3.47.2 <3.50.0`, car cette branche valide la chaîne Flutter 3.47.2 / AGP 9.1.0 / Gradle 9.3.1. Flutter 3.50 documente de nouveaux defaults Android (AGP 9.3.1 / Gradle 9.5.0) ; la mise à niveau coordonnée n'a pas été testée. Ce verrouillage est une protection contre une toolchain non validée, pas la preuve que Flutter 3.50 échoue dans tous les cas. (Documentation : https://flutter.dev/blog/whats-new-in-flutter-3-50)
- Le README annonce désormais le SDK Flutter/Dart retenu.
- La CI Flutter utilise `flutter pub get --enforce-lockfile`, de sorte que la CI échoue si le lockfile n'est pas cohérent au lieu de réécrire implicitement la résolution.

### CI — validation, pas publication

- Les workflows Flutter CI et Supabase Edge Functions CI surveillent également la branche de maintenance.
- Les runners Linux des validations sont épinglés sur `ubuntu-24.04`.
- Le workflow Flutter compile le Web en `--debug`, jamais en `--release` dans cette phase, et applique `pub get --enforce-lockfile`.
- Le workflow natif ne tente plus de créer un AAB Android `--release` sans keystore : il fait uniquement une validation Android APK Debug et iOS Simulator Debug, non signées.
- La documentation native a été corrigée pour ne plus décrire l'ancien job AAB Release.
- Le workflow Flutter manuel applique le même contrôle strict que la CI : analyse et tests sans options qui rendent les warnings/informations non fatals.
- Aucun workflow n'a été lancé, aucun runner n'a été relancé et aucune compilation n'a été exécutée pendant cette passe.

### Hygiène du dépôt

- `.gitignore` ignore maintenant les fichiers Flutter/Android/iOS générés localement, les états locaux Supabase, les clés de signature et les certificats privés.
- Le contrôle statique de l'arbre GitHub n'a trouvé aucun fichier de type `.env`, `key.properties`, keystore, fichier PEM/P12 ou configuration Firebase native contenant des secrets versionné dans l'arbre inspecté.
- Le README indique que la préparation Vercel est suspendue et qu'aucun Preview/Production ne doit être créé pendant la maintenance.
- `docs/native-platforms.md` a été corrigé pour refléter le workflow natif Debug actuel et ne plus annoncer un build AAB Release.

## Vérifications statiques réalisées

- 347 fichiers de migration SQL présents dans le dépôt au moment du relevé.
- 22 points d'entrée Edge Function `index.ts`.
- 8 fichiers de tests SQL pgTAP ; les appels d'assertion détectés correspondent aux 8 valeurs `plan(...)`, soit 179 assertions déclarées.
- 8 fichiers de tests Flutter/Dart présents.
- Aucun appel `throw UnimplementedError` ni marqueur `FIXME` trouvé par les recherches ciblées.
- Les fonctions Wave/CinetPay v3 et leurs webhooks ont été relus pour leurs contrôles JWT, signature, site/provider et traitement serveur. Les secrets marchands et FCM restent une condition de configuration externe ; aucune valeur de secret n'a été cherchée ou affichée.

Ces vérifications ne remplacent ni l'analyseur Dart, ni le compilateur, ni les tests Flutter, Deno ou pgTAP.

## Échecs CI historiques — diagnostic

Les runs Flutter et Supabase Edge Functions consultés se terminaient avec `runner_id=0`, nom de runner vide et aucune étape. Les journaux étaient absents (`404 BlobNotFound`). Ils n'ont pas exécuté `checkout`, `flutter analyze`, `flutter test` ou `deno check`.

Le problème observé est l'attribution du runner, pas une erreur de code prouvée. Le dépôt ne permet pas de corriger une restriction du compte, un quota Actions, une politique d'organisation ou une panne du service de runners. Il faut examiner les paramètres GitHub du compte/dépôt sans augmenter de limite payante.

## Points critiques volontairement non modifiés

### Paiements et remboursements

Le runbook `docs/runbooks/aud-02-refund-allocation.md` décrit un défaut confirmé dans l'allocation des remboursements partiels : le ledger peut imputer des vendeurs qui ne sont pas concernés. Le modèle d'allocation doit d'abord définir article, quantité, groupe, commission, coupon, frais de livraison, financement des remises, double boutique et rapprochement des remboursements externes.

Aucune fonction `complete_refund`, table `refunds`, écriture `seller_ledger`, commission, solde, paiement ou remboursement n'a été modifié. Un correctif SQL improvisé sans tests transactionnels peut déplacer de l'argent entre vendeurs.

### PostGIS

La préparation applicative au déplacement PostGIS existe déjà. L'extension installée dans `public` dépend du propriétaire d'extension Supabase ; le déplacement non destructif doit être coordonné avec Supabase Support. Aucun `DROP EXTENSION`, `REVOKE`, trigger ou changement de schéma distant n'a été tenté.

### Historique des migrations Supabase

Le rapport précédent relève 347 migrations locales contre 346 entrées distantes, avec le numéro `20261104020500` à réconcilier. Le workflow de réparation historique est manuel et changerait l'historique de la base distante ; il n'a pas été lancé.

### Firebase, Wave et CinetPay

Les fichiers de configuration Firebase réels et les secrets des fournisseurs ne doivent pas être fabriqués. Aucun paiement sandbox/réel, aucun callback réel et aucun push appareil n'a été envoyé. Les secrets doivent rester dans les paramètres sécurisés du service concerné, jamais dans Git ou Flutter.

### Validation des plateformes

Les permissions GPS en arrière-plan sont présentes dans les fichiers Android/iOS ; les essais sur appareils physiques, la consommation batterie, l'arrêt de mission, les permissions révoquées et les exigences des stores ne sont pas validés.

## Reste à valider avant d'affirmer que le projet ne présente plus d'erreur

1. Débloquer l'attribution des runners GitHub Actions via les paramètres Actions/quota/politiques ou le support GitHub, sans activer de dépense.
2. Exécuter `flutter analyze`, `flutter test` et la compilation Web Debug, puis corriger chaque diagnostic réel.
3. Exécuter `deno check` sur les 22 fonctions Edge et corriger chaque erreur réelle.
4. Reconstruire une base Supabase **locale** isolée, vérifier la reproductibilité des migrations et exécuter les 179 assertions pgTAP.
5. Ajouter les scénarios d'intégration multi-vendeurs/retours, callbacks signés/idempotents, capture après annulation et concurrence stock.
6. Tester Android et iOS Debug sur appareils/simulateurs, et GPS arrière-plan sur appareils réels.
7. Faire examiner le modèle financier, les règles légales/fiscales et la conservation GPS avant d'activer des flux réels.

## Opérations interdites pendant la maintenance

Aucun déploiement GitHub ou Vercel, aucune publication Web/Android/iOS, aucun build Release, aucun merge vers `main`, aucune migration Supabase distante, aucune modification de données, aucun paiement/remboursement réel, aucun secret modifié et aucune action de billing n'a été effectué.

**Conclusion :** les incohérences de configuration identifiées ont été corrigées sur la branche de maintenance. Le dépôt ne peut pas encore être déclaré sans erreur : les tests automatiques n'ont pas pu démarrer faute de runner et plusieurs contrôles critiques nécessitent un environnement isolé ou une décision métier.
