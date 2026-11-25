# Marketplace Multiservices Burkina

<!-- CI badges -->
[![Flutter CI — main](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/flutter-ci.yml/badge.svg?branch=main)](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/flutter-ci.yml)
[![Flutter CI — maintenance](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/flutter-ci.yml/badge.svg?branch=maintenance%2Faudit-01-07-2026-11-15)](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/flutter-ci.yml)
[![Supabase Edge Functions CI — main](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/supabase-functions-ci.yml/badge.svg?branch=main)](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/supabase-functions-ci.yml)
[![Supabase Edge Functions CI — maintenance](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/supabase-functions-ci.yml/badge.svg?branch=maintenance%2Faudit-01-07-2026-11-15)](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/supabase-functions-ci.yml)
[![Native debug validation](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/native-build.yml/badge.svg?branch=maintenance%2Faudit-01-07-2026-11-15)](https://github.com/snria34-art/marketplace-multiservices-burkina/actions/workflows/native-build.yml)


**Dépôt de référence :** [`snria34-art/marketplace-multiservices-burkina`](https://github.com/snria34-art/marketplace-multiservices-burkina).  
**Phase actuelle :** maintenance et corrections uniquement. Aucun déploiement Vercel, aucune publication GitHub, aucun build de release ni promotion de production ne doit être lancé avant autorisation explicite.

Application mobile Flutter pour marketplace locale et services associés au Burkina Faso.

## Stack

Flutter 3.47.2 (Dart 3.13+), Supabase, Riverpod, go_router, Geolocator et Firebase Messaging.

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

Pendant la maintenance, le SDK Flutter est volontairement borné à `>=3.47.2 <3.50.0` pour rester cohérent avec la chaîne Android AGP 9.1.0 / Gradle 9.3.1 enregistrée et les workflows. Ne pas passer Flutter 3.50+ avant mise à niveau coordonnée d'AGP/Gradle et validation de tous les plugins natifs. Ne jamais inclure de secret de production dans le code source, les logs ou les paramètres de compilation partagés.

## Validation

Le workflow GitHub Actions prévu exécute `flutter analyze` et `flutter test`. Le résultat doit être confirmé sur le dernier commit ; aucune réussite locale ne doit être revendiquée si le SDK Flutter n'a pas été exécuté.

## Base de données et migrations

Au 6 novembre 2026, le contrôle Supabase en lecture seule relève **321 migrations appliquées** sur la base active. Ce chiffre décrit l'historique distant, pas le degré de complétude fonctionnelle.

Les corrections récentes du stock par variante, des annulations, des fonctions administrateur et des RPC coursier sont documentées dans [l'audit du 4 novembre 2026](docs/audit-2026-11-04.md).

**Point bloquant de reproductibilité :** les 15 migrations de correction de novembre 2026 sont maintenant présentes dans `supabase/migrations/`. L'historique SQL plus ancien reste incomplet dans le dépôt ; la reconstruction d'une base vide n'est donc pas encore démontrée.

Consulter également [l'audit complet du 6 novembre 2026](docs/audit-complet-2026-11-06.md), [l'audit du 4 novembre 2026](docs/audit-2026-11-04.md) et [l'audit du 11 octobre 2026](docs/audit-2026-10-11.md) pour les constats détaillés et historiques.


## Cible navigateur — préparation suspendue

La cible Flutter Web est conservée dans le dépôt pour une phase ultérieure. **Aucun projet Vercel ne doit être créé ou relié et aucun Preview/Production ne doit être déclenché pendant la maintenance.** Les étapes ci-dessous sont une documentation future uniquement et ne valent pas autorisation de publication :
- web/ contient la page d'entrée et le manifeste ;
- vercel.json configure le build et le routage SPA ;
- scripts/vercel-build.sh installe Flutter 3.47.2 puis compile build/web.

Après liaison du projet Vercel, définir ces variables comme variables Encrypted pour Preview et Production :
- SUPABASE_URL : URL du projet Supabase ;
- SUPABASE_PUBLISHABLE_KEY : clé publique publishable uniquement.

Ne jamais fournir de clé service_role, sb_secret_*, secret Firebase ou clé de paiement au navigateur.

L'URL publique n'est pas demandée à ce stade. Ne pas approuver ou créer une connexion Vercel ni lancer de déploiement Preview/Production sans autorisation explicite. Voir docs/runbooks/aud-23-vercel-web-release.md et docs/audit-global-2026-11-07.md.

Cette cible web n'active pas à elle seule les notifications push Web ni le retour navigateur des paiements. Les applications natives restent des livrables distincts.
