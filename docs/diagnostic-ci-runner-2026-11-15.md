# Diagnostic et correction de la CI — 15 novembre 2026

**Dépôt :** `snria34-art/marketplace-multiservices-burkina`  
**Branche de travail :** `maintenance/audit-01-07-2026-11-15`  
**Branche principale :** `main` (non modifiée)  
**Nature :** diagnostic GitHub Actions en lecture seule et corrections de configuration sur la branche de maintenance.

## 1. Diagnostic prouvé

Deux workflows échouent avant l'exécution de leur première étape :

| Workflow | Run | Job | Commit testé | Runner | Étapes |
|---|---:|---:|---|---:|---:|
| Flutter CI | 42323347582 | 128252822056 | `b85c83081de557340bcaeafc06fea2a6b54ae2c1` | `runner_id=0` | 0 |
| Supabase Edge Functions CI | 42304226461 (tentative 2) | 128193460782 | `ec7012b0566b74fe99ff2a101cc91be42d0c75ed` | `runner_id=0` | 0 |

Pour les deux jobs, GitHub renvoie une liste d'étapes vide. La récupération des journaux retourne `404 BlobNotFound`. Les jobs sont terminés en quelques secondes et n'ont ni nom de runner ni runner group.

**Conclusion :** ces exécutions n'ont jamais atteint `checkout`, `flutter pub get`, `flutter analyze`, `flutter test` ou `deno check`. Il n'y a donc aucune erreur de code Flutter/Dart/Deno démontrée par ces runs. Modifier le code applicatif pour « corriger » ces échecs serait spéculatif.

Les causes possibles encore à vérifier sont les permissions/limitations GitHub Actions du dépôt ou du compte, les limites d'utilisation/facturation, une politique d'organisation ou le service de provisioning des runners GitHub-hosted. Le diagnostic ne permet pas de choisir l'une de ces causes sans le message pré-exécution du Check Run ou l'examen des paramètres du compte.

## 2. Correctifs de configuration apportés sur la branche de maintenance

### `.github/workflows/flutter-ci.yml`

- Ajout de `maintenance/audit-01-07-2026-11-15` aux branches suivies par le déclencheur `push`.
- Image runner épinglée à `ubuntu-24.04` au lieu de l'alias mobile `ubuntu-latest`.
- Suppression du workflow lui-même de la liste des chemins du déclencheur `push`, afin qu'une simple mise à jour de configuration ne lance pas un job coûteux sans changement de code à contrôler.
- Les contrôles restent : `flutter pub get --enforce-lockfile`, `flutter analyze`, `flutter test` et compilation Flutter Web `--debug` avec valeurs Supabase factices. Il n'y a aucune étape de publication ou de déploiement.

### `.github/workflows/supabase-functions-ci.yml`

- Ajout de `maintenance/audit-01-07-2026-11-15` aux branches suivies par le déclencheur `push`.
- Image runner épinglée à `ubuntu-24.04`.
- Suppression du workflow lui-même de la liste des chemins du déclencheur `push`.
- Le job reste limité à `deno check` de chaque point d'entrée Edge Function. Il ne déploie aucune fonction.

Ces changements rendent la branche de maintenance vérifiable lors des prochains changements de code. L'image runner fixe élimine l'ambiguïté de l'alias `ubuntu-latest`, mais ne contourne pas une restriction de compte, une limite de facturation ou une panne du service d'attribution des runners.

### Résultat de la CI Flutter — validation réussie

Le run `43717217145` sur le commit `5428bc9255d52559bbacfaa47e3e4cde26f3318a` s'est terminé avec succès. Le runner a exécuté toutes les étapes : Flutter 3.47.2, dépendances verrouillées, analyse, tests et compilation Web Debug.

- `flutter analyze --no-fatal-infos` : réussi (aucune erreur ni avertissement bloquant ; les infos sont conservées).
- `flutter test` : 29 réussites, aucun échec.
- `flutter build web --debug` : réussi.
- Lockfile : aucun changement.

Run : https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43717217145

Les deux régressions testées ont été corrigées : tentative de redirection via segments `..` (y compris encodages et entrée malformée) et fuite de timer d'auto-refresh Supabase dans le test GPS.


### Validation native et SDK Flutter

