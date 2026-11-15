# AUD-26 — Préparation des tests Wave et CinetPay en environnement de test

**Projet :** Marketplace Multiservices Burkina  
**Branche examinée :** `maintenance/audit-01-07-2026-11-15`  
**Date :** 16 novembre 2026  
**Statut :** code relu et CI Edge réussie ; tests sandbox non exécutés faute d'accès aux comptes et aux secrets.

## 1. Garde-fous

- Aucun paiement réel, remboursement réel, transfert ou payout ne sert de test.
- N'ajouter aucune clé ou secret à Git, Flutter, aux issues/logs ou au chat.
- Ne pas remplacer les secrets de production. Les clés de test doivent être identifiées et séparées explicitement des clés de production dans le coffre Edge Functions.
- Ne pas déployer les fonctions ni modifier les secrets de l'environnement hébergé dans le cadre de cette préparation.
- Utiliser un projet Supabase isolé/staging et des commandes/test-data propres à cet environnement avant tout appel fournisseur.
- Un timeout ou une réponse ambiguë n'autorise jamais une répétition aveugle : rapprocher d'abord l'état chez le fournisseur et dans Supabase.

## 2. Éléments du dépôt

Fonctions attendues :
- Wave : `create-wave-payment-session-v3`, `wave-payment-webhook-v3`.
- CinetPay : `create-cinetpay-payment-session-v3`, `cinetpay-webhook-v3`.
- Commun : `check-payment-provider-config`, `payment-return`, `execute-payment-refund`.

Secrets documentés côté Edge Functions :
- Wave : `WAVE_API_KEY`, `WAVE_WEBHOOK_SECRET`; `WAVE_SIGNING_SECRET` uniquement si la signature sortante est activée.
- CinetPay : `CINETPAY_API_KEY`, `CINETPAY_SITE_ID`, `CINETPAY_SECRET_KEY`.

Ces noms proviennent de la configuration documentée du dépôt. Leur présence et leur validité sur le projet hébergé ne sont pas vérifiées.

## 3. Préconditions fournisseur à confirmer

### Wave

La documentation officielle Checkout consultée indique l'API Business à `https://api.wave.com`, l'authentification par clé API serveur et des webhooks qui peuvent être livrés plusieurs fois. Elle recommande de garder les clés secrètes. La page Checkout ne décrit pas de sandbox publique : obtenir du responsable Wave la confirmation d'un compte/wallet de test, la portée des clés autorisées et la procédure non financière de validation des webhooks avant de lancer un appel.

Références :
- https://docs.wave.com/checkout
- https://docs.wave.com/webhook

### CinetPay

Confirmer auprès de CinetPay le mode sandbox, la base API, les identifiants, les scénarios de paiement et la procédure de notification correspondant précisément à l'API utilisée dans `cinetpay-webhook-v3`. Des SDKs/API plus récents peuvent documenter des clés et bases différentes ; ne pas substituer leurs paramètres au contrat actuellement codé sans revue et tests de compatibilité.

Référence d'intégration propre au projet : `docs/payment-integration.md`.

## 4. Matrice de tests à exécuter en staging

Pour chacun des fournisseurs, avec un panier fictif et une commande jetable :

1. Configuration absente : le précontrôle retourne non configuré et le checkout ne crée ni commande ni réservation de stock.
2. Configuration de test valide : démarrage du checkout, référence fournisseur enregistrée, redirection externe correcte.
3. Signature webhook invalide : rejet HTTP, aucun changement de paiement/commande.
4. Succès XOF exact : événement accepté une seule fois, paiement passé à `SUCCEEDED`, commande passée à `PAID`.
5. Montant différent, devise différente, montant décimal ou hors plage sûre : rejet avant toute transition.
6. Événement identique rejoué : acquittement idempotent sans deuxième mutation.
7. Deux événements distincts sur la même référence de session/transaction : identité d'événement stable distincte, aucune collision d'index.
8. État non terminal : reste `PROCESSING`, ne libère pas le stock et ne valide pas la commande.
9. Échec terminal : transitions cohérentes, libération de stock une seule fois.
10. Événements arrivant dans le désordre : pas de régression d'un paiement réussi vers un état antérieur.
11. Timeout fournisseur ou erreur 5xx : état ambigu conservé pour rapprochement ; aucune nouvelle session ni requête financière automatique aveugle.
12. Référence fournisseur absente ou liée à un autre paiement : rejet et journalisation sans divulguer de secret.

Montants : utiliser des entiers XOF de test conformes aux validations de la fonction. Le chemin CinetPay v3 du dépôt exige un montant entier positif sûr, au moins 100 XOF et multiple de 5.

## 5. Cas particuliers de remboursement

- Wave Checkout : le endpoint de remboursement documenté rembourse la session Checkout entière. Le code doit refuser l'appel automatique si le montant demandé n'est pas exactement égal au paiement capturé en XOF. Les remboursements partiels restent hors automatisation et nécessitent une procédure contractuelle manuelle.
- CinetPay : le dépôt ne possède pas de chemin de remboursement API automatique validé. Vérifier le canal contractuel de remboursement auprès du marchand ; ne pas assimiler une confirmation manuelle à une preuve technique fournisseur.
- Le garde-fou `PENDING_ALLOCATION` du chantier AUD-02 demeure actif : aucun test ne doit lever le gel des payouts ou du ledger vendeur.

## 6. Critères d'acceptation

- Deux suites fournisseur séparées, sur des identifiants de test confirmés et un Supabase staging isolé.
- Journal de test expurgé de toute donnée personnelle et de tout secret.
- Résultat attendu/observé conservé pour chaque scénario, y compris rejeu, timeout, montant incorrect et ordre des événements.
- Aucune transaction visible sur le compte marchand de production.
- CI Deno et tests SQL locaux verts sur le commit qui porte les correctifs.
- Revue sécurité indépendante des signatures, de l'idempotence et des opérations de rapprochement avant activation réelle.

## 7. État au 16 novembre 2026

La CI Edge [run 43753543111](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/runs/43753543111) a réussi sur `bf42b629c89efbd2f909941a0a5a74966cb9ee17`. La comparaison GitHub confirme qu'aucun fichier `supabase/functions/` n'a changé entre ce commit et la tête `a61064cf7d07f419c9c68a764cb3d8ad2a6a6ef4`.

Aucun accès au projet Supabase ni aux secrets marchands n'est disponible dans cette session. Les tests fournisseur restent donc **non exécutés**.