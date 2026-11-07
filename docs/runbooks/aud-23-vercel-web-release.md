# AUD-23 — Publication Flutter Web avec Vercel

Date : 7 novembre 2026
Dépôt : adjasanou49-max/marketplace-multiservices-burkina, branche main

## État

Une cible Flutter Web a été ajoutée au dépôt pour rendre l'application accessible dans un navigateur, en complément des applications natives.

Éléments versionnés :
- web/index.html, web/manifest.json et web/favicon.svg ;
- vercel.json avec la commande de build et les réécritures SPA ;
- scripts/vercel-build.sh : installation Flutter 3.47.2, vérification SHA-256, dépendances verrouillées et compilation release ;
- import conditionnel des contrôleurs vidéo natif/web ;
- callback de récupération de mot de passe web /auth/recovery ;
- étape de compilation web ajoutée à Flutter CI.

Statut : préparation du code terminée ; compilation et déploiement Vercel non encore validés.

La connexion Vercel voit l'espace par défaut ridiastore, mais l'accès du connecteur à cette équipe retourne HTTP 403 avant approbation du consentement. Aucun projet Vercel n'a été créé et aucune URL publique n'est confirmée.

## Configuration Vercel

- Dépôt : adjasanou49-max/marketplace-multiservices-burkina
- Branche : main
- Répertoire racine : .
- Commande de build : bash scripts/vercel-build.sh
- Répertoire de sortie : build/web

Variables requises, type Encrypted, Preview et Production :
- SUPABASE_URL=https://dzhhsoikzxibmngjzcch.supabase.co
- SUPABASE_PUBLISHABLE_KEY : clé publishable du projet Supabase.

Ne jamais placer une clé service_role, sb_secret_*, un compte de service Firebase, une clé privée ou un secret de paiement dans le bundle navigateur.

Le script installe Flutter 3.47.2 depuis l'archive officielle, vérifie son empreinte SHA-256, exécute flutter pub get --enforce-lockfile puis flutter build web --release.

## Contrôles avant promotion Production

1. Approuver l'accès de l'équipe Vercel.
2. Vérifier que le projet est créé dans l'espace attendu et relié au dépôt privé.
3. Définir les deux variables Supabase en Encrypted pour Preview et Production.
4. Lancer un déploiement Preview et examiner son build.
5. Vérifier accueil, authentification, routes directes (/health, /orders, /auth/recovery), session après rafraîchissement, médias, upload, géolocalisation et rôles.
6. Ajouter l'URL exacte du site et le chemin /auth/recovery dans Supabase Authentication > URL Configuration > Redirect URLs.
7. Tester la récupération email via SMTP configuré.
8. Promouvoir Production seulement après validation Preview.

Les 41 règles de réécriture de vercel.json doivent être confirmées par tests navigateur sur le vrai déploiement.

## Limitations web connues

- PushNotificationService retourne immédiatement lorsque kIsWeb est vrai : le push navigateur n'est pas activé.
- payment-return renvoie actuellement un deep link mobile marketplaceburkina://orders/... ; le retour de paiement navigateur doit utiliser l'URL exacte du site web avant d'activer le checkout dans le navigateur.
- Géolocalisation, caméra, vidéo, permissions, uploads et partage doivent être testés en HTTPS sur les navigateurs ciblés.
- Le résultat du build web n'est pas validé : Flutter/Dart n'étaient pas installés localement et les runners GitHub Actions observés n'ont pas démarré.

## Sécurité et preuves

RLS et les contrôles de rôle/propriété serveur restent obligatoires. Masquer un écran Flutter ne remplace jamais l'autorisation côté serveur. Ne pas utiliser de jeu de données fictif sur la base de production.

Cases à fermer :
- [ ] Consentement Vercel approuvé.
- [ ] Projet Vercel lié au bon dépôt et à la bonne équipe.
- [ ] Variables publiques Supabase configurées en Encrypted.
- [ ] Build Preview READY.
- [ ] Navigation directe et session testées.
- [ ] URL de récupération web autorisée dans Supabase.
- [ ] Paiement navigateur et URL de retour validés en sandbox.
- [ ] Push web évalué ou explicitement non proposé.
- [ ] Production promue après validation.

Aucun compte utilisateur, boutique, produit, commande, paiement ou jeu de données de test n'a été créé pendant AUD-23.
