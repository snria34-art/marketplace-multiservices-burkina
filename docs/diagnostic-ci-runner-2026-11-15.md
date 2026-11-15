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
- Les contrôles restent : dépendances verrouillées, `flutter analyze`, `flutter test` et compilation de validation Flutter Web avec valeurs Supabase factices. Il n'y a aucune étape de publication ou de déploiement.

### `.github/workflows/supabase-functions-ci.yml`

- Ajout de `maintenance/audit-01-07-2026-11-15` aux branches suivies par le déclencheur `push`.
- Image runner épinglée à `ubuntu-24.04`.
- Suppression du workflow lui-même de la liste des chemins du déclencheur `push`.
- Le job reste limité à `deno check` de chaque point d'entrée Edge Function. Il ne déploie aucune fonction.

Ces changements rendent la branche de maintenance vérifiable lors des prochains changements de code. L'image runner fixe élimine l'ambiguïté de l'alias `ubuntu-latest`, mais ne contourne pas une restriction de compte, une limite de facturation ou une panne du service d'attribution des runners.

## 3. Action requise dans les paramètres GitHub — sans frais

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

## 4. Validation et limites

- Les deux fichiers YAML ont été relus après enregistrement sur la branche de maintenance.
- Aucune nouvelle exécution n'a été déclenchée par cette modification de workflow.
- Aucun test Flutter, Deno ou SQL n'a été déclaré réussi : les jobs précédents n'ont exécuté aucune étape et les exécutables Flutter, Dart, Deno, Supabase CLI et PostgreSQL ne sont pas présents dans l'environnement de travail.
- Aucun workflow n'a été lancé ou relancé manuellement.
- Aucun build de publication, déploiement GitHub/Vercel, changement de base Supabase, migration distante, secret, donnée métier, paiement ou remboursement n'a été touché.
- `main` est restée inchangée.

**État :** la configuration CI de la branche de maintenance est corrigée. Le blocage d'attribution des runners est externe au dépôt et nécessite la vérification des paramètres GitHub ci-dessus ; il ne peut pas être réparé par une modification de code dans ce dépôt seul.
