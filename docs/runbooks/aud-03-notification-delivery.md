# AUD-03 — Fiabilité des notifications push

## Changement

La table `public.notification_push_deliveries` conserve un état par couple notification/appareil :
- `PENDING` : l'envoi doit être retenté ;
- `SENT` : FCM a accepté l'envoi ;
- `INVALID` : le jeton est vide ou déclaré non enregistré par FCM, et l'appareil est désactivé si FCM confirme `UNREGISTERED`.

L'Edge Function `dispatch-push-notifications` consulte ces états avant chaque tentative. Les appareils déjà marqués `SENT` ou `INVALID` sont ignorés lors des reprises. Une notification n'est marquée comme terminée (`push_sent_at`) que lorsque tous les appareils actifs ciblés ont un état terminal.

## Garantie et limites

- La garantie est **au moins une fois** pour un appareil dont le résultat réseau est ambigu : si FCM accepte le message mais que la réponse ou l'écriture SQL est perdue, une reprise peut produire un doublon.
- Les appareils déjà confirmés `SENT` ne sont pas renvoyés lors d'une reprise normale.
- Les notifications anciennes déjà marquées `push_sent_at` avec `push_error = 'FCM_SEND_FAILED'` ne sont pas réouvertes automatiquement : l'historique ne permet pas de savoir quels appareils ont réellement reçu le message. Une reprise rétroactive demanderait une procédure de support explicite.
- Si aucun appareil actif n'existe, la notification reste en attente et conserve `NO_ACTIVE_DEVICE`. Le balayage périodique peut la reprendre si un appareil est ensuite enregistré.
- Les états de livraison sont internes : RLS activée, aucun accès aux rôles `anon` et `authenticated`, écriture réservée au service.

## Ordre de mise en service

1. Appliquer la migration `20261118212000_notification_per_device_delivery_retry.sql` dans un environnement de test.
2. Exécuter `supabase/tests/database/notification_push_delivery_test.sql` avec pgTAP.
3. Déployer ensuite la version Edge Function mise à jour.
4. Tester avec plusieurs appareils de test : succès complet, un appareil en erreur temporaire, jeton FCM `UNREGISTERED`, et reprise après interruption.
5. Vérifier qu'un appareil déjà `SENT` ne reçoit pas une deuxième notification quand un autre appareil échoue.

Aucun envoi FCM réel, aucune migration distante et aucun déploiement n'ont été effectués dans cette correction.
