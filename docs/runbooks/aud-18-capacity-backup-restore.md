# AUD-18 — Capacité, sauvegardes et reprise

**Projet :** Marketplace Multiservices Burkina  
**Supabase ref :** `dzhhsoikzxibmngjzcch`  
**Audit :** 7 novembre 2026  
**État :** premier relevé en lecture seule terminé ; aucun test de charge, backup restore ou changement de compute n'a été effectué.

## 1. Capacité observée maintenant

Snapshot PostgreSQL / Supabase :

- Projet : `ACTIVE_HEALTHY`, PostgreSQL 17.6.1, région `eu-west-1`.
- Taille de la base : environ 80 MB.
- `max_connections = 60`, `superuser_reserved_connections = 3`.
- 11 connexions client PostgreSQL au moment de l'échantillon, toutes inactives ; la répartition incluait les services Supabase, PostgREST et PgBouncer.
- La connexion au pooler est bien présente dans les rôles/logs ; le rôle PostgreSQL `pgbouncer` apparaissait parmi les connexions.
- Sur les logs PgBouncer des dernières 24 h : 0 occurrence « max client connections reached », 0 « client login timeout », 0 « no more connections allowed », 0 « server login retry » ; 71 fermetures `server idle timeout`.
- `pg_stat_database` : zéro deadlock depuis le reset des statistiques (25 août 2026) ; 153 rollbacks, 4 sessions tuées, 50 sessions abandonnées. Ces compteurs sont cumulés depuis le reset, pas des mesures par jour.
- `pg_stat_archiver` : 33 222 fichiers WAL archivés, 0 échec, dernier fichier archivé le 6 novembre 2026 à 21:25:50 UTC. C'est un indicateur d'archivage WAL ; ce n'est pas une preuve que les sauvegardes quotidiennes ou PITR sont activés et restaurables.
- Aucun slot de réplication ni connexion de réplication détecté.

La limite de 60 est celle de Postgres, pas le nombre d'utilisateurs de l'application. Les connexions clientes poolées peuvent être beaucoup plus nombreuses que les connexions PostgreSQL backend, mais les deux plafonds doivent être suivis séparément.

Supabase publie des limites de pooler client par compute : Nano/Micro 200, Small 400, Medium 600, Large 800, XL 1 000, 2XL 1 500, 4XL 3 000, 8XL 6 000, 12XL 9 000 et 16XL 12 000. Le compute exact et la limite actuelle du pooler de ce projet n'ont pas été retournés par les outils de lecture ; ils doivent être vérifiés dans Dashboard > Settings > Infrastructure / Database Settings. Sources officielles : [Compute and Disk](https://supabase.com/docs/guides/platform/compute-and-disk) et [Connection management](https://supabase.com/docs/guides/database/connection-management).

## 2. Conclusion provisoire sur 1 000 à 10 000 utilisateurs

**La capacité de 1 000 à 10 000 utilisateurs simultanés n'est pas démontrée.** À l'heure du contrôle, la base a 60 connexions directes au maximum et seulement 11 connexions clients observées. Cela ne signifie pas qu'elle ne peut pas servir 1 000 utilisateurs via un pooler, ni qu'elle pourrait supporter 10 000 : il faut un test de charge sur un environnement de staging et un compute approprié.

Ne pas connecter chaque session mobile directement à PostgreSQL. Les accès doivent passer par Supabase Auth/Data API/Edge Functions et un pooler ; garder les connexions backend sous le plafond disponible, laisser des connexions aux services Auth/Storage/PostgREST et limiter les opérations longues. Ne pas augmenter `max_connections` manuellement sans calcul du compute, mémoire et pool sizes.

## 3. Script k6 préparé (lecture seule)

Fichier : `tests/load/k6_readonly_supabase_categories.js`.

- Requiert `TARGET_ENV=staging` et refuse explicitement le ref production.
- Interroge seulement `GET /rest/v1/categories` (30 lignes maximum) avec la clé publique.
- Paliers : 100 VUs, 1 000 VUs, puis `K6_PEAK_VUS=1000` ou `10000`, enfin retour à zéro.
- Seuils de départ : échecs HTTP < 1 %, p95 < 1 000 ms, p99 < 2 000 ms.
- Une attente de cinq secondes par itération évite le tight-loop ; les seuils et l'endpoint doivent être adaptés à un vrai parcours avant d'en tirer une capacité utilisateur.

Exemple, sur un projet de staging seulement :

