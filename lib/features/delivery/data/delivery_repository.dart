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
          'id,shop_id,shops(name),'
          'order_packages(id,status,picked_up_at,delivered_at,updated_at)',
        )
        .eq('order_id', orderId)
        .order('created_at');

    final result = <Map<String, dynamic>>[];
    for (final rawGroup in groups as List) {
      final group = Map<String, dynamic>.from(rawGroup as Map);
      final rawPackages = group['order_packages'];
      final packages = rawPackages is List ? rawPackages : const [];

      for (final rawPackage in packages) {
        final package = Map<String, dynamic>.from(rawPackage as Map);
        package['shop_name'] = group['shops'] is Map
            ? (group['shops'] as Map)['name']
            : null;
        result.add(package);
      }
    }

    // Customers cannot read delivery_assignments directly. This RPC verifies
    // order ownership and returns only the latest courier position for an
    // active assignment, without widening table-level RLS permissions.
    final rawAssignments = await client.rpc(
      'get_customer_order_delivery_assignments',
      params: {'p_order_id': orderId},
    );
    final assignmentRows = rawAssignments is List
        ? rawAssignments
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList()
        : const <Map<String, dynamic>>[];

    final trackingByPackage = <String, Map<String, dynamic>>{};
    for (final row in assignmentRows) {
      final packageId = row['package_id']?.toString() ?? '';
      if (packageId.isEmpty) continue;

      final assignmentId = row['assignment_id']?.toString();
      final courierId = row['courier_id']?.toString();
      final assignment = assignmentId == null
          ? null
          : <String, dynamic>{
              'id': assignmentId,
              'courier_id': courierId,
              'status': row['assignment_status'],
              'assigned_at': row['assigned_at'],
              'accepted_at': row['accepted_at'],
              'completed_at': row['assignment_completed_at'],
            };

      final tracking = <String, dynamic>{
        'assignment': assignment,
      };
      final latitude = row['courier_latitude'];
      final longitude = row['courier_longitude'];
      if (latitude != null && longitude != null) {
        tracking['latest_location'] = <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'accuracy_m': row['courier_accuracy_m'],
          'recorded_at': row['courier_recorded_at'],
        };
      }
      trackingByPackage[packageId] = tracking;
    }

    for (final package in result) {
      final packageId = package['id']?.toString() ?? '';
      final tracking = trackingByPackage[packageId];
      package['assignment'] = tracking?['assignment'];
      if (tracking?['latest_location'] is Map) {
        package['latest_location'] = tracking!['latest_location'];
      }
    }

    // Delivery history is readable by the customer who owns the order under
    // the existing delivery_events RLS policy. Only non-sensitive event
    // fields are selected; metadata and actor identifiers stay server-side.
    final packageIds = result
        .map((package) => package['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (packageIds.isNotEmpty) {
      final eventRows = await client
          .from('delivery_events')
          .select('id,package_id,status,created_at')
          .inFilter('package_id', packageIds)
          .order('created_at');

      final eventsByPackage = <String, List<Map<String, dynamic>>>{};
      for (final rawEvent in eventRows as List) {
        final event = Map<String, dynamic>.from(rawEvent as Map);
        final packageId = event['package_id']?.toString() ?? '';
        if (packageId.isEmpty) continue;
        eventsByPackage.putIfAbsent(packageId, () => []).add(event);
      }

      for (final package in result) {
        final packageId = package['id']?.toString() ?? '';
        package['events'] = eventsByPackage[packageId] ??
            const <Map<String, dynamic>>[];
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
        .select('order_packages(id)')
        .eq('order_id', orderId);

    final packageIds = <String>{};
    for (final rawGroup in groups as List) {
      final group = rawGroup as Map;
      final rawPackages = group['order_packages'];
      if (rawPackages is! List) continue;

      for (final rawPackage in rawPackages) {
        final packageId = (rawPackage as Map)['id']?.toString();
        if (packageId != null && packageId.isNotEmpty) {
          packageIds.add(packageId);
        }
      }
    }

    // The same ownership-checked RPC exposes only active courier IDs needed
    // to subscribe to the current customer's delivery updates.
    final rawAssignments = await client.rpc(
      'get_customer_order_delivery_assignments',
      params: {'p_order_id': orderId},
    );
    final courierIds = <String>{};
    if (rawAssignments is List) {
      for (final rawAssignment in rawAssignments) {
        final assignment = rawAssignment as Map;
        final courierId = assignment['courier_id']?.toString();
        if (courierId != null && courierId.isNotEmpty) {
          courierIds.add(courierId);
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
