import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class DeviceLocationService {
  const DeviceLocationService._();

  static Future<Position> current() async {
    await _ensureLocationPermission(requireAlways: false);
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
      ),
    );
  }

  /// Requests background-capable permission only after the courier explicitly
  /// enables tracking for an active delivery assignment.
  static Future<void> ensureBackgroundTrackingPermission() async {
    await _ensureLocationPermission(requireAlways: true);
  }

  static Future<void> _ensureLocationPermission({
    required bool requireAlways,
  }) async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw StateError('Le service de localisation est désactivé.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError(
        'Autorisez la localisation dans les paramètres de l’application.',
      );
    }

    if (requireAlways && permission != LocationPermission.always) {
      throw StateError(
        'Pour continuer le suivi pendant une livraison en arrière-plan, '
        'autorisez la localisation « Toujours » dans les paramètres.',
      );
    }

    if (!requireAlways &&
        permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw StateError('La permission de localisation est indisponible.');
    }
  }

  static LocationSettings trackingSettings() {
    if (kIsWeb) {
      throw UnsupportedError(
        'Le suivi GPS continu en arrière-plan nécessite l’application mobile.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
          intervalDuration: const Duration(seconds: 15),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'Suivi de livraison actif',
            notificationText:
                'Votre position est partagée pendant votre mission de livraison.',
            notificationChannelName: 'Suivi des livraisons',
            enableWakeLock: false,
            enableWifiLock: false,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          activityType: ActivityType.automotiveNavigation,
          distanceFilter: 25,
          pauseLocationUpdatesAutomatically: false,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
        );
      default:
        return const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        );
    }
  }

  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: trackingSettings(),
    );
  }
}
