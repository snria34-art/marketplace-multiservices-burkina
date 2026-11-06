import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:marketplace_multiservices_burkina/core/providers/repository_providers.dart';
import 'package:marketplace_multiservices_burkina/features/courier/data/courier_repository.dart';
import 'package:marketplace_multiservices_burkina/features/courier/presentation/courier_page.dart';

class _NoMissionCourierRepository extends CourierRepository {
  _NoMissionCourierRepository()
      : super(SupabaseClient('http://localhost:54321', 'test-anon-key'));

  @override
  Future<List<Map<String, dynamic>>> assignments() async => const [];
}

void main() {
  testWidgets(
    'does not request GPS permission when the courier has no active mission',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(null),
            courierRepositoryProvider.overrideWithValue(
              _NoMissionCourierRepository(),
            ),
          ],
          child: const MaterialApp(
            home: CourierPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

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
}
