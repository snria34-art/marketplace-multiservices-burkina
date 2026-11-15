class CourierRouteStop {
  const CourierRouteStop({
    required this.sequence,
    required this.packageId,
    required this.kind,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.completed,
  });

  final int sequence;
  final String packageId;
  final String kind;
  final String address;
  final String? latitude;
  final String? longitude;
  final bool completed;
}

class CourierRoutePlan {
  const CourierRoutePlan._();

  static const activeStatuses = {
    'ASSIGNED',
    'ACCEPTED',
    'PICKED_UP',
    'IN_TRANSIT',
  };

  /// The courier assignment RPC exposes the primary key as assignment_id.
  /// Accept the legacy id key only for callers using an older read model.
  static String requireAssignmentId(Map<String, dynamic> assignment) {
    final raw = assignment['assignment_id'] ?? assignment['id'];
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty || value.toLowerCase() == 'null') {
      throw const FormatException('Identifiant de mission indisponible.');
    }
    return value;
  }

  static double? _validCoordinate(Object? raw, {required double min, required double max}) {
    final value = double.tryParse(raw?.toString().trim() ?? '');
    if (value == null || !value.isFinite || value < min || value > max) {
      return null;
    }
    return value;
  }

  /// Combines all currently assigned packages for the signed-in courier into
  /// one operational itinerary. This is a client-side grouping only: it does
  /// not create or mutate database assignments or persisted delivery routes.
  ///
  /// The safe default sequence is all shop pickups followed by all customer
  /// drop-offs. It deliberately does not claim road-distance optimisation.
  static List<CourierRouteStop> build(
    List<Map<String, dynamic>> assignments,
  ) {
    final active = assignments.where((row) {
      final status = row['status']?.toString().trim().toUpperCase();
      final id = row['package_id']?.toString().trim() ?? '';
      return id.isNotEmpty && id.toLowerCase() != 'null' &&
          activeStatuses.contains(status);
    }).toList()
      ..sort((a, b) {
        final left = DateTime.tryParse(a['assigned_at']?.toString() ?? '');
        final right = DateTime.tryParse(b['assigned_at']?.toString() ?? '');
        if (left == null && right == null) {
          return (a['package_id']?.toString() ?? '')
              .compareTo(b['package_id']?.toString() ?? '');
        }
        if (left == null) return 1;
        if (right == null) return -1;
        final byDate = left.compareTo(right);
        if (byDate != 0) return byDate;
        return (a['package_id']?.toString() ?? '')
            .compareTo(b['package_id']?.toString() ?? '');
      });

    final pickups = <CourierRouteStop>[];
    final dropoffs = <CourierRouteStop>[];

    for (final assignment in active) {
      final packageId = assignment['package_id'].toString().trim();
      final status = assignment['status']?.toString().trim().toUpperCase() ?? '';
      final shopAddress = assignment['shop_address']?.toString().trim() ?? '';
      final deliveryAddress = [
        assignment['delivery_address_line']?.toString().trim() ?? '',
        assignment['delivery_city']?.toString().trim() ?? '',
      ].where((part) => part.isNotEmpty).join(', ');
      final latitude = _validCoordinate(
        assignment['delivery_latitude'],
        min: -90,
        max: 90,
      );
      final longitude = _validCoordinate(
        assignment['delivery_longitude'],
        min: -180,
        max: 180,
      );
      final hasValidCoordinates = latitude != null && longitude != null;

      pickups.add(
        CourierRouteStop(
          sequence: 0,
          packageId: packageId,
          kind: 'PICKUP',
          address: shopAddress,
          latitude: null,
          longitude: null,
          completed: status == 'PICKED_UP' || status == 'IN_TRANSIT',
        ),
      );
      dropoffs.add(
        CourierRouteStop(
          sequence: 0,
          packageId: packageId,
          kind: 'DROPOFF',
          address: deliveryAddress,
          latitude: hasValidCoordinates ? latitude.toString() : null,
          longitude: hasValidCoordinates ? longitude.toString() : null,
          completed: false,
        ),
      );
    }

    final ordered = [...pickups, ...dropoffs];
    return [
      for (var index = 0; index < ordered.length; index++)
        CourierRouteStop(
          sequence: index + 1,
          packageId: ordered[index].packageId,
          kind: ordered[index].kind,
          address: ordered[index].address,
          latitude: ordered[index].latitude,
          longitude: ordered[index].longitude,
          completed: ordered[index].completed,
        ),
    ];
  }
}
