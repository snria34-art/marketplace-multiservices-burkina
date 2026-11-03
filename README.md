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

Au 4 novembre 2026, la base Supabase active indique **258 migrations appliquées**. Ce chiffre décrit l'historique distant, pas le degré de complétude fonctionnelle.

Les corrections récentes du stock par variante, des annulations, des fonctions administrateur et des RPC coursier sont documentées dans [l'audit du 4 novembre 2026](docs/audit-2026-11-04.md).

**Point bloquant de reproductibilité :** l'historique SQL complet n'est pas encore synchronisé dans le dépôt. Les migrations appliquées à distance doivent être ajoutées et vérifiées dans `supabase/migrations/` avant de considérer le dépôt comme capable de recréer une base vide de façon déterministe.

Consulter également [l'audit du 11 octobre 2026](docs/audit-2026-10-11.md) pour les constats historiques.
