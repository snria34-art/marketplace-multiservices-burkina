# Mapbox rollout plan — Marketplace Multiservices Burkina

Status: selected for evaluation and integration; not yet activated in production.

## Verified pricing model

Checked against Mapbox's published pricing on 20 November 2026:

- Maps SDK for Mobile: up to 25,000 monthly active users (MAUs) free.
- Directions API: up to 100,000 requests per month free.
- Temporary Geocoding: up to 100,000 requests per month free.
- Permanent Geocoding has no free tier. Temporary geocoding results must not be stored or cached for later use.

A Maps SDK MAU is a unique app/device that uses Mapbox map functionality during the billing period; it is not a delivery count. Mapbox counts a single app/device once during the billing period. Reinstalling the app can count again.

Official references:
- https://www.mapbox.com/pricing
- https://docs.mapbox.com/flutter/maps/guides/pricing/
- https://docs.mapbox.com/api/search/geocoding/
- https://docs.mapbox.com/api/navigation/directions/

## Package compatibility

The official Flutter package is `mapbox_maps_flutter`. The current stable package is 3.35.1 and requires Flutter 3.38.1 / Dart 3.10 or higher. The repository currently declares Dart >=3.12 and its Flutter CI pins Flutter 3.47.2, so the declared toolchain meets the package's minimum requirements.

Package and setup:
- https://pub.dev/packages/mapbox_maps_flutter
- https://docs.mapbox.com/flutter/maps/guides/install/

## Token handling

A public Mapbox token is required by the client SDK. It must be supplied at build time using `--dart-define=ACCESS_TOKEN=...`; do not commit it in source control or put a secret token in Flutter code. Use a public token with only the required scopes, and create separate tokens for development and production.

Required local build argument:
```bash
flutter build apk --dart-define=ACCESS_TOKEN="$MAPBOX_ACCESS_TOKEN"
```

The production CI and deployment workflows must receive the public token via an encrypted variable; the token is not committed to GitHub.

## Cost-control rules for delivery tracking

1. Load the map only on the order-tracking screen or when the customer opens the address picker, not on every catalogue card.
2. Keep the existing courier GPS upload guard: active assignment only, 25 m distance filter and 15-second Android interval.
3. Do not call Directions for every GPS update. Calculate the route at assignment/start and refresh only on explicit reroute conditions.
4. Avoid background map rendering for customers who are not viewing tracking.
5. Use a Mapbox usage dashboard and budget alerts; the free thresholds are not a lifetime or fixed-price plan.
6. Never store Temporary Geocoding responses as a saved address. Store user-entered address text and the coordinate the user deliberately confirms on the map. Permanent geocoding is a separately billed option.

## Integration gate

The SDK dependency and platform credentials are intentionally not added in this patch: Flutter/Dart are not installed in the current editing runtime, so the lockfile cannot be generated and the Flutter analyzer/build cannot be run here. Add the SDK, regenerate and commit `pubspec.lock` with Flutter 3.47.2, then run Android, iOS and Web builds before enabling Mapbox. Until then, keep the existing Flutter map as the working fallback.
