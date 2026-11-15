import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/features/courier/domain/courier_route_plan.dart';

void main() {
  group('CourierRoutePlan.requireAssignmentId', () {
    test('uses the assignment_id field returned by the secure RPC', () {
      expect(
        CourierRoutePlan.requireAssignmentId({'assignment_id': 'assignment-1'}),
        'assignment-1',
      );
    });

    test('accepts the legacy id field for older read models', () {
      expect(
        CourierRoutePlan.requireAssignmentId({'id': 'assignment-2'}),
        'assignment-2',
      );
    });

    test('rejects a missing assignment identifier', () {
      expect(
        () => CourierRoutePlan.requireAssignmentId({'package_id': 'package-1'}),
        throwsFormatException,
      );
    });
  });

  group('CourierRoutePlan.build', () {
    test('places all shop pickups before customer drop-offs', () {
      final stops = CourierRoutePlan.build([
        {
          'package_id': 'package-b',
          'status': 'ASSIGNED',
          'assigned_at': '2026-11-15T10:00:00Z',
          'shop_address': 'Boutique B, Bobo-Dioulasso',
          'delivery_address_line': 'Secteur 5',
          'delivery_city': 'Bobo-Dioulasso',
          'delivery_latitude': '11.18',
          'delivery_longitude': '-4.29',
        },
        {
          'package_id': 'package-a',
          'status': 'ACCEPTED',
          'assigned_at': '2026-11-15T09:00:00Z',
          'shop_address': 'Boutique A, Bobo-Dioulasso',
          'delivery_address_line': 'Secteur 2',
          'delivery_city': 'Bobo-Dioulasso',
          'delivery_latitude': '11.17',
          'delivery_longitude': '-4.30',
        },
      ]);

      expect(stops, hasLength(4));
      expect(stops.map((stop) => stop.kind).toList(), [
        'PICKUP',
        'PICKUP',
        'DROPOFF',
        'DROPOFF',
      ]);
      expect(stops.map((stop) => stop.sequence).toList(), [1, 2, 3, 4]);
      expect(stops[0].packageId, 'package-a');
      expect(stops[1].packageId, 'package-b');
      expect(stops[2].packageId, 'package-a');
      expect(stops[3].packageId, 'package-b');
    });

    test('marks pickup stops already completed for picked-up packages', () {
      final stops = CourierRoutePlan.build([
        {
          'package_id': 'package-a',
          'status': 'IN_TRANSIT',
          'shop_address': 'Boutique A',
          'delivery_address_line': 'Secteur 2',
        },
      ]);

      expect(stops.first.completed, isTrue);
      expect(stops.last.completed, isFalse);
    });

    test('ignores completed, cancelled and malformed assignments', () {
      final stops = CourierRoutePlan.build([
        {'package_id': 'package-done', 'status': 'DELIVERED'},
        {'package_id': 'package-cancelled', 'status': 'CANCELLED'},
        {'package_id': '', 'status': 'ASSIGNED'},
      ]);

      expect(stops, isEmpty);
    });
  });
}
