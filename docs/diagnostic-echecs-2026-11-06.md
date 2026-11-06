# Diagnostic des échecs CI et des intégrations — 6 novembre 2026

Dépôt : `adjasanou49-max/marketplace-multiservices-burkina`, branche `main`.

Ce rapport distingue les échecs d'infrastructure, les défauts de configuration et les erreurs de code. **Aucun workflow GitHub, test Flutter, test SQL, build natif, paiement ou notification de test n'a été lancé pendant cette intervention.**

## 1. GitHub Actions : aucun runner attribué

Les exécutions consultées :

- [Flutter CI — run 42089050684](https://github.com/adjasanou49-max/marketplace-multiservices-burkina/actions/runs/42089050684)
- [Supabase database tests — run 42089050574](https://github.com/adjasanou49-max/marketplace-multiservices-burkina/actions/runs/42089050574)

Les diagnostics de jobs associés aux échecs précédents montrent `runner_id=0`, aucun nom de runner et `steps=[]`. L'API GitHub ne fournit pas les journaux de ces jobs (404 `BlobNotFound`). Le même symptôme a été consigné dans `docs/phase-80-audit.md` pour les runs du 5 novembre.

**Conclusion :** le runner GitHub n'a pas démarré le job. Il n'y a donc aucune preuve que `flutter analyze`, `flutter test`, `deno check`, `supabase db reset` ou `supabase test db` aient été exécutés dans ces runs. Il serait incorrect d'attribuer ces échecs à une erreur de source ou de test.

**À vérifier dans GitHub avant la prochaine exécution autorisée :** Actions autorisées pour le dépôt, état de facturation/limites du compte, minutes Actions disponibles, restrictions d'organisation et disponibilité des runners GitHub-hosted. Les workflows restent manuels ; aucun déclenchement automatique n'a été ajouté.

## 2. Supabase : notifications push

Projet : `dzhhsoikzxibmngjzcch`.

### Cause confirmée

Les journaux du 6 novembre montrent que :

- le trigger serveur atteint bien `dispatch-push-notifications` par `pg_net` ;
- l'appel à `verify_push_dispatch_secret` répond HTTP 200 ;
- l'Edge Function déployée en version 7 répond HTTP 503 ;
- la source de cette version renvoie explicitement `fcm_not_configured` lorsque `FCM_SERVICE_ACCOUNT_JSON` est absent ;
- l'advisor Health signale 5 réponses 5xx sur 5 requêtes pendant deux fenêtres consécutives.

Le contrôle du secret de dispatch réussit : le problème se situe ensuite, au niveau de la configuration FCM. Le secret Firebase est une donnée privée qui doit être créée dans les secrets Supabase, jamais dans GitHub ou dans le code Flutter.

### Correction effectuée

La source déjà présente dans le dépôt a été synchronisée vers Supabase. La fonction `dispatch-push-notifications` est maintenant en **version 8**.

Cette version apporte notamment :
- une limite de cinq notifications traitées en parallèle ;
- une gestion des erreurs isolée par appareil ;
- la désactivation des tokens FCM explicitement invalidés ;
- la conservation des erreurs d'envoi au niveau de la notification.

Le réglage `verify_jwt=false` a été conservé, car la fonction utilise son contrôle serveur `verify_push_dispatch_secret`. Il ne faut pas supprimer ce contrôle.

**Limite :** le déploiement de la version 8 ne crée pas le compte Firebase et ne renseigne pas `FCM_SERVICE_ACCOUNT_JSON`. La réception réelle sur téléphone n'est pas validée. Aucun message de test n'a été envoyé. Le retour à la normale de l'advisor Health doit être confirmé plus tard à partir des journaux, après configuration des secrets.

## 3. Remboursements : défaut métier à corriger séparément

La définition actuellement déployée de `public.complete_refund(uuid,text)` :

- verrouille le remboursement, le paiement et la commande ;
- calcule le total remboursé ;
- répartit le montant de remboursement entre **tous** les groupes vendeurs de la commande, au prorata de leurs sous-totaux ;
- écrit ensuite une entrée `REFUND` dans le ledger de chaque groupe concerné.

Ce modèle ne sait pas cibler un remboursement partiel portant sur un article, une quantité ou une boutique précise. Il peut donc débiter des vendeurs non concernés si le remboursement demandé ne porte pas sur toute la commande.

**Aucune modification SQL distante n'a été appliquée ici.** Avant de corriger, il faut définir et versionner une allocation par ligne d'article/groupe, prendre en compte quantités, frais, remises, commissions et remboursements précédents, puis ajouter des tests négatifs, d'idempotence et de concurrence. Le modèle de données de remboursement doit être inspecté avec tous ses appelants avant la migration ; une correction approximative du ledger serait dangereuse.

## 4. Migrations et base de données

L'historique distant contient davantage de versions que les anciens nombres inscrits dans certains documents. Le workflow DB exécute `supabase db reset`, qui exige un historique local complet et rejouable. Le problème de runner empêche de savoir si cette étape a réellement échoué sur les migrations dans les derniers runs concernés.

Ne pas modifier l'historique distant, ne pas marquer des migrations comme appliquées à l'aveugle et ne pas lancer de reset sur le projet actif. La baseline de reconstruction doit être réconciliée avec les versions distantes avant de réactiver la validation DB.

## 5. Actions réalisées et non réalisées

### Réalisées
- Lecture des journaux GitHub et Supabase disponibles.
- Identification du blocage d'attribution du runner GitHub.
- Identification du blocage de configuration FCM.
- Synchronisation de `dispatch-push-notifications` vers Supabase version 8.
- Mise à jour de `docs/push-notifications.md` avec l'état réel et les prérequis restants.

### Non réalisées volontairement
- Aucun workflow GitHub lancé ou relancé.
- Aucun test, build ou commande de migration lancé.
- Aucune modification des données métier ou des écritures comptables.
- Aucun secret créé, lu ou exposé.
- Aucun paiement, remboursement ou push réel déclenché.
- Aucun changement destructif sur Supabase.

## 6. Prochain ordre de correction

1. Renseigner le compte de service Firebase et les configurations natives réelles.
2. Vérifier plus tard les logs de la version 8 sans envoyer de notification de masse ; faire un unique test sur appareil dédié seulement avec autorisation.
3. Résoudre les restrictions d'exécution GitHub Actions depuis les paramètres du compte/dépôt.
4. Concevoir la table d'allocation des remboursements et la correction ledger dans une migration versionnée, sans l'appliquer en production avant revue.
5. Reconstituer la baseline des migrations et préparer une validation locale reproductible.