- `native-build.yml` est passé d'un build AAB Android `--release` non signable sans keystore à deux builds de validation non signés : Android APK `--debug` et iOS Simulator `--debug`.
- `flutter.yml` reste un workflow de validation manuel strict ; la CI automatique Flutter utilise `flutter analyze --no-fatal-infos`, ce qui garde les erreurs et avertissements bloquants tout en laissant les diagnostics de niveau info non bloquants.
- `pubspec.yaml` exige Dart >=3.13.0 et Flutter >=3.47.2 <3.50.0 ; le lockfile existant indique Dart >=3.13.0 et Flutter >=3.47.0. Le plafond Flutter est temporaire : le dépôt utilise AGP 9.1.0 / Gradle 9.3.1, tandis que les nouveaux projets Flutter 3.50 documentés utilisent AGP 9.3.1 / Gradle 9.5.0. La migration vers cette nouvelle chaîne doit être testée avant d'élargir la contrainte.
- `.gitignore` couvre les fichiers locaux Android/iOS/Flutter, l'état Supabase local et les clés/certificats de signature.

## 4. Action requise dans les paramètres GitHub — sans frais

L'accès de ce connecteur permet la lecture et les changements de fichiers, mais pas la lecture ni la modification des paramètres Actions/Billing du compte. Il est donc impossible de lever un blocage de facturation, une restriction de compte ou une politique d'organisation depuis un commit.

Vérifier dans l'interface GitHub :

1. **Paramètres du dépôt → Actions → General** : vérifier que GitHub Actions est autorisé et qu'aucune politique du dépôt ou de l'organisation ne bloque les workflows.
   Lien : https://github.com/snria34-art/marketplace-multiservices-burkina/settings/actions
2. **Settings du compte → Billing and plans → Plans and usage → Actions** : vérifier le quota inclus, l'utilisation et la limite de dépenses. Ne pas relever la limite de dépenses ni activer de paiement pour cette réparation ; si le quota gratuit est épuisé, attendre son renouvellement ou réduire les exécutions.
   Lien : https://github.com/settings/billing
3. Si Actions est autorisé et que le quota inclus est disponible, mais qu'un nouveau job échoue encore avec `runner_id=0`, transmettre les deux URLs de runs et les IDs des jobs à GitHub Support pour une investigation du provisioning.

Liens des runs concernés :
- https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/42323347582
- https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/42304226461


## 6. Résultats des validations après correction

### Flutter

- Run : https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43717217145
- Commit : `5428bc9255d52559bbacfaa47e3e4cde26f3318a`
- Conclusion : `success`
- `flutter analyze --no-fatal-infos` : réussi ; aucune erreur ni avertissement bloquant.
- `flutter test` : 29 réussites, 0 échec.
- `flutter build web --debug` : réussi.

### Supabase Edge Functions

- Run : https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43717824685
- Commit : `f2384dbfbb7ffbcd6bb6b1f8a4d6ff817caf65d7`
- Conclusion : `success`
- `deno check` : les 22 points d'entrée Edge Function ont tous été contrôlés ; le job a terminé avec succès.

### État restant

- Les huit suites pgTAP (179 assertions) n'ont pas été exécutées dans une base Supabase locale reconstruite.
- Les builds Android/iOS Debug ne sont pas encore validés sur des runners natifs.
- Les tests E2E métier, paiements sandbox, notifications FCM et GPS sur appareils physiques restent distincts.
- Aucun déploiement, build Release, test remote SQL ou opération de paiement/remboursement n'a été effectué.

## 7. Validation et limites

- Les deux fichiers YAML ont été relus après enregistrement sur la branche de maintenance.
- Aucune nouvelle exécution n'a été déclenchée par cette modification de workflow.
- Les anciens jobs ont échoué avant attribution du runner. Depuis, le runner a été attribué et la validation Flutter est passée sur le run `43717217145` (29/29 tests et Web Debug). Aucun résultat Deno, pgTAP ou SQL n'est déclaré dans cette passe.
- Aucun workflow n'a été lancé ou relancé manuellement.
- Aucun build de publication, déploiement GitHub/Vercel, changement de base Supabase, migration distante, secret, donnée métier, paiement ou remboursement n'a été touché.
- `main` est restée inchangée.

**État :** la CI Flutter de la branche de maintenance a été exécutée avec succès. Le problème historique d'attribution runner n'empêche plus cette validation. La CI Edge Functions et les tests Supabase locaux restent à exécuter dans leurs validations dédiées.
