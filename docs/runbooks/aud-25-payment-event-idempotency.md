# AUD-25 — Idempotence des événements Wave/CinetPay

**Date du constat :** 15 novembre 2026  
**Branche :** `maintenance/audit-01-07-2026-11-15`  
**Sévérité :** P1 — callbacks paiement pouvant se succéder sur une même session  
**Statut :** migration versionnée `20261115184115_phase1_commerce_integrity.sql` ; validations SQL/Edge déclenchées sur le nouveau commit, aucune base hébergée modifiée.

## 1. Constat SQL

La migration `20260921084442_v53_payment_intent_and_webhook_guard.sql` crée l'index unique :

```sql
create unique index if not exists uq_payment_events_provider_ref
on public.payment_events(provider_reference)
where provider_reference is not null;
```

La migration `20260921080918_v10_financial_integrity_guards.sql` crée aussi :

```sql
create unique index if not exists ux_payment_events_idempotency
on public.payment_events(payment_id,event_type,coalesce(provider_reference,''));
```

La version actuelle de `public.process_payment_event(...)` (migration `20260921224846_v137_payment_event_state_machine_hardening.sql`, puis révisions ultérieures) reçoit le même `p_provider_reference` que le paiement externe et insère un événement dans `payment_events`. Son contrôle de doublon vérifie le triplet paiement + type + référence, mais ne supprime pas l'index global unique sur `provider_reference`.

Les fonctions Edge v3 transmettent actuellement :
- Wave : l'identifiant de session Checkout (`data.id`) comme `p_provider_reference` ;
- CinetPay : l'identifiant de transaction (`cpm_trans_id`) comme `p_provider_reference`.

Or plusieurs événements distincts peuvent concerner la même référence externe :
- Wave peut envoyer plusieurs `checkout.session.payment_failed` avant `checkout.session.completed` ;
- CinetPay peut notifier un état d'attente puis un état final pour le même identifiant de transaction.

Le premier événement peut donc enregistrer la référence ; un événement ultérieur distinct avec cette même référence rencontre potentiellement l'index unique global et échoue, même si son type d'événement est différent. Pour Wave, cela risque notamment de bloquer l'enregistrement de la réussite après une tentative échouée. Le contrôle d'idempotence dans la fonction ne neutralise pas cet index : il a une portée plus fine que la contrainte globale.

## 2. Correction proposée

Ne pas contourner le problème en envoyant arbitrairement l'identifiant d'événement comme `p_provider_reference` : cette valeur pourrait remplacer la véritable référence Checkout/transaction dans `public.payments`, utilisée ensuite pour le rapprochement et les remboursements.

Le modèle cible doit séparer explicitement :

1. **Référence fournisseur stable** : session Wave ou transaction CinetPay, conservée dans `payments.provider_reference`.
2. **Identifiant d'événement/idempotence** : identifiant Wave `event.id` ; pour CinetPay, empreinte cryptographique déterministe de la notification signée reçue (corps brut), puisque le callback form-url-encoded ne fournit pas le même identifiant d'événement.
3. **Type d'événement métier** : `checkout.session.payment_failed`, `checkout.session.completed`, `cinetpay.waiting_for_customer`, `cinetpay.accepted`, etc.

Créer une nouvelle migration au moyen de la Supabase CLI, sans réécrire les migrations historiques. Elle devra :
- ajouter une colonne d'identité d'événement dédiée à `payment_events` ;
- remplacer l'unicité globale sur `provider_reference` par un index non unique adapté à la recherche ;
- ajouter une contrainte unique sur `(payment_id, provider_event_id)` ou une clé équivalente et stable ;
- adapter le processeur d'événements avec un paramètre distinct pour la référence de paiement et la clé d'idempotence de l'événement ;
- préserver la référence Wave/CinetPay dans `payments.provider_reference` ;
- traiter un rejeu du même événement comme un succès idempotent, mais permettre plusieurs événements distincts pour la même session/transaction ;
- garder les verrous de paiement/commande et l'ordre des transitions d'état.

## 3. Tests requis sur une base locale isolée

