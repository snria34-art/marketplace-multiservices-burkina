# Paiements réels

## Architecture

- Flutter ne contient aucune clé opérateur.
- Le checkout est créé côté Supabase Edge Functions avec un JWT utilisateur.
- Flutter ouvre le lien de paiement dans le navigateur externe.
- Wave utilise son Checkout API et un webhook signé HMAC.
- Orange Money et Moov Money au Burkina sont proposés via CinetPay Collect.
- CinetPay reçoit une notification x-www-form-urlencoded signée par x-token, puis le serveur vérifie toujours la transaction via l'API de vérification.
- Une notification CinetPay `WAITING_FOR_CUSTOMER` reste en `PROCESSING`.
- Un événement Wave `checkout.session.payment_failed` reste en `PROCESSING` : Wave précise qu'une même session peut recevoir plusieurs échecs avant une réussite. Cela évite d'annuler prématurément la commande et de libérer son stock entre deux tentatives.
- Les événements de paiement sont traités par un RPC idempotent qui valide le montant et la devise avant de modifier la commande.

## Fonctions Edge actives

### Création

- create-wave-payment-session-v3
- create-cinetpay-payment-session-v3

Ces deux fonctions exigent un JWT valide.

### Webhooks

- wave-payment-webhook-v3
- cinetpay-webhook-v3

Ces deux fonctions sont publiques au niveau HTTP pour accepter les callbacks fournisseur et valident leur signature avant tout traitement.

### Autres

- payment-return
- execute-payment-refund

execute-payment-refund exige un JWT et vérifie l'autorisation administrateur avant toute exécution.

## Secrets

Les clés suivantes doivent être configurées dans les secrets des Edge Functions Supabase, jamais dans Flutter ni dans Git.

### Wave

- WAVE_API_KEY
- WAVE_WEBHOOK_SECRET
- WAVE_SIGNING_SECRET si la signature des requêtes sortantes est activée
- WAVE_SUCCESS_URL et WAVE_ERROR_URL sont optionnels

Webhook à enregistrer dans le compte marchand Wave :

https://dzhhsoikzxibmngjzcch.supabase.co/functions/v1/wave-payment-webhook-v3

Sans WAVE_SUCCESS_URL/WAVE_ERROR_URL, le code utilise automatiquement payment-return et ajoute la référence de commande.

### CinetPay

- CINETPAY_API_KEY
- CINETPAY_SITE_ID
- CINETPAY_SECRET_KEY
- CINETPAY_RETURN_URL est optionnel

Notification à enregistrer dans le compte marchand CinetPay :

https://dzhhsoikzxibmngjzcch.supabase.co/functions/v1/cinetpay-webhook-v3

Le code utilise MOBILE_MONEY comme univers de paiement afin de proposer les opérateurs mobile money disponibles sur le guichet.

## Montants

Tous les montants envoyés à CinetPay sont en XOF. Le montant est un entier positif et doit être un multiple de 5. Le code refuse le checkout si cette règle n'est pas respectée; il ne modifie jamais silencieusement le total de la commande.

## Précontrôle du moyen de paiement avant commande

Avant de créer la commande ou de réserver le stock, l'application appelle l'Edge Function authentifiée `check-payment-provider-config` (v1, `verify_jwt=true`). Elle retourne uniquement le statut configuré/non configuré :
- Wave : API key + secret webhook présents ;
- CinetPay : API key + site ID + secret webhook présents.

Si les secrets nécessaires sont absents, l'application bloque le checkout avant `checkout_cart`. Cette vérification n'expose aucun secret et ne garantit pas l'activation du compte marchand : un test sandbox et une vérification des webhooks restent obligatoires.

## Remboursements

- Le client peut demander un remboursement partiel ou total depuis une commande livrée.
- Le cumul des demandes actives et terminées ne peut pas dépasser le montant réellement payé.
- Une demande passe par REQUESTED puis une validation admin.
- Pour Wave, execute-payment-refund appelle le endpoint officiel de remboursement de la session Checkout et ne marque le remboursement local comme terminé qu'après réponse fournisseur.
- Pour CinetPay, le checkout public actuel ne fournit pas un endpoint de remboursement direct documenté comparable à Wave. L'application conserve donc la demande dans le workflow admin et permet de confirmer manuellement le remboursement après exécution par le canal CinetPay prévu par le contrat.
- Un remboursement terminé met à jour le paiement en PARTIALLY_REFUNDED ou REFUNDED. **Attention :** la version actuellement déployée de `complete_refund` répartit encore le débit du ledger au prorata de tous les groupes de la commande ; ce comportement n'est pas une règle comptable approuvée et peut débiter des vendeurs non concernés. Voir `docs/runbooks/aud-02-refund-allocation.md`. Ne pas considérer l'allocation des remboursements partiels comme prête pour la production.