```bash
k6 run \
  -e TARGET_ENV=staging \
  -e SUPABASE_URL=https://<staging-project-ref>.supabase.co \
  -e SUPABASE_ANON_KEY=<staging-publishable-or-anon-key> \
  -e K6_PEAK_VUS=1000 \
  tests/load/k6_readonly_supabase_categories.js
```

Le palier 10 000 doit être lancé séparément, après validation du palier 1 000, des coûts compute/pooler, des métriques CPU/mémoire et d'un budget. Le script n'a pas été lancé dans ce travail ; aucune charge n'a été générée sur production.

Ce script n'éprouve que la lecture publique de catégories. Un test réaliste final doit couvrir navigation catalogue, lecture produits, authentification, panier, checkout sandbox, consultations de commande, messages et suivi, avec un dataset de staging et scénarios de montée/descente. Les flux d'écriture doivent utiliser des comptes et produits factices, jamais les données de production.

## 4. État des données (staging / production)

Au moment de l'audit :

- `auth.users` : 0 compte utilisateur ;
- `public.profiles` : 0 profil ;
- `public.products` : 0 produit ;
- `public.orders`, paiements, remboursements, affectations livreur : aucune ligne métier recensée dans les contrôles précédents ;
- `storage.objects` : 0 objet ;
- les tables volumineuses sont principalement `spatial_ref_sys` (8 500 SRID) et les tables diagnostics `platform_health_checks` / `platform_agent_runs`.

Il n'y a donc pas de dataset transactionnel représentatif. Les tests de charge ne sont pas valides tant que des produits, boutiques, clients, commandes, paniers et affectations de test ne sont pas seedés sur un projet isolé.

## 5. Sauvegardes et restauration

Les outils connectés permettent de lire le projet, les statistiques et l'archiver WAL, mais ne retournent pas la liste des backups du projet ni leurs points de restauration. Le plan Supabase du projet n'est pas exposé par l'outil de lecture utilisé. **L'activation des sauvegardes quotidiennes et leur rétention restent donc à confirmer dans Dashboard > Database > Backups.**

La documentation Supabase, mise à jour le 5 novembre 2026, indique :
- les projets Pro, Team et Enterprise reçoivent des sauvegardes quotidiennes ;
- Pro : 7 jours, Team : 14 jours, Enterprise : jusqu'à 30 jours ;
- le Free plan doit exporter les données régulièrement avec Supabase CLI et conserver un backup hors site ;
- PITR est une option payante pour un point de restauration plus précis ;
- les backups de base n'incluent pas les objets stockés dans Supabase Storage.

Source : [Database Backups](https://supabase.com/docs/guides/platform/backups).

### Procédure de preuve à exécuter avant production

1. Vérifier le plan du projet dans Billing et les backups disponibles dans Database > Backups.
2. Capturer le backup le plus récent, sa date/heure, la rétention et le dernier point récupérable.
3. Fixer et documenter les objectifs métier RPO/RTO ; ne pas annoncer de valeur avant mesure.
4. Sauvegarder séparément les objets Storage, car les backups DB ne rétablissent pas les binaires Storage.
5. Restaurer le backup dans un projet isolé / staging, jamais directement sur production.
6. Vérifier profils, rôles custom, données métiers, fonctions, extensions, RLS et accès Storage après restauration.
7. Mesurer le temps de restauration complet et noter les opérations manuelles restantes (réinitialisation des mots de passe des rôles personnalisés, clés externes, objets Storage).
8. Faire approuver le résultat par le propriétaire avant de conclure que le plan de reprise est prêt.

La base PostgreSQL actuelle est en version 17.6, donc éligible au mécanisme de sauvegarde physique par défaut décrit par Supabase ; cela ne confirme pas que le projet dispose d'un plan payant avec sauvegardes quotidiennes.

## 6. État AUD-18

- Snapshot de capacité : obtenu.
- Saturation instantanée : non observée ; ce n'est pas un test de charge.
- Absence de saturation dans les logs PgBouncer 24 h : confirmée.
- WAL archiver : 33 222 archivages, zéro échec depuis le reset des statistiques.
- Limite de connexions directe et compute exact : 60 max_connections observés ; taille compute/plan et pooler-client exacts à vérifier dans le Dashboard.
- Dataset de charge : absent ; pas de profil multi-utilisateur significatif.
- Test k6 staging : préparé, non exécuté.
- Backups quotidiens/PITR : non vérifiés.
- Restore : non testé.
- Objets Storage : 0 actuellement, prévoir un backup indépendant avant production.
- Aucun compute, pool size, plan, backup, donnée ou ressource payante n'a été modifié.
