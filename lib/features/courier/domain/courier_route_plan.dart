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
    final value = (assignment['assignment_id'] ?? assignment['id'])?.toString();
    if (value == null || value.trim().isEmpty || value == 'null') {
      throw const FormatException('Identifiant de mission indisponible.');
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
      final status = row['status']?.toString().toUpperCase();
      final id = row['package_id']?.toString() ?? '';
      return id.isNotEmpty && activeStatuses.contains(status);
    }).toList()
      ..sort((a, b) {
        final left = DateTime.tryParse(a['assigned_at']?.toString() ?? '');
        final right = DateTime.tryParse(b['assigned_at']?.toString() ?? '');
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });

    final pickups = <CourierRouteStop>[];
    final dropoffs = <CourierRouteStop>[];

    for (final assignment in active) {
      final packageId = assignment['package_id'].toString();
      final status = assignment['status']?.toString().toUpperCase() ?? '';
      final shopAddress = assignment['shop_address']?.toString().trim() ?? '';
      final deliveryAddress = [
        assignment['delivery_address_line']?.toString().trim() ?? '',
        assignment['delivery_city']?.toString().trim() ?? '',
      ].where((part) => part.isNotEmpty).join(', ');

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
          latitude: assignment['delivery_latitude']?.toString(),
          longitude: assignment['delivery_longitude']?.toString(),
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
