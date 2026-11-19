import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/core/engine/marketplace_resilience.dart';

void main() {
  group('MarketplaceResilience', () {
    test('retries safe reads with bounded exponential delays', () async {
      var calls = 0;
      final delays = <Duration>[];
      final resilience = MarketplaceResilience(
        wait: (duration) async => delays.add(duration),
      );

      final result = await resilience.run(
        () async {
          calls++;
          if (calls < 3) throw Exception('temporary');
          return 'ok';
        },
        retrySafe: true,
        isRetryable: (_) => true,
      );

      expect(result, 'ok');
      expect(calls, 3);
      expect(delays, const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
      ]);
      expect(resilience.consecutiveFailures, 0);
    });

    test('never retries a mutation when retrySafe is false', () async {
      var calls = 0;
      final resilience = MarketplaceResilience(
        wait: (_) async {},
      );

      await expectLater(
        resilience.run(
          () async {
            calls++;
            throw Exception('unknown mutation outcome');
          },
          retrySafe: false,
          isRetryable: (_) => true,
        ),
        throwsException,
      );

      expect(calls, 1);
    });

    test('opens circuit after consecutive failed operations', () async {
      var now = DateTime.utc(2026);
      final resilience = MarketplaceResilience(
        failureThreshold: 2,
        cooldown: const Duration(seconds: 10),
        clock: () => now,
        wait: (_) async {},
      );

      for (var i = 0; i < 2; i++) {
        await expectLater(
          resilience.run<String>(
            () async => throw Exception('offline'),
            retrySafe: false,
            isRetryable: (_) => true,
          ),
          throwsException,
        );
      }

      await expectLater(
        resilience.run(
          () async => 'should not run',
          retrySafe: true,
          isRetryable: (_) => true,
        ),
        throwsStateError,
      );

      now = now.add(const Duration(seconds: 11));
      expect(
        await resilience.run(
          () async => 'recovered',
          retrySafe: true,
          isRetryable: (_) => true,
        ),
        'recovered',
      );
      expect(resilience.consecutiveFailures, 0);
    });

    test('does not let an older normal operation close a half-open circuit', () async {
      var now = DateTime.utc(2026);
      final normalStarted = Completer<void>();
      final releaseNormal = Completer<void>();
      final probeStarted = Completer<void>();
      final releaseProbe = Completer<void>();
      final resilience = MarketplaceResilience(
        failureThreshold: 1,
        cooldown: const Duration(seconds: 1),
        clock: () => now,
        wait: (_) async {},
      );

      final normal = resilience.run(
        () async {
          normalStarted.complete();
          await releaseNormal.future;
          return 'normal';
        },
        retrySafe: true,
        isRetryable: (_) => true,
      );
      await normalStarted.future;

      await expectLater(
        resilience.run<String>(
          () async => throw Exception('open circuit'),
          retrySafe: false,
          isRetryable: (_) => true,
        ),
        throwsException,
      );

      now = now.add(const Duration(seconds: 2));
      final probe = resilience.run(
        () async {
          probeStarted.complete();
          await releaseProbe.future;
          return 'probe';
        },
        retrySafe: true,
        isRetryable: (_) => true,
      );
      await probeStarted.future;

      releaseNormal.complete();
      expect(await normal, 'normal');

      // Completion of the older request must not reset the circuit or unlock
      // the dedicated probe.
      await expectLater(
        resilience.run(
          () async => 'must be blocked',
          retrySafe: true,
          isRetryable: (_) => true,
        ),
        throwsStateError,
      );

      releaseProbe.complete();
      expect(await probe, 'probe');
      expect(resilience.consecutiveFailures, 0);
    });

    test('times out stalled operations within the configured bound', () async {
      final resilience = MarketplaceResilience(
        operationTimeout: const Duration(milliseconds: 5),
        wait: (_) async {},
      );

      await expectLater(
        resilience.run(
          () async => Future<void>.delayed(const Duration(seconds: 1)),
          retrySafe: false,
          isRetryable: (_) => true,
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('does not retry non-retryable failures', () async {
      var calls = 0;
      final resilience = MarketplaceResilience(wait: (_) async {});

      await expectLater(
        resilience.run(
          () async {
            calls++;
            throw ArgumentError('invalid input');
          },
          retrySafe: true,
          isRetryable: (_) => false,
        ),
        throwsArgumentError,
      );

      expect(calls, 1);
    });
  });
}
