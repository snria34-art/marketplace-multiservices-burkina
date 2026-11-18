# AUD-02 — Modèle sûr d'allocation des remboursements multi-boutiques

**Projet :** Marketplace Multiservices Burkina  
**Supabase :** `dzhhsoikzxibmngjzcch` — PostgreSQL 17.6 — `eu-west-1`  
**État au 7 novembre 2026 :** anomalie confirmée ; modèle métier et technique préparé ; aucune correction financière appliquée en production.  
**Suivi :** [RIA-25 — allocation des remboursements partiels](https://linear.app/faso/issue/RIA-25/bloquant-finance-corriger-lallocation-des-remboursements-partiels)

## 1. Décision de sécurité

**Ne pas modifier pour le moment** `public.complete_refund(uuid,text)`, `public.request_refund(uuid,numeric,text)`, `public.refunds`, `public.seller_ledger`, les écritures de commissions ou les soldes vendeurs.

La fonction actuelle peut débiter un vendeur qui ne fournit pas l'article remboursé. Elle ne dispose pas des informations nécessaires pour répartir un remboursement d'article/quantité et distinguer le montant payé par le client de la charge financière du vendeur.

La base hébergée ne contient actuellement aucune commande, ligne de commande, commande de paiement, écriture de remboursement ou écriture du ledger vendeur. Cela réduit le risque d'une future migration de données, mais ne dispense pas de tester le modèle complet sur une base isolée avant déploiement.

## 2. Constats vérifiés sur la base active

### 2.1 Le remboursement n'a pas de portée commerciale explicite

`public.refunds` contient actuellement :

- `id`, `payment_id`, `order_id`
- `amount`, `currency`, `reason`, `status`
- `provider_reference`, `created_at`, `completed_at`

Il n'existe aucun lien direct vers `order_group_id`, `order_item_id`, un retour ou une quantité.

`public.request_refund(order_id, amount, reason)` ne reçoit que la commande, le montant et le motif. La fonction sélectionne un paiement réussi ; elle ne reçoit pas la boutique, les lignes ou les quantités concernées.

### 2.2 Un retour client ne décrit pas les quantités

`public.returns` peut pointer vers un seul `order_item_id`, mais ne conserve pas la quantité demandée/acceptée et ne possède aucun lien vers `public.refunds`.

`public.open_return(order_id, order_item_id, reason)` ouvre le dossier, mais ne réserve pas une quantité et ne prépare pas d'allocation de remboursement. Une résolution `REPLACEMENT` ou `CREDIT` n'est pas nécessairement un remboursement monétaire.

### 2.3 L'allocation actuelle de `complete_refund` est incorrecte

La routine :

1. verrouille le remboursement, le paiement et la commande ;
2. marque le remboursement `COMPLETED` ;
3. met à jour les statuts du paiement/commande selon le cumul remboursé ;
4. divise le montant remboursé au prorata du subtotal de **tous** les groupes vendeurs ;
5. écrit une ligne `REFUND` négative dans le ledger de chaque groupe.

Exemple : commande A = 30 000 F, commande B = 70 000 F. Un remboursement de 10 000 F portant uniquement sur un article de A est réparti environ 3 000 F sur A et 7 000 F sur B. Le vendeur B supporte donc une partie du remboursement sans être concerné.

Le traitement final marque également tous les groupes `REFUNDED` lorsque le montant cumulé atteint le paiement total. À terme, le statut de chaque groupe devra dépendre des allocations réellement affectées à ce groupe, pas seulement du total payé au client.

### 2.4 Le modèle des ventes/commissions doit être normalisé

Deux fonctions existent dans la base :

- `finalize_seller_group(uuid,numeric)` : crédite `SALE` du montant brut du groupe et débite `COMMISSION` séparément.
- `finalize_seller_group_financials(uuid)` : crédite `SALE` du montant net et conserve la commission dans `commissions` avec le statut `PENDING`.

Ces deux conventions peuvent donner un solde net similaire, mais elles n'ont pas les mêmes écritures ni les mêmes statuts. Aucune référence interne SQL ni trigger appelant ces routines n'a été identifiée dans les contrôles effectués. Leur usage par les intégrations serveur doit être confirmé avant de choisir la convention de référence.

`reverse_seller_group(order_group_id, reason)` est une inversion complète de groupe : elle écrit `COMMISSION_REVERSAL` positif et `SALE_REVERSAL` négatif, puis marque la commission `REVERSED`. Cette fonction ne doit pas être utilisée pour un retour partiel d'un article ou d'une quantité.

### 2.5 Les remises ne sont pas ventilées au niveau des articles

Dans `checkout_cart` :

- les lignes et groupes conservent les prix/subtotaux bruts ;
- la remise est stockée uniquement dans `orders.discount_total` ;
- la remise n'est pas répartie en snapshots par article ou groupe ;
- le total payé correspond au subtotal + livraison - remise.

Le modèle ne permet donc pas de retrouver exactement, à partir d'un article retourné, le montant payé par le client après remise, ni la part de remise financée par la plateforme ou par le vendeur. Une ventilation déterministe doit être enregistrée au checkout, et non reconstruite au moment d'un remboursement.

## 3. Modèle cible recommandé

Le remboursement du prestataire et la répartition comptable interne doivent être deux objets distincts :

- `refunds` garde la demande et le montant **global** à rendre au client.
- `refund_allocations` conserve une ventilation **immuable** de ce montant.
- `return_items` conserve les produits et quantités concernés par un dossier de retour.
- Les écritures du ledger sont créées à partir des allocations validées, jamais par un prorata automatique sur tous les vendeurs.

### 3.1 Informations de tarification à figer au checkout

Pour chaque ligne de commande, enregistrer un snapshot financier comportant au minimum :

- prix brut unitaire et quantité ;
- montant brut de la ligne ;
- remise affectée à la ligne ;
- source de financement de la remise : vendeur, plateforme ou financement partagé ;
- montant net payé par le client pour la ligne ;
- base de commission contractuelle et taux de commission appliqué ;
- devise et règles d'arrondi.

L'allocation de la remise doit être déterministe au centime XOF, par exemple au prorata des lignes éligibles avec une méthode de plus grands restes ; le dernier résidu est attribué selon un ordre stable. Les sommes ventilées doivent égaler exactement `orders.discount_total`.

### 3.2 Dossier de retour et quantités

Conserver un dossier `returns` et une table enfant `return_items` :

- `return_id`
- `order_item_id`
- `requested_quantity`
- `approved_quantity`
- `received_quantity` lorsque le contrôle physique est terminé
- état et décision pour la ligne

Les quantités approuvées/reçues ne doivent jamais dépasser la quantité commandée moins les quantités déjà approuvées ou remboursées sur les autres dossiers. Le contrôle doit être transactionnel et verrouiller la ligne de commande pour empêcher deux retours concurrents sur le même stock.

Un dossier peut contenir plusieurs articles. Une résolution `REPLACEMENT` ou `CREDIT` ne crée pas automatiquement un remboursement monétaire.

### 3.3 Allocation monétaire immuable

Créer `refund_allocations` comme enfant de `refunds`, avec un enregistrement par ligne d'allocation. Champs recommandés :

| Champ | Rôle |
|---|---|
| `refund_id` | Remboursement externe concerné |
| `return_id` / `return_item_id` | Référence de retour, nullable pour un remboursement hors retour |
| `order_group_id` / `order_item_id` | Groupe vendeur et ligne concernée, nullable pour une charge plateforme seule |
| `allocation_type` | `ITEM`, `DELIVERY`, `PLATFORM_ADJUSTMENT` ou `ORDER_ADJUSTMENT` |
| `quantity` | Quantité remboursée pour une allocation article |
| `customer_amount` | Somme de cette allocation incluse dans le montant rendu au client |
| `seller_gross_debit` | Charge brute imputée au vendeur |
| `commission_reversal_amount` | Commission à reverser au vendeur |
| `platform_funded_amount` | Part financée par la plateforme |
| `currency`, `created_at`, `created_by` | Traçabilité et devise |

Les valeurs financières calculées sont enregistrées au moment de l'approbation et deviennent immuables lorsque le remboursement passe à `PROCESSING`. Une modification ultérieure doit créer une nouvelle correction auditée, et non réécrire l'allocation qui a déjà servi au prestataire.

### 3.4 Invariants financiers obligatoires

1. **Remboursement client :** somme de `refund_allocations.customer_amount` = `refunds.amount`, exactement, au centime.
2. **Propriété :** une allocation article doit pointer vers une ligne appartenant à la commande et au groupe vendeur indiqués.
3. **Quantités :** la somme des quantités allouées/remboursées ne dépasse jamais la quantité commandée.
4. **Isolation vendeur :** aucun vendeur/groupe non présent dans les allocations ne reçoit de débit.
5. **Ledger :** une allocation produit ses écritures une seule fois, avec une référence unique à `refund_allocation_id`.
6. **Commission :** la commission reversée ne peut pas dépasser la commission d'origine non encore reversée sur le groupe.
7. **Frais de livraison :** l'allocation livraison est une charge plateforme/courier selon une règle explicite ; elle ne doit pas être ajoutée arbitrairement au débit du vendeur.
8. **Idempotence :** une répétition de webhook ou de `complete_refund` ne crée aucune écriture supplémentaire.
9. **Concurrence :** les remboursements concurrents verrouillent le paiement et les lignes/groupes concernés ; le cumul demandé, en cours et terminé ne dépasse pas le montant payé et remboursable.
10. **Statuts :** un groupe ne devient `REFUNDED` que lorsque ses propres montants remboursables et quantités ont été totalement traités ; un remboursement total de commande ne doit pas être déduit du seul statut de paiement si les allocations racontent autre chose.

### 3.5 Convention de ledger et contre-passation de commission

Le dépôt contient deux conventions historiques, toutes deux prises en charge explicitement par la nouvelle procédure d'allocation, sans les mélanger :

- **Modèle brut `GROSS_LEDGER`** : `SALE = +base brute`, `COMMISSION = -commission`. Pour un retour partiel, le ledger reçoit `REFUND = -(seller_net_debit + commission_reversal_amount)` puis `COMMISSION_REVERSAL = +commission_reversal_amount`. L'impact vendeur net reste exactement `-seller_net_debit`. La commission `POSTED` ne passe à `REVERSED` qu'après contre-passation complète.
- **Modèle net `NET_SALE`** : `SALE = base brute - commission`, commission `PENDING`, aucune écriture `COMMISSION` séparée. Le ledger reçoit uniquement `REFUND = -seller_net_debit` ; il ne faut surtout pas ajouter de crédit `COMMISSION_REVERSAL`, car la commission a déjà été retenue dans le crédit de vente. La commission `PENDING` passe à `CANCELLED` uniquement lorsque la part correspondante est entièrement neutralisée.
- **Mode inconnu ou écritures incohérentes** : l'allocation est refusée. La procédure déduit le mode des écritures `SALE`/`COMMISSION` effectivement présentes et le conserve dans `refund_allocations.commission_accounting_mode`.

La commission n'est jamais modifiée au prorata dans ses champs `base_amount`, `rate` ou `commission_amount`. Les contre-passations partielles sont suivies par allocation ; le statut ne change qu'une fois le montant d'origine intégralement contre-passé et comptabilisé.

Ne pas appeler `reverse_seller_group` pour un retour partiel : cette routine annule toute la base de commission du groupe.

### 3.6 Contraintes réelles du registre et risque de conflit multi-boutiques

La contrainte unique active sur `public.seller_ledger` est un index :

```sql
CREATE UNIQUE INDEX uq_seller_ledger_ref_type
ON public.seller_ledger(seller_id, entry_type, reference_id);
```

La fonction actuelle `complete_refund` écrit une ligne `REFUND` par `order_group`, avec :
- le même `reference_id = refunds.id` ;
- le même `entry_type = 'REFUND'` ;
- le `seller_id` du groupe concerné.

Si un vendeur possède deux boutiques (ou deux groupes) dans la même commande, le remboursement d'une commande complète ou partielle peut produire deux écritures portant le même triplet `seller_id + REFUND + refund_id`. La seconde insertion viole `uq_seller_ledger_ref_type` et fait échouer la transaction de `complete_refund`.

Conséquence supplémentaire : la fonction Edge `execute-payment-refund` contacte Wave **avant** l'appel à `complete_refund`. Si Wave confirme le remboursement mais que l'écriture du ledger échoue ensuite sur cette unicité, l'Edge Function renvoie `refund_completion_failed` avec `refund_provider_confirmed=true`, tandis que la transaction SQL est annulée. Le remboursement fournisseur est alors réel mais la base locale peut laisser la demande en `PROCESSING`. La correction future doit traiter explicitement cette situation de rapprochement et ne jamais relancer aveuglément le remboursement fournisseur.

**Règle de conception pour les futures écritures :**
- chaque ligne comptable issue d'une allocation doit avoir une référence unique `refund_allocation_id`, et non le seul `refund_id`, si plusieurs lignes d'allocation sont créées pour un même vendeur ;
- l'agrégation vendeur/groupe doit être déterminée avant insertion ;
- l'écriture doit être idempotente par allocation et distinguer l'état du remboursement externe (Wave/CinetPay) de la comptabilisation interne ;
- un échec de comptabilisation après confirmation du prestataire doit déclencher un état de rapprochement/retry interne, pas un nouvel appel au prestataire.

Cette contrainte n'a pas été provoquée sur la production : il n'existe actuellement aucune commande, aucun remboursement et aucune écriture de ledger.

### 3.7 Appelants réellement observés

Vérifications de catalogue et recherche de code le 7 novembre 2026 :
- aucune fonction SQL applicative ni aucun trigger ne référence `finalize_seller_group`, `finalize_seller_group_financials` ou `reverse_seller_group` ;
- aucun job `pg_cron` du projet n'appelle ces routines ou n'écrit dans `seller_ledger` ;
- la recherche de code dans la branche `main` ne trouve leurs références que dans les migrations qui les définissent, les runbooks et le rapport d'audit, pas dans les sources Flutter/Edge Function.

Cela ne prouve pas qu'aucun appel externe hors dépôt n'existe, mais l'intégration de finalisation des ventes ne peut pas encore être attribuée avec certitude à l'une des deux conventions. Il faut la tracer dans le service serveur qui orchestrera le passage à `DELIVERED` avant de choisir le ledger canonique.

### 3.8 Portée actuelle de la demande côté client

L'écran `OrderDetailsPage` permet au client de saisir uniquement un montant XOF et un motif ; il appelle `request_refund(order_id, amount, reason)`. Il ne propose pas de choisir une boutique, un article ou une quantité. La demande client actuelle est donc un montant global sur une commande, et toute possibilité de remboursement ciblé par article doit être conçue de bout en bout (écran, RPC, retour, allocations, validation admin et appel prestataire).

### 3.9 Capture de paiement après annulation : débits vendeur sans vente créditée

Le traitement de paiement et celui du remboursement créent un autre défaut de cohérence :

1. `public.process_payment_event(...)` détecte que la commande est déjà `CANCELLED` au moment où le fournisseur confirme le paiement.
2. Il crée une demande `refunds.status = 'REQUESTED'` pour le montant restant à restituer au client, sans réactiver la commande, les colis ou le stock.
3. Ce chemin ne crédite aucun `SALE` et ne crée aucune commission vendeur : la commande avait été annulée avant la capture confirmée.
4. Plus tard, `complete_refund` marque le remboursement terminé, mais ne vérifie pas que le groupe a reçu une écriture `SALE`. Il parcourt quand même tous les `order_groups` et écrit une ligne `REFUND` négative au vendeur.
5. Quand le remboursement atteint le montant payé, `complete_refund` n'inclut pas l'état parent `CANCELLED` dans sa liste de statuts de commande à passer à `REFUNDED`, mais met à jour tous les groupes en `REFUNDED`. La commande peut donc rester `CANCELLED` avec des groupes `REFUNDED`.

**Conséquence :** le client reçoit le remboursement, mais un ou plusieurs vendeurs peuvent être débités alors qu'aucune vente n'a jamais été créditée. Les groupes changent également de statut indépendamment de la commande annulée.

**Règle attendue :** pour une capture fournisseur arrivée après annulation d'une commande impayée, le remboursement intégral du client doit être traité sans débit du ledger vendeur. Les groupes/commande restent cohérents avec l'annulation initiale ; le rapprochement du montant capturé et restitué appartient au compte de paiement/plateforme, sauf écriture vendeur d'origine explicitement démontrée. Ne pas déduire l'existence d'une créance vendeur de la simple présence d'un `order_group`.

Cette règle doit être testée avec un paiement fournisseur simulé et une commande factice en staging avant modification de `complete_refund`.

### 3.6 Coupons, livraison et financement plateforme — décision métier requise

Les règles suivantes doivent être écrites avant d'implémenter le calcul :

- Un coupon financé par la plateforme réduit le montant payé par le client, mais ne réduit pas automatiquement la recette contractuelle du vendeur.
- Un coupon financé par le vendeur réduit la base vendeur selon le contrat ; le calcul de commission doit utiliser la base spécifiée par le contrat.
- Un coupon cofinancé doit conserver la ventilation de chaque financeur.
- Les frais de livraison ne sont pas une vente produit. Un remboursement de livraison doit avoir sa propre allocation et son propre bénéficiaire financier.
- Les gestes commerciaux, remboursements de frais, taxes éventuelles et remboursements hors retour doivent être des allocations distinctes, non ventilées arbitrairement entre boutiques.

Les règles ci-dessus constituent le modèle de contrôle recommandé ; les pourcentages et la responsabilité finale de chaque remise doivent être validés par le propriétaire du marketplace et la règle commerciale/fiscale retenue.

## 4. Séquence d'exécution cible

1. Le client demande un retour sur une ou plusieurs lignes et quantités.
2. Le serveur vérifie la propriété de la commande, les fenêtres de retour, la quantité restante et l'absence de demande concurrente.
3. L'administrateur accepte/rejette les quantités et la résolution.
4. Avant l'appel au prestataire, le serveur calcule et fige les allocations client, vendeur, commission, plateforme et livraison.
5. Il vérifie toutes les sommes, les limites de paiement et les soldes/obligations vendeur.
6. `admin_begin_refund` passe le dossier à `PROCESSING` une seule fois ; la fonction Edge contacte le prestataire.
7. À confirmation du prestataire, `complete_refund` verrouille le remboursement, puis le paiement, valide l'allocation gelée et écrit les journaux du ledger avec une référence unique par allocation.
8. Les statuts du paiement, de la commande, du groupe et du retour sont calculés à partir des allocations réellement terminées.
9. Les retries/webhooks relisent l'état déjà finalisé et ne créent aucun doublon.

Le chemin de paiement réussi après annulation (`process_payment_event`) doit rester distinct : il crée une demande de remboursement pour la capture tardive. Dans ce cas, s'il n'existe aucune vente/commission portée au ledger vendeur pour les groupes concernés, le remboursement client ne doit pas générer un débit vendeur artificiel.

## 5. Tests transactionnels à ajouter avant toute migration financière

- Commande multi-vendeurs A/B : remboursement d'un seul article A ; aucune écriture chez B.
- Deux boutiques détenues par le même vendeur : chaque groupe reçoit uniquement sa part ; le vendeur reste traçable au niveau groupe.
- Retour de 1 unité sur une ligne de quantité 3 ; une deuxième demande concurrente ne peut pas rembourser la même unité.
- Remboursements partiels successifs du même article ; les quantités et montants cumulés sont plafonnés.
- Retour complet d'un groupe : inversion exacte de vente et commission, une seule fois.
- Retour partiel : débit vendeur et reversement de commission partiels sans marquer toute la commission `REVERSED`.
- Coupon plateforme, coupon vendeur et coupon cofinancé ; sommes d'allocation identiques au snapshot checkout.
- Remboursement des frais de livraison seul ; aucune boutique n'est débitée.
- Arrondis XOF et allocation du résidu ; la somme finale égale exactement le montant externe.
- Paiement capturé tardivement après annulation ; remboursement complet sans débit d'un seller ledger non crédité.
- Même scénario, puis relecture des statuts : la commande et ses groupes ne doivent pas diverger (commande et groupes restent CANCELLED, sans mutation vers REFUNDED en l'absence d'une vente réglée).
- Un vendeur possédant deux boutiques dans une commande ; un seul remboursement doit pouvoir produire des écritures ledger idempotentes sans violer uq_seller_ledger_ref_type.
- Wave confirme le remboursement puis l'écriture ledger échoue ; le mécanisme de rapprochement doit reprendre la comptabilisation interne sans rappeler le endpoint refund de Wave.
- Réponse prestataire répétée, webhook rejoué, fonction appelée à nouveau après `COMPLETED` ; une seule écriture par allocation.
- Vendeur déjà payé : la règle de créance/recouvrement doit être testée, sans rendre son solde silencieusement négatif.

## 6. Contrôles de déploiement

Avant d'appliquer une migration :

- normaliser les deux routines de finalisation vendeur vers une convention unique ;
- confirmer quelle routine est appelée par le backend de paiement/livraison réellement déployé ;
- ajouter et valider les snapshots de prix/remise au checkout ;
- tester la nouvelle structure sur une base isolée reconstruite avec un jeu de données de test ;
- exécuter pgTAP et les tests Edge de webhook avec un faux prestataire ;
- vérifier les ACL `service_role`/admin, les verrous, les contraintes uniques et l'absence d'exposition Data API ;
- faire une revue comptable des écritures attendues avant migration de production.

## 7. État de réalisation

- Diagnostic SQL et schéma : terminé.
- Cause du prorata global de `complete_refund` : confirmée.
- Absence de quantité et lien retour/remboursement : confirmée.
- Absence de ventilation des remises par ligne : confirmée.
- Deux conventions de ledger présentes : confirmées.
- Proposition de schéma et invariants : documentés dans ce runbook.
- **Mesure de sécurité ajoutée :** la finalisation fournisseur ne débite plus les vendeurs au prorata. Un rapprochement privé `PENDING_ALLOCATION` est créé pour chaque remboursement ; les retraits des vendeurs impliqués et un second remboursement sur le même paiement restent bloqués jusqu'à la ventilation vérifiée. Les montants exacts par article/quantité, remise, livraison et commission restent à définir et à approuver avant de lever ce gel.
- **Soldes, remboursements et paiements : aucune donnée touchée.**
- Validation finale de la règle de financement des coupons, des frais de livraison et de la commission : encore nécessaire.

## Addendum — contrôle de la mitigation financière (16 novembre 2026)

La branche de maintenance contient la migration `20261115191336_phase1_commerce_integrity_final.sql`.

- Elle crée `private.refund_accounting_reconciliations`, dans un schéma privé avec RLS et sans accès direct aux rôles clients.
- Le trigger `trg_sync_refund_accounting_hold` place les remboursements non rejetés/annulés en `PENDING_ALLOCATION`.
- `public.complete_refund` ne répartit plus de débit arbitraire dans `seller_ledger` : il confirme l'état du remboursement et du paiement, tout en laissant le rapprochement vendeur en attente.
- Les retraits des vendeurs concernés restent bloqués. Un nouveau traitement fournisseur sur le même paiement est bloqué lorsqu'une tentative antérieure est déjà en cours, échouée ou terminée et demeure en `PENDING_ALLOCATION`.
- Les remboursements rejetés/annulés passent en `RECONCILED`; aucun mécanisme de libération manuelle d'une allocation financière non approuvée ne doit être ajouté.

### Validation et portée

Le workflow local Supabase Database Tests [run 43754031145](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43754031145), sur le commit `e0eac2cf7e15019b5cfa95304cffc6f209fe1875`, a réussi : reconstruction locale depuis les migrations puis exécution pgTAP, journal final « All tests successful ». La migration et le test `phase1_commerce_integrity_test.sql` étaient déjà présents sur ce commit. Le workflow a toutefois été ajusté depuis ; sa dernière définition n'a pas encore son propre run.

**Limite impérative :** cette validation est locale/CI. Elle ne prouve pas que la migration est appliquée à la base Supabase hébergée. La connexion Supabase ne retourne aucun projet accessible dans cette session. Aucun changement distant n'a été exécuté.

Le gel reste nécessaire jusqu'à l'approbation des règles d'allocation par article/quantité, vendeur, commission, coupons et livraison, puis jusqu'à la conception et aux tests d'une procédure d'allocation immuable.


## Addendum complémentaire — distinction entre mitigation des remboursements et finalisation des ventes (16 novembre 2026)

Les descriptions des anciennes sections 3.6 et 3.9 décrivent le comportement historique de `complete_refund` avant la migration `20261115191336_phase1_commerce_integrity_final.sql`. Elles ne décrivent plus la fonction actuellement définie sur la branche de maintenance :

- `complete_refund` ne parcourt plus les groupes pour y écrire des lignes `REFUND` dans `seller_ledger` ;
- la table privée `refund_accounting_reconciliations` et son trigger gardent les vendeurs concernés en `PENDING_ALLOCATION` ;
- `request_seller_payout_secure` bloque les retraits des vendeurs concernés tant que le rapprochement est en attente ;
- `admin_begin_refund` bloque une nouvelle tentative fournisseur sur le même paiement tant qu'un remboursement antérieur doit encore être ventilé.

Ainsi, le risque de double écriture/refund décrit dans les sections historiques est mitigé par le gel comptable : il ne faut pas le présenter comme une écriture effectuée par la version actuelle de `complete_refund`. La contrainte unique de `seller_ledger` reste néanmoins à prendre en compte lors de la conception future des allocations.

### Point encore ouvert : créditer les ventes livrées

La vérification du 16 novembre 2026 a aussi confirmé que `20261115191336_phase1_commerce_integrity_final.sql` ne contient aucun appel à `finalize_seller_group` ou `finalize_seller_group_financials`. La fonction `sync_after_package_delivery` synchronise l'affectation de livraison et le statut parent ; elle ne crée pas les écritures de vente/commission.

Les deux fonctions de finalisation ont des conventions incompatibles :
- `finalize_seller_group` enregistre une vente brute, puis une commission négative distincte ;
- `finalize_seller_group_financials` enregistre directement une vente nette et conserve la commission dans un état séparé.

Aucun appelant versionné dans les sources applicatives récentes n'a été identifié pendant l'audit. Un orchestrateur externe reste possible et doit être vérifié. Tant que ce point n'est pas établi et qu'une convention n'est pas choisie, ne pas ajouter un appel automatique ni supposer qu'un groupe `DELIVERED` a déjà crédité le solde vendeur.


### Addendum — absence de commande admin pour lever le gel (16 novembre 2026)

La relecture de `AdminRefundsPage` et des fonctions SQL montre que l'interface admin peut consulter `accounting_status`/`accounting_note`, approuver/refuser un remboursement et faire confirmer une opération fournisseur. Elle ne peut pas créer d'allocation ni valider le rapprochement comptable privé. Le trigger passe automatiquement à `RECONCILED` lorsqu'une demande devient `REJECTED` ou `CANCELLED`, mais une demande `COMPLETED` reste `PENDING_ALLOCATION` en l'absence de procédure distincte.

En conséquence, les retraits des vendeurs associés restent bloqués après un remboursement exécuté tant que le rapprochement n'est pas résolu par un mécanisme serveur privilégié. Cette limitation doit être traitée comme un blocage opérationnel à planifier, pas comme une raison de supprimer le gel ou d'autoriser une modification directe de la table privée.

L'action « Exécuter » de l'écran admin a été limitée à `WAVE` + `APPROVED` : `admin_begin_refund` n'accepte pas `FAILED`/`PROCESSING` et CinetPay nécessite sa confirmation manuelle. Les résultats fournisseur ambigus ne doivent jamais être relancés automatiquement.


### Contrat d'allocation et contre-passation de commission (AUD-02)

La RPC `set_refund_allocations(refund_id, allocations)` accepte un remboursement `APPROVED`, `PROCESSING` ou `COMPLETED`. Le flux normal doit figer l'allocation après approbation et avant l'appel prestataire ; `PROCESSING`/`COMPLETED` servent uniquement à raccorder une tentative déjà engagée ou confirmée.

Pour chaque ligne article, les montants XOF entiers respectent :

`customer_amount = seller_net_debit + commission_reversal_amount + platform_funded_amount`

La procédure détecte la convention historique depuis les écritures réelles du groupe et la fige dans `commission_accounting_mode` :

- **`GROSS_LEDGER`** : `SALE` brut et `COMMISSION` négative séparée. Pour un remboursement client de 1 000 XOF avec débit vendeur net approuvé de 900 XOF et contre-passation de commission de 100 XOF, le ledger reçoit `REFUND -1 000` puis `COMMISSION_REVERSAL +100`. L'impact vendeur net est exactement -900 XOF.
- **`NET_SALE`** : le `SALE` crédité est déjà net et la commission est `PENDING`, sans écriture `COMMISSION` négative. Avec les mêmes montants, le ledger reçoit seulement `REFUND -900` ; la commission déjà retenue n'est jamais recréditée au vendeur. Sa part de 100 XOF est neutralisée côté commission/plateforme, pas par un crédit vendeur.
- Si les écritures ne correspondent sans ambiguïté à aucun de ces modèles, l'allocation est refusée. Aucun mode ne peut être choisi arbitrairement par le client ou l'interface.

Les écritures du ledger utilisent `refund_allocation.id` comme référence unique. La commission reste dans son statut d'origine pendant les contre-passations partielles. Quand le cumul des allocations effectivement comptabilisées (`ledger_posted_at` renseigné) atteint `commission_amount`, la commission `POSTED` passe à `REVERSED`, tandis qu'une commission `PENDING` passe à `CANCELLED`. La procédure ne modifie jamais `base_amount`, `rate` ou `commission_amount`.

**Limite d'intégration :** l'écran admin et l'Edge Function doivent encore appeler l'allocation avant l'exécution fournisseur dans le flux normal. Tant que cette intégration n'est pas réalisée, le gel comptable reste actif et les retraits ne doivent pas être libérés.

### Addendum — intégration du flux d'exécution (18 novembre 2026)

La migration `20261118194500_aud02_refund_execution_gate.sql` relie désormais le contrôle d'allocation au déclenchement fournisseur :

- `get_refund_allocation_candidates` expose à l'administrateur les UUID des articles, groupes, vendeurs, quantités commandées et totaux de ligne ; aucune donnée n'est accessible anonymement.
- `get_refund_allocation_status` permet à l'écran de vérifier si une allocation complète existe déjà.
- `AdminRefundsPage` affiche les candidats et demande le JSON de ventilation approuvé avant l'exécution Wave ou la confirmation CinetPay. Les montants ne sont jamais calculés ou ventilés automatiquement par l'interface.
- `admin_begin_refund` exige maintenant le statut `APPROVED` et une allocation dont la somme `customer_amount` égale exactement le montant du remboursement. Une demande sans allocation est refusée avant la transition vers `PROCESSING`.
- Après confirmation Wave, l'Edge Function appelle `complete_refund`, puis `reconcile_refund_accounting` avec la session administrateur. Si le second appel échoue, la réponse signale que le prestataire a déjà confirmé : aucun nouvel appel Wave n'est lancé. L'écran permet ensuite de reprendre uniquement le rapprochement interne lorsque le remboursement est `COMPLETED` mais encore `PENDING_ALLOCATION`.
- `admin_complete_manual_refund` exige la même allocation et exécute la confirmation locale et le rapprochement dans une transaction SQL.
- Pour un résultat Wave ambigu resté `PROCESSING`, l'écran propose une confirmation manuelle de la référence réellement visible dans le tableau de bord Wave via `record_provider_refund_confirmation`, puis reprend le rapprochement. Cette action ne contacte jamais Wave.

Le JSON saisi par l'administrateur doit reprendre les UUID affichés dans la fenêtre et contenir, pour chaque ligne `ITEM`, `quantity`, `customer_amount`, `seller_net_debit`, `commission_reversal_amount` et `platform_funded_amount`. Les montants sont en XOF entiers et leur somme par ligne doit être équilibrée. Une ligne `PLATFORM_ADJUSTMENT` ne peut être financée que par la plateforme. Toute ambiguïté de commission, quantité excessive, double allocation ou somme incorrecte est rejetée par la RPC.

**Limites restantes :** le système ne calcule pas automatiquement la ventilation contractuelle des coupons, frais de livraison ou retours partiels ; la comptabilité doit fournir et approuver ces montants. Le client ne choisit toujours pas des articles/quantités au moment de créer sa demande. Les remboursements Wave partiels restent refusés par le contrôle existant. Les migrations et tests ajoutés n'ont pas été exécutés sur PostgreSQL isolé dans cette session ; aucune base distante ni aucun prestataire n'a été contacté.

### Addendum — suppression du débit historique automatique (18 novembre 2026)

La migration `20261118203000_aud02_remove_legacy_refund_ledger_debit.sql` remplace `complete_refund(uuid,text)` : elle confirme le remboursement et met à jour les statuts paiement/commande, mais ne crée plus aucune écriture `seller_ledger`. Les écritures vendeurs sont exclusivement produites par `reconcile_refund_accounting` à partir de `refund_allocations` immuables et approuvées. Le droit d'exécution de `complete_refund` reste réservé à `service_role`.

Protection de l'historique : si une ancienne version de `complete_refund` a déjà créé une écriture `REFUND` portant le même `reference_id`, le rapprochement refuse de republier une écriture et renvoie `refund_legacy_ledger_entries_present`. Ces dossiers historiques doivent être examinés manuellement avant toute reprise ; ne pas supprimer ni compenser automatiquement leurs écritures.
