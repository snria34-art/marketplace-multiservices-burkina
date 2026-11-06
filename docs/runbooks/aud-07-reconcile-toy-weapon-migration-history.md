# AUD-07 — Réconcilier l'historique de la migration du classificateur produits

**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**Dépôt :** `adjasanou49-max/marketplace-multiservices-burkina`  
**Migration concernée :** `20261104020500_add_toy_weapon_product_classification.sql`  
**État :** effets fonctionnels déjà présents sur la base ; entrée de migration distante manquante ; réparation d'historique préparée mais non exécutée depuis cet environnement.

## 1. Diagnostic comparatif

GitHub contient 328 fichiers de migration et Supabase en consigne 327. Le seul numéro GitHub absent de l'historique distant est `20261104020500`.

### Fonction active

La migration GitHub crée `private.scan_toy_weapon_products()`. La fonction existe déjà sur Supabase.

Comparaison du corps SQL :
- après normalisation des espaces et des espaces après virgule uniquement, le corps versionné et le corps déployé sont identiques ;
- propriétaire distant : `postgres` ;
- `SECURITY DEFINER` est activé ;
- `search_path = ''` ;
- ACL effective : seul `postgres` a EXECUTE ; `anon`, `authenticated` et `service_role` n'ont pas ce droit.

La fonction détecte les termes jouets/armes dans les noms et descriptions de produits, écrit des constats `TOY_WEAPON_REPRESENTATION` de gravité `REVIEW`, puis journalise un passage d'agent. Elle n'effectue pas de blocage automatique du produit.

### Cron actif

Le job distant `toy-weapon-classifier` existe et est actif :

- job ID : 5
- calendrier : `*/10 * * * *`
- commande : `select private.scan_toy_weapon_products();`
- utilisateur : `postgres`

La commande correspond au contenu versionné de la migration. La migration d'origine utilise un `cron.unschedule` puis un `cron.schedule`; il ne faut donc pas la rejouer pour « corriger l'historique », car cela remplacerait le job actif.

### Dépendances

Les relations utilisées et retrouvées sur la base :
- `public.products`
- `private.catalog_moderation_findings`
- `private.platform_agent_runs`

Le trigger `private.prevent_reactivation_of_restricted_product()` est aussi présent sur `public.products`, mais il est indépendant de cette migration et n'a pas été inclus dans la réparation.

## 2. Action recommandée : réparer uniquement l'historique

La documentation officielle Supabase décrit `supabase migration repair` comme l'outil permettant d'ajouter ou retirer des entrées de l'historique distant sans rejouer le SQL de la migration.

Après avoir vérifié que le terminal est bien lié au projet `dzhhsoikzxibmngjzcch`, exécuter :

```bash
supabase migration list
supabase migration repair 20261104020500 --status applied
supabase migration list
```

Résultat attendu : les listes locale et distante présentent désormais le numéro `20261104020500` des deux côtés ; le total doit être de 328 migrations.

**Important :** cette commande ne doit être exécutée qu'après authentification CLI et liaison explicite au bon projet. Elle ne crée/rejoue pas la fonction, ne modifie aucune ligne de produit et ne touche pas au cron. Elle marque uniquement la version déjà présente sur la base comme appliquée.

Documentation Supabase :
https://supabase.com/docs/reference/cli/supabase-migration-repair

## 3. Vérifications après réparation

1. Relancer `supabase migration list` et confirmer l'alignement local/distant à 328.
2. Re-vérifier `private.scan_toy_weapon_products()` : propriétaire postgres, `SECURITY DEFINER`, `search_path = ''`, ACL sans EXECUTE pour les rôles client.
3. Re-vérifier le job `toy-weapon-classifier` : un job actif, calendrier `*/10 * * * *`, commande inchangée.
4. Re-vérifier les relations dépendantes.
5. Ne pas lancer manuellement la fonction de scan pour valider la migration : elle écrit dans `private.catalog_moderation_findings` et `private.platform_agent_runs`. La présence du code et du cron est déjà vérifiée.

## 4. Limite de réalisation

La réparation de l'historique n'a pas été exécutée depuis l'agent : les outils Supabase connectés peuvent lire l'historique et appliquer des migrations SQL, mais ils ne fournissent pas la commande CLI `supabase migration repair`. Aucun INSERT manuel dans `supabase_migrations.schema_migrations` n'a été effectué. C'est volontaire : utiliser l'outil officiel garantit la sémantique attendue du réparateur Supabase sans toucher aux objets existants.

**État réel :** diagnostic et procédure terminés ; exécution CLI de la réparation encore requise.
