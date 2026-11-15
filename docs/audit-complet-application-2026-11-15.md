# Audit transversal de l'application — 15 novembre 2026

**Dépôt :** `snria34-art/marketplace-multiservices-burkina`  
**Branche examinée :** `maintenance/audit-01-07-2026-11-15`  
**Objet :** état technique, sécurité, métier, exploitation et tests avant toute ouverture publique.  
**Nature :** revue statique du code versionné, lecture des workflows et rapports techniques antérieurs, vérification des commits CI connus. Ce document n'est pas une certification de production ni un audit réglementaire.

## 1. Conclusion exécutive

L'application présente une base Flutter/Supabase étendue et plusieurs protections déjà sérieuses : vérifications de session et de rôles dans le routeur, RPC serveur pour les opérations sensibles, règles RLS, webhooks de paiement signés, contrôle serveur du stock, limites et permissions sur les preuves de livraison, contrôle de l'affectation active pour les positions GPS et vérification de secrets avant l'envoi FCM.

**L'application n'est pas prête à être certifiée sans réserve ni à être ouverte aux paiements réels.** Trois risques P1 restent non résolus : l'allocation comptable des remboursements, la protection de `public.spatial_ref_sys` qui dépend de Supabase Support, et la reproductibilité complète des migrations/tests SQL. Le parcours de remboursement est particulièrement sensible : le fournisseur Wave peut confirmer un remboursement externe avant que l'écriture interne du ledger échoue.

### Inventaire du dépôt examiné

