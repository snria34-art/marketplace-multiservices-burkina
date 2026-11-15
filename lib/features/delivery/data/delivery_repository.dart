import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DeliveryRepository {
  const DeliveryRepository(this.client);

  final SupabaseClient client;

  static const _activeAssignmentStatuses = {
    'ASSIGNED',
    'ACCEPTED',
    'PICKED_UP',
    'IN_TRANSIT',
  };

  Future<List<Map<String, dynamic>>> packagesForOrder(
    String orderId,
  ) async {
    final groups = await client
        .from('order_groups')
        .select(
          'id,shop_id,shops(name),order_packages(id,status,picked_up_at,delivered_at,updated_at,delivery_assignments(id,courier_id,status,accepted_at,completed_at))',
        )
        .eq('order_id', orderId)
        .order('created_at');

    final result = <Map<String, dynamic>>[];
    final courierIds = <String>{};

    for (final rawGroup in groups as List) {
      final group = Map<String, dynamic>.from(rawGroup as Map);
      final rawPackages = group['order_packages'];
      final packages = rawPackages is List ? rawPackages : const [];

      for (final rawPackage in packages) {
        final package = Map<String, dynamic>.from(rawPackage as Map);
        package['shop_name'] = group['shops'] is Map
            ? (group['shops'] as Map)['name']
            : null;

        final assignments = package['delivery_assignments'];
        final activeAssignments = assignments is List
            ? assignments.where((raw) {
                final status = (raw as Map)['status']?.toString().toUpperCase();
                return _activeAssignmentStatuses.contains(status);
              }).toList()
            : const [];
        final assignment = activeAssignments.isNotEmpty
            ? Map<String, dynamic>.from(activeAssignments.first as Map)
            : null;
        package['assignment'] = assignment;

        final courierId = assignment?['courier_id']?.toString();
        if (courierId != null && courierId.isNotEmpty) {
          courierIds.add(courierId);
        }

        result.add(package);
      }
    }

    // Fetch the latest position once per distinct courier and in parallel.
    // This avoids sequential N+1 requests when an order contains several
    // packages assigned to the same courier or to different couriers.
    final latestLocations = <String, Map<String, dynamic>>{};
    await Future.wait(courierIds.map((courierId) async {
      final rows = await client
          .from('courier_locations')
          .select('id,location,accuracy_m,recorded_at')
          .eq('courier_id', courierId)
          .order('recorded_at', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        latestLocations[courierId] =
            Map<String, dynamic>.from(rows.first as Map);
      }
    }));

    for (final package in result) {
      final assignment = package['assignment'];
      if (assignment is! Map) continue;
      final courierId = assignment['courier_id']?.toString();
      final latest = courierId == null ? null : latestLocations[courierId];
      if (latest != null) {
        package['latest_location'] = latest;
      }
    }

    return result;
  }

  Future<RealtimeChannel> watchOrder(
    String orderId,
    VoidCallback onChange,
  ) async {
    final groups = await client
        .from('order_groups')
        .select(
          'order_packages(id,delivery_assignments(courier_id,status))',
        )
        .eq('order_id', orderId);

    final packageIds = <String>{};
    final courierIds = <String>{};
    for (final rawGroup in groups as List) {
      final group = rawGroup as Map;
      final rawPackages = group['order_packages'];
      if (rawPackages is! List) continue;

      for (final rawPackage in rawPackages) {
        final package = rawPackage as Map;
        final packageId = package['id']?.toString();
        if (packageId != null && packageId.isNotEmpty) {
          packageIds.add(packageId);
        }

        final rawAssignments = package['delivery_assignments'];
        if (rawAssignments is! List) continue;

        for (final rawAssignment in rawAssignments) {
          final assignment = rawAssignment as Map;
          final status = assignment['status']?.toString().toUpperCase();
          final courierId = assignment['courier_id']?.toString();
          if (courierId != null &&
              courierId.isNotEmpty &&
              _activeAssignmentStatuses.contains(status)) {
            courierIds.add(courierId);
          }
        }
      }
    }

    var channel = client.channel('delivery-order-$orderId');

    for (final courierId in courierIds) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'courier_locations',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'courier_id',
          value: courierId,
        ),
        callback: (_) => onChange(),
      );
    }

    for (final packageId in packageIds) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'delivery_events',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'package_id',
          value: packageId,
        ),
        callback: (_) => onChange(),
      );
    }

    return channel.subscribe();
  }
}