1. Wave : deux événements `payment_failed` distincts pour une même session sont stockés une fois chacun ; le rejeu du même `event.id` ne crée aucune nouvelle ligne.
2. Wave : un `payment_failed` suivi de `checkout.session.completed` sur la même session permet la transition vers `SUCCEEDED`.
3. Wave : un échec tardif après la réussite ne rétrograde jamais le paiement ni la commande.
4. CinetPay : une notification `WAITING_FOR_CUSTOMER` suivie d'une notification `ACCEPTED` pour le même `cpm_trans_id` permet la transition finale.
5. CinetPay : le rejeu exact du même corps signé reste idempotent.
6. La référence fournisseur dans `payments.provider_reference` reste toujours la session/transaction attendue pour les remboursements.
7. Les tentatives de deux paiements différents ne peuvent jamais partager une même identité d'événement.

Rejouer `supabase db reset --local`, `supabase test db --local` et les tests Edge avant de discuter d'une application distante.

## 4. Mitigation temporaire appliquée dans les webhooks

Les fonctions `wave-payment-webhook-v3` et `cinetpay-webhook-v3` ne transmettent plus les notifications `PROCESSING` au RPC financier. Elles répondent HTTP 200 après authentification/vérification fournisseur, sans consommer l'index unique `payment_events.provider_reference`.

Les statuts terminaux sont traités par le RPC avec `p_provider_reference = NULL`. La référence stable fournisseur est conservée dans `payments.provider_reference` (écrite lors de `prepare_payment_processing`) et recopiée dans `payment_events.payload.gateway_reference`. Une recherche préalable par paiement/type/référence NULL protège les replays ; après une erreur d'insertion, le webhook vérifie si un appel concurrent a déjà écrit la ligne et renvoie HTTP 200 si c'est le cas. Wave conserve aussi `event.id` dans le payload.

Cette mesure supprime le conflit sur les séquences normales :
- Wave : `payment_failed` (non terminal) puis `checkout.session.completed` ;
- CinetPay : `WAITING_FOR_CUSTOMER` (non terminal) puis `ACCEPTED` ou `REFUSED`.

Elle ne conserve pas l'historique détaillé de chaque tentative intermédiaire. Le modèle cible (identifiant d'événement distinct de la référence de paiement) reste nécessaire pour une traçabilité complète et pour gérer d'éventuels états terminaux contradictoires.

## 5. Références de contrat fournisseur

- Wave documente explicitement que plusieurs événements `checkout.session.payment_failed` peuvent précéder une réussite et que l'identifiant d'événement `id` est unique : [Wave — Webhooks / Checkout Events](https://docs.wave.com/webhook).
- La documentation CinetPay indique que l'URL de notification peut être appelée à chaque mise à jour de l'état : [CinetPay Support — intégration PayIn](https://support.cinetpay.com/d/81-comment-integrer-lapi-de-paiement-payin).

## 6. Correction versionnée

La migration ajoute `payment_events.provider_event_id`, retire l'unicité globale sur `provider_reference` et la remplace par une unicité sur l'identité d'événement. La référence stable de transaction est conservée dans `payment_events.provider_reference` et dans `payments.provider_reference`. Le processeur à sept arguments est utilisé par les webhooks ; la signature à six arguments reste comme wrapper de compatibilité.

Wave utilise `event.id` et CinetPay une empreinte SHA-256 des champs signés canoniques incluant le statut vérifié. Les notifications intermédiaires sont désormais enregistrées sans empêcher l'événement terminal suivant.

Tests Deno : `_shared/provider_event_identity_test.ts`. Tests SQL : `phase1_commerce_integrity_test.sql`.

## 7. Limites de cette passe

- Le constat est issu des migrations versionnées ; aucune écriture ni requête SQL distante n'a été exécutée durant cette passe.
- Aucun événement marchand réel ni transaction sandbox n'a été émis.
- La CLI Supabase et l'accès autorisé au projet ne sont pas disponibles dans cette session ; aucune migration n'a donc été créée ou appliquée.
- Ne pas déclarer les séquences multi-événements Wave/CinetPay prêtes pour la production avant la correction DB et les tests décrits ci-dessus.
