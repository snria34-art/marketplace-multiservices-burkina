# AUD-20 — Revue des index signalés inutilisés

**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**PostgreSQL :** 17.6.1  
**Date de mesure :** 7 novembre 2026  
**État :** diagnostic terminé ; aucune suppression d'index effectuée.

## 1. Résultat de l'advisor

Supabase Performance Advisor retourne 366 avertissements `unused_index` (niveau INFO) observés le 6 novembre 2026 à 21:40 UTC.

Le relevé PostgreSQL détaillé confirme :

- `pg_stat_database.stats_reset = 2026-08-25 20:33:23 UTC`.
- 571 index dans `public`, dont 559 sans scan.
- 44 index dans `private`, dont 39 sans scan.
- Parmi ces 598 index public/private sans scan :
  - 232 sont primaires ou uniques (contraintes / unicité), hors des 366 candidats de l'advisor ;
  - 366 sont non uniques et non primaires, soit le décompte exact de l'advisor.
- Taille cumulée des 366 index non uniques sans scan : 3 031 040 octets, environ 2,9 MiB.
- Taille de tous les index public/private sans scan, contraintes incluses : 5 414 912 octets, environ 5,2 MiB.
- Les index Auth, Storage, Cron, Realtime et autres schémas ajoutent leurs propres index sans scan ; ils ne doivent pas être assimilés aux 366 recommandations de l'advisor public/private.

La plupart des tables métier concernées ont `n_live_tup = 0`. Au moment du snapshot : aucun profil, produit, commande, paiement, remboursement, affectation de livraison ou message métier réel n'avait été créé. Les index de ces futures fonctions ne peuvent donc pas encore avoir été sollicités par le trafic utilisateur attendu.

Les statistiques de scan sont des compteurs depuis le dernier reset : elles ne prouvent pas qu'un index ne sera jamais utilisé.

## 2. Index à préserver absolument

Ne pas supprimer :
- un index primaire ;
- un index unique (dont ceux portant les références de paiement, les clés d'idempotence checkout, les slugs, les noms normalisés de boutique, les identifiants de lignes et les contraintes d'intégrité) ;
- un index référencé par une contrainte, une exclusion, une clé étrangère ou un mécanisme d'idempotence ;
- un index nécessaire à un chemin de service futur même si le jeu de données est vide.

Le relevé inclut par exemple des index uniques pour :
- `public.shops.normalized_name` ;
- `public.products.slug` ;
- `public.checkout_requests(user_id, idempotency_key)` ;
- `public.payment_events(provider_reference)` ;
- `public.payments(order_id)` pour les paiements PENDING/PROCESSING ;
- `public.refunds(provider_reference)` ;
- les clés primaires et étrangères.

Ces index garantissent l'intégrité et la sécurité, indépendamment du volume de lectures.

## 3. Index non uniques sans scan mais stratégiques pour les futures fonctions

Les index suivants ont `idx_scan=0` à la date du relevé, mais correspondent directement à des parcours déjà codés :

| Index | Parcours qui l'utilise / justifie sa présence |
|---|---|
| `idx_orders_customer_created` | Historique des commandes d'un client |
| `idx_products_shop_status` | Liste produits d'une boutique et état |
| `idx_products_expiry` | Filtre des produits proches de péremption |
| `idx_packages_status` | Filtrage des colis par état |
| `idx_delivery_assignments_courier` | Missions du livreur par état |
| `idx_courier_locations_time` | Dernières positions GPS d'un livreur |
| `idx_messages_conversation_time` | Historique de conversation |
| `idx_payment_events_payment` | Historique des événements d'un paiement |
| `idx_seller_ledger_seller` | Relevé comptable du vendeur |
| `idx_payouts_seller` | Paiements sortants par vendeur |
| `idx_refunds_order` | Remboursements par commande |

Ils sont conservés. Leur coût de stockage est actuellement minime et supprimer un index avant la mise en activité risquerait de rendre les premiers parcours lents ou de nécessiter une migration urgente au moment du lancement.

## 4. Taille et activité

- Base entière : environ 80 Mo lors du snapshot AUD-18.
- Tous les index PostgreSQL observés : environ 9,5 Mo.
- Les 366 index non uniques signalés représentent environ 2,9 MiB.
- Les tables volumineuses de diagnostics (`private.platform_health_checks`, `private.platform_agent_runs`) dominent le stockage de quelques index, mais la majorité des tables opérationnelles ne contiennent aucune ligne métier.
- Dernier `ANALYZE` maximal observé : 21 septembre 2026 à 06:20 UTC.
- Dernier `AUTOANALYZE` maximal observé : 6 novembre 2026 à 21:23 UTC.

La mesure doit être répétée après un trafic réel représentatif et après le chargement d'un jeu de données de test.

## 5. Procédure de revue avant toute suppression future

1. Attendre un jeu de données représentatif et au moins un cycle métier complet (catalogue, commandes, paiements, livraison, remboursements).
2. Vérifier `stats_reset`, `last_analyze`, `last_autoanalyze` et la période de trafic mesurée.
3. Exporter la liste des index candidats avec schéma, table, définition, taille, `idx_scan`, `idx_tup_read`, `idx_tup_fetch`, statut unique/primary et dépendances contraintes.
4. Examiner le code SQL/RPC, les requêtes PostgREST, les filtres RLS et les requêtes des Edge Functions liées à chaque index.
5. Mesurer `EXPLAIN (ANALYZE, BUFFERS)` sur des requêtes représentatives dans staging avec volumes réalistes ; ne pas utiliser de charge artificielle sur production.
6. Rechercher des index redondants ou des préfixes couverts, mais conserver les variantes partielles/trigramme/géographiques qui répondent à des requêtes spécifiques.
7. Présenter une migration de suppression limitée à un index non unique non-primary, avec sauvegarde et comparaison des plans, seulement après validation du propriétaire.
8. Mesurer le temps d'écriture et la latence lecture après changement.

Ne pas supprimer en masse ni utiliser la seule sortie `unused_index` de l'advisor comme autorisation de suppression.

## 6. État AUD-20

- 366 avertissements advisor reproduits par le décompte PostgreSQL des index public/private non uniques non primaires sans scan.
- 232 index primaires/uniques supplémentaires sont sans scan mais ne font pas partie des candidats de l'advisor.
- 0 suppression d'index ; aucune migration DDL créée.
- Aucune donnée, commande, paiement ou stock modifié.
- Revue à refaire après la mise en activité ou un benchmark staging réaliste.
