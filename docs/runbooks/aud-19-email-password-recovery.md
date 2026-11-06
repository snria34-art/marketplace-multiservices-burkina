# AUD-19 — Récupération du mot de passe par email

**Date :** 7 novembre 2026  
**Projet Supabase :** `dzhhsoikzxibmngjzcch`  
**Branche :** `main`  
**État :** écrans et routes ajoutés ; la configuration Auth URL/SMTP et les tests sur appareil restent à valider.

## 1. Ce qui est ajouté

### Demande de récupération

Depuis l'écran de connexion, le lien `Mot de passe oublié ?` ouvre `/auth/forgot-password`.

Le formulaire :
- demande l'adresse email ;
- appelle `supabase.auth.resetPasswordForEmail(email, redirectTo: ...)` ;
- ne révèle pas si l'adresse correspond à un compte, afin de limiter l'énumération de comptes ;
- affiche une confirmation générique lorsque la demande est acceptée par Supabase.

### Callback et changement du mot de passe

- URL mobile de callback déclarée dans le code : `marketplaceburkina://auth/recovery`.
- Android : intent-filter ajouté pour le schéma `marketplaceburkina`, hôte `auth`, chemin `/recovery`.
- iOS : schéma `marketplaceburkina` déjà présent dans `CFBundleURLTypes`.
- `Supabase.initialize()` est appelé avant l'enregistrement de `AuthRecoveryState.attach(client)`. L'écouteur démarre immédiatement après l'initialisation et écoute `AuthChangeEvent.passwordRecovery`.
- Le formulaire `/auth/recovery` reste verrouillé tant que Supabase n'a pas émis l'événement `passwordRecovery`. Une session utilisateur normale ne suffit pas à autoriser ce formulaire.
- Après validation des deux mots de passe et du minimum de 8 caractères, le client appelle `auth.updateUser(UserAttributes(password: ...))`.
- Le marqueur de récupération est effacé après déconnexion ou après modification réussie du mot de passe.

Deux routes sont disponibles pour la compatibilité des parseurs de liens mobiles :
- `/auth/recovery` ;
- `/recovery`, lorsque le parseur de schéma personnalisé ne conserve que le path de la URI.

## 2. Configuration obligatoire dans Supabase Dashboard

Cette configuration n'est pas modifiable via les outils de connexion utilisés pendant cet audit ; elle doit être appliquée directement par un propriétaire du projet.

1. Ouvrir Supabase Dashboard > Authentication > URL Configuration.
2. Ajouter exactement `marketplaceburkina://auth/recovery` dans **Redirect URLs** (liste d'autorisation).
3. Vérifier que le Site URL reste une URL valide prévue pour l'application ; le callback explicite utilise l'URL de redirection fournie à `resetPasswordForEmail`.
4. Ouvrir Authentication > Email Templates > Reset Password.
5. Vérifier que le lien du modèle utilise le lien de confirmation Supabase (`{{ .ConfirmationURL }}`) afin que le `redirectTo` autorisé soit respecté.
6. Envoyer un email de test à un compte de staging et vérifier que le lien ouvre bien l'application sur l'écran de récupération.

Si l'URL n'est pas autorisée, Supabase peut ignorer ou refuser la redirection demandée et le callback de l'application ne sera pas atteint.

## 3. SMTP et coûts

Les emails de récupération nécessitent un service d'envoi email :
- Supabase fournit un service SMTP intégré limité à des fins d'essai, soumis à des limites et à une livraison best-effort.
- Pour production, il faut généralement configurer un SMTP personnalisé et vérifier le domaine expéditeur.
- Aucun fournisseur SMTP payant n'a été activé, aucune clé SMTP n'a été lue ou ajoutée à GitHub, et aucun email de test n'a été envoyé pendant ce travail.

Avant d'utiliser ce flux avec de vrais clients, vérifier les limites actuelles et le coût du fournisseur mail choisi. Les secrets doivent être saisis uniquement dans le Dashboard ou le gestionnaire de secrets approprié.

## 4. Pourquoi l'OTP téléphone n'est pas activé

Supabase Phone Auth / SMS OTP nécessite un fournisseur externe SMS tel que Twilio, MessageBird ou Vonage et la configuration de leurs identifiants. Les messages SMS entraînent des frais variables selon le fournisseur et la destination. Les numéros téléphoniques peuvent aussi être recyclés ; une identification téléphone seule doit être accompagnée de protections supplémentaires.

Aucun fournisseur SMS n'a été configuré ni activé et aucun SMS n'a été envoyé. L'OTP téléphone reste un chantier distinct à décider après validation du coût et du parcours pays +226.

## 5. Tests à exécuter

1. Adresse qui existe : demander le reset, recevoir le mail, ouvrir le lien sur Android puis iOS.
2. Adresse qui n'existe pas : le message dans l'application reste générique.
3. URL de callback non autorisée : vérifier qu'aucun changement de mot de passe n'est possible.
4. Lien expiré ou déjà utilisé : le formulaire reste verrouillé ou l'API renvoie une erreur ; demander un nouveau lien.
5. Ouvrir `/auth/recovery` sans événement de récupération avec une session ordinaire : le formulaire reste verrouillé.
6. Modifier le mot de passe, vérifier l'ancien refusé et le nouveau accepté.
7. Se déconnecter après récupération, puis vérifier que le formulaire de récupération est verrouillé.
8. Vérifier le comportement à froid (application fermée) et à chaud (application déjà ouverte), sur Android et iOS.

Test unitaire ajouté :
- `test/core/auth/auth_recovery_state_test.dart` : ouverture uniquement après événement, fermeture après complétion.
- `test/core/routing/route_access_test.dart` : pages de récupération déclarées accessibles sans authentification préalable, car l'autorisation du formulaire est gérée par l'événement de récupération.

Les tests Flutter ne sont pas confirmés exécutés dans cette session ; GitHub Actions a historiquement échoué sans étapes ni logs récupérables. Aucun email, compte utilisateur ou mot de passe réel n'a été utilisé.

## 6. État

- Écran mot de passe oublié : ajouté.
- Écran nouveau mot de passe : ajouté, verrouillé par l'événement Supabase.
- Callback Android/iOS : code ajouté.
- Configuration Supabase Redirect URLs : action Dashboard restant à faire.
- SMTP de production : non configuré / non vérifié.
- Phone OTP : non activé, fournisseur SMS et coût à décider.
- Tests sur appareils : à exécuter.
