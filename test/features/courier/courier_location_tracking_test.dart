import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:marketplace_multiservices_burkina/core/providers/repository_providers.dart';
import 'package:marketplace_multiservices_burkina/features/courier/data/courier_repository.dart';
import 'package:marketplace_multiservices_burkina/features/courier/presentation/courier_page.dart';

class _NoMissionCourierRepository extends CourierRepository {
  _NoMissionCourierRepository(super.client);

  @override
  Future<List<Map<String, dynamic>>> assignments() async => const [];
}

 
class _ResumeCourierRepository extends CourierRepository {
  _ResumeCourierRepository(super.client);

  var _calls = 0;
  int get calls => _calls;

  @override
  Future<List<Map<String, dynamic>>> assignments() async {
    _calls++;
    if (_calls == 1) {
      return [
        {
          'assignment_id': 'assignment-1',
          'package_id': 'package-1',
          'status': 'ASSIGNED',
          'assigned_at': '2026-11-16T08:00:00Z',
          'shop_address': 'Boutique de test',
          'delivery_address_line': 'Secteur 1',
          'delivery_city': 'Bobo-Dioulasso',
        },
      ];
    }
    return const [];
  }
}

void main() {
  testWidgets(
    'does not request GPS permission when the courier has no active mission',
    (tester) async {
      final testClient = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(null),
            courierRepositoryProvider.overrideWithValue(
              _NoMissionCourierRepository(testClient),
            ),
          ],
          child: const MaterialApp(
            home: CourierPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(repository.calls, 2);
      expect(find.text('Aucune livraison affectée.'), findsOneWidget);

      await tester.tap(find.byTooltip('Partager ma position'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Aucune mission active : la position ne peut pas être partagée.',
        ),
        findsOneWidget,
      );
      expect(find.text('Autoriser le suivi'), findsNothing);
      expect(find.text('Partager votre position'), findsNothing);
    },
  );
  testWidgets(
    'refreshes courier assignments after the app resumes',
    (tester) async {
      final testClient = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final repository = _ResumeCourierRepository(testClient);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(null),
            courierRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(home: CourierPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Colis package-1'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Aucune livraison affectée.'), findsOneWidget);
      expect(find.text('Colis package-1'), findsNothing);
    },
  );

}
