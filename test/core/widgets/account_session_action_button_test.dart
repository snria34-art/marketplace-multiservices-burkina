import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marketplace_multiservices_burkina/core/providers/repository_providers.dart';
import 'package:marketplace_multiservices_burkina/core/widgets/account_session_action_button.dart';

void main() {
  testWidgets(
    'shows a sign-in action when Supabase is not configured',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  AccountSessionActionButton(),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Se connecter'), findsOneWidget);

      await tester.tap(find.byTooltip('Se connecter'));
      await tester.pump();

      expect(
        find.text('Le service de connexion est indisponible.'),
        findsOneWidget,
      );
    },
  );
}
