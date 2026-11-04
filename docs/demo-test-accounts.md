# Comptes de démonstration — environnement local uniquement

Ces comptes servent à tester les parcours Flutter et les autorisations Supabase. Ils sont créés par le seed local supabase/seed.test.sql. Ne jamais exécuter ce seed sur le projet Supabase hébergé et ne jamais déployer ces identifiants.

## Démarrage local

1. Installer Docker et Supabase CLI.
2. Depuis la racine du dépôt, exécuter : supabase start
3. Sur une base locale neuve, exécuter : supabase db reset. Cette commande réinitialise la base LOCALE et applique les migrations puis les données de démonstration.
4. Récupérer l'URL et la clé publishable locales avec : supabase status
5. Lancer Flutter avec --dart-define=SUPABASE_URL=http://127.0.0.1:54321 et la clé publishable locale affichée par la CLI.

Ne pas utiliser supabase db reset --linked, supabase db push ou supabase config push pour créer ces comptes dans le projet hébergé.

## Identifiants locaux

Mot de passe commun de démonstration : DemoOnly-2026!

| Rôle | Email |
|---|---|
| Client | demo.customer@marketplace.test |
| Vendeur | demo.seller@marketplace.test |
| Livreur | demo.courier@marketplace.test |
| Restaurant | demo.restaurant@marketplace.test |
| Mécanicien | demo.mechanic@marketplace.test |
| Transporteur | demo.transport@marketplace.test |
| Support | demo.support@marketplace.test |
| Modérateur | demo.moderator@marketplace.test |
| Administrateur de test | demo.admin@marketplace.test |

Tous les comptes sont marqués dans auth.users.raw_app_meta_data avec is_test_account=true et environment=local. Le compte administrateur de démonstration reçoit SUPER_ADMIN et une entrée admin_users uniquement dans la base locale. Il ne doit jamais être créé sur l'environnement hébergé.

## Nettoyage

Pour supprimer les comptes et toutes les données de démonstration, arrêter la stack puis réinitialiser la base locale avec supabase db reset. Cette commande détruit toutes les données locales non sauvegardées. Sauvegarder tout travail local utile avant de la lancer.

Ces comptes n'ont pas de téléphone, de vraie identité, de moyen de paiement ou de compte marchand.