| Élément | Volume constaté |
|---|---:|
| Fichiers versionnés | 606 |
| Fichiers Dart sous `lib/` | 79 |
| Domaines Flutter sous `lib/features/` | 21 dossiers |
| Verticales métier déclarées | 16 |
| Migrations SQL | 347 |
| Fonctions Edge (points d'entrée `index.ts`) | 22 |
| Tests Flutter | 8 fichiers |
| Tests SQL pgTAP | 8 fichiers |
| Assertions pgTAP déclarées | 179 |
| Fichiers natifs Android et iOS | 61 |

## 2. Registre des constats prioritaires

### P1 — Remboursements et ledger vendeur : blocage financier confirmé

**Preuve dans le code :** `supabase/migrations/20260921224022_v133_finalize_refund_payment_and_seller_ledger.sql`, fonction `public.complete_refund(uuid,text)`.

La fonction répartit un remboursement au prorata du sous-total de tous les groupes vendeurs de la commande, sans allocation explicite par article, quantité ou groupe. Un remboursement ne concernant qu'un article d'une boutique peut donc imputer une partie de la charge à un autre vendeur. Si un vendeur possède plusieurs boutiques/groupes dans la commande, plusieurs lignes `REFUND` avec le même `seller_id + entry_type + refund_id` peuvent également violer la contrainte unique du ledger.

Le chemin `execute-payment-refund` appelle Wave avant `complete_refund`. Si Wave rembourse mais que la transaction PostgreSQL échoue ensuite, l'état externe et le ledger local divergent ; un nouvel appel au prestataire n'est surtout pas une stratégie de reprise sûre. Un autre cas est la capture tardive d'un paiement après annulation : aucun crédit SALE vendeur n'a nécessairement été créé, mais le finaliseur de remboursement peut quand même débiter des groupes.

**Décision :** ne pas modifier les fonctions financières, les soldes, le ledger ou les remboursements tant que le modèle d'allocation n'est pas validé. Le runbook `docs/runbooks/aud-02-refund-allocation.md` décrit le modèle attendu : snapshots de prix et de remises au checkout, lignes/quantités de retour, allocations immuables, séparation de la charge vendeur/commission/plateforme/livraison, idempotence et rapprochement interne après confirmation du prestataire.

### P1 — PostGIS dans le schéma public : risque d'intégrité confirmé par le dernier relevé documenté

Le runbook `docs/runbooks/aud-01-postgis-schema-move.md` rapporte PostGIS 3.3.7 installé dans `public`, propriété de `supabase_admin`, avec des droits d'écriture/troncature `anon` et `authenticated` sur `public.spatial_ref_sys`. Une altération des SRID peut casser des calculs géographiques. Le rôle de projet ne peut pas retirer proprement les grants accordés par le propriétaire de l'extension.

Les deux RPC applicatives ont déjà été préparées pour résoudre PostGIS depuis `extensions` après intervention du support. Le déplacement n'est pas terminé. Ne pas tenter de `DROP EXTENSION`, de déplacement forcé, de `REVOKE` supposé suffisant ni de trigger bricolé.

**Action :** ticket Supabase Support, déplacement non destructif, puis contrôles post-déplacement des trois colonnes `geography`, des index GiST, des vues, des fonctions et des droits. Le constat live n'a pas été rafraîchi pendant le présent audit.

### P1 — Historique et reconstruction SQL : non certifiés

Le dépôt contient 347 migrations. Le dernier rapprochement documenté signalait une divergence d'une migration autour de `20261104020500` (l'effet SQL était déjà présent sur la base observée, mais l'historique restait à rapprocher). Cette information est historique : aucune base Supabase n'est accessible via le connecteur pendant cet audit et aucune vérification distante actuelle n'a été faite.

Les huit fichiers pgTAP ont été contrôlés statiquement : les plans déclarés et les appels d'assertion recensés concordent, pour un total de **179**. Ce comptage ne prouve pas que PostgreSQL accepte les migrations, que les fixtures sont cohérentes ou que les assertions réussissent.

Le workflow `.github/workflows/supabase-db-tests.yml` est manuel et limité à la branche de maintenance. Il installe une CLI épinglée, démarre une stack locale, exécute `supabase db reset --local`, puis `supabase test db --local`, et arrête la stack. Il ne contient pas de connexion ou de commande SQL distante. **Il n'a pas encore été exécuté.**

### P1 — Paiements Wave/CinetPay : intégrité du protocole partiellement revue, exploitation non vérifiée

Les sources incluent des webhooks qui vérifient la signature fournisseur, contrôlent les montants/devise (et, pour CinetPay, re-vérifient la transaction auprès du prestataire) avant d'appeler `process_payment_event`. Les fonctions de création de session exigent une session Supabase et vérifient que le paiement appartient à la commande et au client.

Le moniteur de santé rapporté le 6 novembre 2026 indiquait Wave et CinetPay `NOT_CONFIGURED` faute de secrets marchands. Cette configuration n'a pas été revérifiée aujourd'hui. Aucun scénario sandbox signé, retry webhook, latence fournisseur, annulation de commande ou capture tardive n'a été rejoué dans cette session.

**Action :** tests d'intégration sur faux prestataire puis sandbox, avec vérification d'idempotence, ordre des transitions, montants, devise, références, délais et rapprochement. Aucun paiement réel ne doit servir de test.

### P1 — Notifications push : service non opérationnel selon le dernier état documenté

Le code FCM vérifie le secret interne de dispatch, utilise un compte de service côté Edge Function et gère les tokens invalides. Toutefois, le dernier état de santé documenté (6 novembre 2026) indiquait `FCM_SERVICE_ACCOUNT_JSON_missing` et aucun identifiant de projet Firebase. Aucun fichier Firebase natif (`google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`) n'est présent dans l'arbre du dépôt.

**Défaut de fiabilité confirmé dans le code :** quand plusieurs appareils sont ciblés et qu'au moins un envoi réussit, `push_sent_at` est défini même si d'autres appareils ont échoué. La notification ne sera alors plus sélectionnée par le balayage des notifications en attente ; les appareils ayant échoué peuvent manquer le message. Prévoir une stratégie d'état/réessai par appareil ou un suivi des destinataires, sans renvoyer en boucle aux appareils déjà servis.

### P2 — GPS coursier : bonne garde serveur, confidentialité et validation terrain incomplètes

Le code demande une mission active avant l'activation et le serveur vérifie encore l'affectation à chaque écriture de position. Les permissions Android/iOS et un flux Geolocator continu sont présents.

Les contrôles suivants restent ouverts : comportement réel application en arrière-plan et écran verrouillé sur Android et iOS, arrêt après révocation de permission/fin de mission, consommation batterie, absence de fuite de position à une commande terminée. Le runbook AUD-14 précise que la durée de conservation/purge des coordonnées GPS n'est pas définie. La conservation de coordonnées précises doit être décidée et documentée avant production.

### P2 — Médias et documents : validation du type binaire à renforcer

Le code mobile limite la taille des fichiers et contrôle les extensions/types MIME annoncés par le sélecteur. Les runbooks signalent toutefois que le type MIME déclaré par le client et l'extension ne prouvent pas la signature réelle du contenu binaire. C'est particulièrement important pour les preuves de livraison, médias d'avis et documents de santé.

**Action :** valider le format réel côté serveur ou par un pipeline d'inspection contrôlé, conserver les buckets sensibles privés, tester les accès positifs/négatifs par rôle et prévoir le nettoyage des objets orphelins. Ne pas assouplir les policies Storage pour contourner un échec d'upload.

### P2 — RBAC administrateur : séparation ADMIN/MODERATOR améliorée, permissions fines manquantes

Le contrôle de route vérifie l'état actif du profil, le rôle vendeur/coursier et l'inscription administrateur. Les routes de modération sont distinctes des contrôles plateforme. Côté SQL, des corrections antérieures ont séparé les opérations globales réservées aux administrateurs enregistrés des files de modération accessibles au modérateur.

La matrice granulaire `admin_role_id` / permissions par domaine n'est pas encore implémentée. Les actions finance, comptes, logistique, plateforme, réparations et gestion des rôles doivent être protégées par permissions précises, pas uniquement par un rôle générique. Ajouter aussi une procédure de protection du dernier propriétaire, une ré-authentification/MFA pour les opérations critiques et un journal d'audit immuable.

### P2 — Architecture Flutter : concentration excessive des verticales

`lib/features/verticals/presentation/vertical_discovery_page.dart` est un écran de plus de 3 200 lignes qui regroupe de nombreux formulaires, listes, décisions et actions pour 16 verticales. Cela concentre les effets de bord et rend les tests par parcours et la maintenance risqués.

**Action :** découper progressivement par verticales (présentation, état, formulaires, navigation et tests), sans réécrire toutes les verticales en une seule migration. Extraire d'abord les domaines santé, agriculture, immobilier, professionnel et créatif qui comportent les workflows les plus sensibles.

### P2 — Accessibilité Web : correction appliquée, à revalider

`web/index.html` désactivait le zoom du navigateur avec `maximum-scale=1.0` et `user-scalable=no`. La restriction a été retirée sur la branche de maintenance ; le viewport est maintenant standard. Le build Web Debug devra être rejoué pour confirmer l'absence de régression.

### P2 — CI et reproductibilité des outils

Le dernier log Flutter disponible remonte au 15 novembre 2026 sur un commit antérieur aux corrections de cycle de vie. Il affichait 396 diagnostics de niveau `info` (principalement concaténation de chaînes et paramètres de callbacks). Les diagnostics de cycle de vie `BuildContext` ont été corrigés ensuite, mais l'analyse n'a pas encore été relancée sur la tête actuelle.

Le log contenait aussi un avertissement de dépréciation Node.js 20 sur `actions/checkout@v4`. Le workflow Deno utilise `deno-version: v2.x`, donc une version flottante. À terme, mettre à niveau les actions compatibles Node 24, épingler Deno et les actions tierces sur des versions vérifiées (idéalement SHA) et conserver un calendrier de mise à jour.

## 3. Corrections réalisées pendant cette passe

Toutes ces modifications ont été faites uniquement sur `maintenance/audit-01-07-2026-11-15` :

- Ajout de vérifications `dialogContext.mounted` après les attentes asynchrones dans les actions des verticales (commit `5d48c0013f75502db5089d4d2b39ace4ec3b63a8`).
- Vérification de l'état `mounted` de l'écran mécanicien après l'appel RPC, avant d'ouvrir le sélecteur de dates (commit `6d0734b9bb588a298e2c72270f1483b4c04e30bd`).
- Protection du contexte des dialogues de coupons et promotions après les sélecteurs de dates (commits `33b45a4c71a4711297385a8213f4c5cf7689fbae` et `21cec096e4b9853f8a68414e548436fdf8d18fa3`).
- Réactivation du zoom navigateur pour l'accessibilité (commit `b043d8c2d905021ebdbe6de4611bcf4f2b78c4b1`).
- Renforcement et clarification de la reconstruction PostgreSQL locale avec `supabase db reset --local` avant pgTAP.
- Correction du rapport Vercel pour préciser que la configuration d'arrêt est portée par la branche de maintenance et ne remplace pas le réglage global du projet.

## 4. Contrôles confirmés et limites

| Contrôle | Résultat connu | Portée |
|---|---|---|
| Flutter CI | 29 tests réussis, analyse terminée, build Web Debug réussi | Run antérieur au présent audit ; 396 diagnostics `info` |
| Deno Edge Functions | `deno check` réussi sur 22 points d'entrée | Run antérieur ; sources Edge non modifiées pendant cette passe |
| pgTAP | 179 assertions statiquement cohérentes | Pas d'exécution PostgreSQL |
| Android APK Debug | Non exécuté | Workflow manuel seulement |
| iOS Simulator Debug | Non exécuté | Workflow manuel seulement |
| Parcours E2E métier | Non exécutés | Comptes et jeux de données de test requis |
| RLS / Storage live | Pas de nouvel essai live | Derniers relevés consignés dans les runbooks |
| Paiements et push sandbox | Non exécutés | Aucun secret ou compte marchand disponible/vérifié |
| Vercel | Accès de lecture refusé au scope `ridiastore` | Aucun Preview/Production vérifié |

À la tête courante de cette branche, GitHub ne retourne pas encore de workflow run ni de statut CI. Les réussites Flutter et Deno citées plus haut ne doivent donc pas être présentées comme une validation de tous les commits ajoutés après ces runs.

## 5. Vercel et protection de `main`

Le `vercel.json` modifié est dans la branche de maintenance. Le `vercel.json` de `main` est resté inchangé et ne comporte pas `git.deploymentEnabled`. La configuration de maintenance ne constitue donc pas une désactivation projet-wide de Vercel. L'accès à l'équipe Vercel est refusé ; il faut que le propriétaire confirme la désactivation des déploiements automatiques dans le tableau de bord avant tout push futur sur `main`.

Aucun déploiement manuel, build Vercel, Preview, Production, publication de store, merge ou migration distante n'a été lancé pendant cet audit. La branche `main` n'a pas été modifiée.

## 6. Ordre de travail recommandé

1. **Geler les opérations financières à risque** : définir et approuver le modèle d'allocations, snapshots et rapprochement des remboursements ; créer des tests transactionnels multi-vendeurs et de capture tardive.
2. **Résoudre AUD-01 avec Supabase Support** puis vérifier PostGIS, les droits et les RPC.
3. **Reconstruire PostgreSQL localement** sur runner isolé, résoudre toute migration manquante, exécuter les 179 assertions pgTAP et corriger chaque échec avant d'élargir les tests.
4. **Relancer Flutter CI sur la tête actuelle**, puis exécuter les builds Android/iOS Debug. Ne pas produire de Release.
5. **Ajouter les tests E2E** : rôles client/vendeur/coursier/admin/modérateur, checkout/stock concurrent, webhooks simulés, annulations, retours, remboursements, accès Storage et notifications.
6. **Traiter l'opérationnel** : configurer Wave/CinetPay/FCM par les consoles propriétaires, exécuter les tests sandbox et définir la rétention GPS.
7. **Compléter le RBAC fin et la validation média**, puis découper les gros écrans verticaux.
8. **Avant toute reprise Vercel**, faire confirmer le verrou global depuis le compte Vercel et vérifier le sort des statuts/previews antérieurs ; ne pas réactiver automatiquement à la fin de ces travaux.

## 7. Périmètre explicitement non touché

Aucune écriture SQL distante, migration Supabase hébergée, donnée utilisateur, compte, commande, stock, solde, paiement, remboursement, secret marchand, secret Firebase, clé de signature, déploiement Vercel, upload store, build Release, PR ou merge sur `main` n'a été effectué. Les décisions métier nécessaires aux remboursements, au financement des remises et à la conservation GPS n'ont pas été inventées.
