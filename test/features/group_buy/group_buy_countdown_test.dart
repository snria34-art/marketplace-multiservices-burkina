import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marketplace_multiservices_burkina/features/group_buy/presentation/group_buy_countdown.dart';

void main() {
  testWidgets('shows elapsed time and the remaining countdown for an active group',
      (tester) async {
    final now = DateTime.now().toUtc();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupBuyCountdown(
            startsAt: now.subtract(const Duration(minutes: 8)),
            endsAt: now.add(const Duration(hours: 2, minutes: 3)),
          ),
        ),
      ),
    );

    expect(find.textContaining('commencé il y a'), findsOneWidget);
    expect(find.textContaining('Se termine dans'), findsOneWidget);
  });

  testWidgets('shows the ended state after the group deadline', (tester) async {
    final now = DateTime.now().toUtc();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupBuyCountdown(
            startsAt: now.subtract(const Duration(hours: 2)),
            endsAt: now.subtract(const Duration(seconds: 1)),
          ),
        ),
      ),
    );

    expect(find.text('Regroupage terminé'), findsOneWidget);
  });

  testWidgets('supports a compact countdown strip', (tester) async {
    final now = DateTime.now().toUtc();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupBuyCountdown(
            startsAt: now.subtract(const Duration(minutes: 1)),
            endsAt: now.add(const Duration(minutes: 10)),
            compact: true,
          ),
        ),
      ),
    );

    expect(find.byType(Container), findsOneWidget);
    expect(find.textContaining('Se termine dans'), findsOneWidget);
  });
}