### Gestion des résultats ambigus du remboursement Wave — 15 novembre 2026

- Les erreurs de mise à jour du statut Supabase après un remboursement manuel, une configuration Wave absente ou une réponse Wave négative sont maintenant remontées explicitement ; l'Edge Function ne prétend plus que le statut a été enregistré lorsque l'écriture DB a échoué.
- Si la connexion échoue pendant l'appel de remboursement Wave, le résultat fournisseur est considéré comme **inconnu**. La demande reste en `PROCESSING` afin d'empêcher une nouvelle soumission aveugle ; une réconciliation avec le tableau de bord Wave est nécessaire avant toute nouvelle action.
- Cette correction réduit le risque de double remboursement mais ne résout pas l'allocation comptable multi-vendeurs documentée dans `docs/runbooks/aud-02-refund-allocation.md`. Les remboursements restent un parcours non certifié jusqu'à la correction et aux tests isolés du ledger.

## Activation production

Le code d'intégration est en place, mais les comptes marchands/KYC, clés API, secrets de signature et URLs webhook doivent être fournis par les comptes fournisseur avant tout paiement réel.

Aucun secret réel ne doit être commit dans le dépôt.

## Revue de code — 5 novembre 2026

Les fonctions de création de session v3 ont été corrigées : les URL de retour Wave et CinetPay sont maintenant construites après validation de l'identifiant de commande. Le webhook déclaré lors de la création de session CinetPay pointe vers `cinetpay-webhook-v3`, et non vers l'ancienne version. Une branche GET dupliquée a été supprimée dans le webhook v3.

La CI Supabase vérifie maintenant aussi le typage des fonctions Edge avec `deno check`. Ce contrôle doit réussir avant de considérer les correctifs de paiement comme validés. Les webhooks doivent ensuite être testés avec des notifications simulées signées et des réponses fournisseur simulées. Aucun paiement réel ne doit être utilisé pour ces tests.

Statut : code corrigé et commité ; validation Deno et tests de webhook en attente de la CI. Les secrets et comptes marchands réels ne sont pas configurés ici.
### Sécurité des callbacks et état des échecs — correction complémentaire

- Les fonctions `wave-payment-webhook-v3`, `cinetpay-webhook-v3` et `payment-return` ont `verify_jwt = false` dans `supabase/config.toml`, car les fournisseurs et navigateurs ne disposent pas d'un JWT Supabase.
- Les webhooks vérifient leurs propres signatures/secrets dans le code avant toute mutation. La désactivation du contrôle JWT à la passerelle n'enlève donc pas le contrôle d'authenticité métier ; les callbacks non signés sont rejetés.
- Les événements Wave `checkout.session.payment_failed` sont maintenant transmis comme `FAILED` et non `PROCESSING`, afin de suivre la machine d'état SQL.
- Le contrôle Deno des fonctions Edge a réussi dans la CI du commit `7c3739f1d3`. Les tests SQL Supabase et les tests Flutter ont également réussi sur ce commit ; les builds Android/iOS sont encore en cours.

### Limite Wave Checkout pour les remboursements partiels — 15 novembre 2026

- L'endpoint Wave `POST /v1/checkout/sessions/:id/refund` rembourse le paiement associé à la session Checkout dans son intégralité ; il ne prend aucun paramètre de montant.
- L'Edge Function vérifie désormais le montant et la devise du paiement local avant tout appel Wave. Si le montant demandé ne correspond pas exactement au paiement XOF capturé, elle remet la demande à `APPROVED`, n'appelle pas Wave et exige un traitement manuel.
- Cette garde évite qu'une demande locale partielle déclenche un remboursement intégral chez Wave. Elle ne fournit pas de remboursement partiel Wave : il faut confirmer le canal contractuel alternatif avec le marchand.
- Le corps brut des erreurs Wave n'est pas enregistré dans `refunds.reason`, car ce champ est également retourné au client par `get_customer_refunds` ; seul le code HTTP est conservé.
- Le contrôle statique Deno/CI doit encore confirmer cette modification. Aucun remboursement réel ni appel fournisseur n'a été effectué.
