# Marketplace Multiservices Burkina

Application mobile Flutter pour marketplace locale et services associés au Burkina Faso.

## Stack

Flutter stable 3.47+, Dart 3.12+, Supabase, Riverpod, go_router, Geolocator et Firebase Messaging.

## État du projet

Le dépôt couvre les principaux parcours de marketplace et de services : authentification, catalogue paginé, catégories dynamiques, panier/checkout, commandes multi-vendeurs, livraison, mécaniciens, transport, restaurants, achats groupés, favoris, notifications, messagerie, support, administration, vendeurs, finance et plusieurs verticales de services.

**Cet état fonctionnel ne vaut pas validation de production.** Les workflows doivent être vérifiés par tests et par les résultats CI les plus récents. Les intégrations marchandes de paiement et les clés de production doivent être configurées séparément.

## Sécurité

- Les opérations sensibles doivent rester côté serveur avec contrôle de propriété, permissions et RLS/RPC.
- Ne jamais placer une clé `service_role` dans l’application mobile.
- Les fonctions `SECURITY DEFINER` doivent être auditées une par une : une alerte générique du linter ne prouve pas à elle seule qu'une fonction est vulnérable, mais chaque fonction exposée doit vérifier l'identité, les permissions et la portée des données.
- Les avertissements PostGIS ne doivent pas être corrigés en déplaçant aveuglément l'extension, car cela peut casser la géolocalisation.

## Lancer localement

Si les plateformes natives `android/` et `ios/` ne sont pas présentes :

```bash
flutter create . --platforms=android,ios
flutter pub get
flutter run --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Ne jamais inclure de secret de production dans le code source, les logs ou les paramètres de compilation partagés.

## Validation

Le workflow GitHub Actions prévu exécute `flutter analyze` et `flutter test`. Le résultat doit être confirmé sur le dernier commit ; aucune réussite locale ne doit être revendiquée si le SDK Flutter n'a pas été exécuté.

## Base de données et migrations

Au 6 novembre 2026, le contrôle Supabase en lecture seule relève **321 migrations appliquées** sur la base active. Ce chiffre décrit l'historique distant, pas le degré de complétude fonctionnelle.

Les corrections récentes du stock par variante, des annulations, des fonctions administrateur et des RPC coursier sont documentées dans [l'audit du 4 novembre 2026](docs/audit-2026-11-04.md).

**Point bloquant de reproductibilité :** les 15 migrations de correction de novembre 2026 sont maintenant présentes dans `supabase/migrations/`. L'historique SQL plus ancien reste incomplet dans le dépôt ; la reconstruction d'une base vide n'est donc pas encore démontrée.

Consulter également [l'audit complet du 6 novembre 2026](docs/audit-complet-2026-11-06.md), [l'audit du 4 novembre 2026](docs/audit-2026-11-04.md) et [l'audit du 11 octobre 2026](docs/audit-2026-10-11.md) pour les constats détaillés et historiques.


## Accès navigateur avec Vercel

Une cible Flutter Web est préparée dans le dépôt :
- web/ contient la page d'entrée et le manifeste ;
- vercel.json configure le build et le routage SPA ;
- scripts/vercel-build.sh installe Flutter 3.47.2 puis compile build/web.

Après liaison du projet Vercel, définir ces variables comme variables Encrypted pour Preview et Production :
- SUPABASE_URL : URL du projet Supabase ;
- SUPABASE_PUBLISHABLE_KEY : clé publique publishable uniquement.

Ne jamais fournir de clé service_role, sb_secret_*, secret Firebase ou clé de paiement au navigateur.

L'URL publique reste à obtenir : l'équipe Vercel doit d'abord approuver l'accès du connecteur, puis le déploiement Preview doit réussir. Voir docs/runbooks/aud-23-vercel-web-release.md et docs/audit-global-2026-11-07.md.

Cette cible web n'active pas à elle seule les notifications push Web ni le retour navigateur des paiements. Les applications natives restent des livrables distincts.
