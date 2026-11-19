import 'dart:async';

/// Bounded retry + circuit breaker for idempotent backend reads.
///
/// Never use automatic retries for checkout, payment, refund, payout or any
/// other mutation unless the server operation has an idempotency key.
class MarketplaceResilience {
  MarketplaceResilience({
    this.failureThreshold = 4,
    this.cooldown = const Duration(seconds: 20),
    this.baseDelay = const Duration(milliseconds: 250),
    this.maxDelay = const Duration(seconds: 3),
    this.operationTimeout = const Duration(seconds: 15),
    DateTime Function()? clock,
    Future<void> Function(Duration)? wait,
  })  : assert(failureThreshold > 0),
        assert(operationTimeout > Duration.zero),
        _clock = clock ?? DateTime.now,
        _wait = wait ?? Future<void>.delayed;

  final int failureThreshold;
  final Duration cooldown;
  final Duration baseDelay;
  final Duration maxDelay;
  final Duration operationTimeout;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _wait;

  int _consecutiveFailures = 0;
  DateTime? _openedAt;
  bool _probeInFlight = false;

  bool get isOpen {
    final openedAt = _openedAt;
    return openedAt != null && _clock().difference(openedAt) < cooldown;
  }

  int get consecutiveFailures => _consecutiveFailures;

  /// Executes an idempotent operation with bounded exponential backoff.
  /// The caller must explicitly classify retryable errors.
  Future<T> run<T>(
    Future<T> Function() operation, {
    required bool retrySafe,
    required bool Function(Object error) isRetryable,
    int maxAttempts = 3,
  }) async {
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'Must be >= 1');
    }

    var ownsProbe = false;
    final openedAt = _openedAt;
    if (openedAt != null) {
      if (_clock().difference(openedAt) < cooldown) {
        throw StateError('Service temporairement indisponible (circuit ouvert).');
      }
      if (_probeInFlight) {
        throw StateError('Vérification de disponibilité déjà en cours.');
      }
      _probeInFlight = true;
      ownsProbe = true;
    }

    try {
      final attempts = retrySafe ? maxAttempts : 1;
      for (var attempt = 1; attempt <= attempts; attempt++) {
        try {
          final result = await operation().timeout(operationTimeout);
          _consecutiveFailures = 0;
          _openedAt = null;
          return result;
        } catch (error) {
          final canRetry = retrySafe &&
              attempt < attempts &&
              isRetryable(error);
          if (!canRetry) {
            _recordFailure();
            rethrow;
          }
          await _wait(_backoff(attempt));
        }
      }
      throw StateError('Échec inattendu de la politique de reprise.');
    } finally {
      // A normal operation that started before the circuit opened must not
      // release a half-open probe lock owned by a different operation.
      if (ownsProbe) _probeInFlight = false;
    }
  }

  Duration _backoff(int attempt) {
    var milliseconds = baseDelay.inMilliseconds;
    for (var i = 1; i < attempt && milliseconds < maxDelay.inMilliseconds; i++) {
      milliseconds = (milliseconds * 2).clamp(0, maxDelay.inMilliseconds).toInt();
    }
    return Duration(
      milliseconds: milliseconds.clamp(0, maxDelay.inMilliseconds).toInt(),
    );
  }

  void _recordFailure() {
    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold) {
      _openedAt = _clock();
    }
  }

  /// Reset after an operator-confirmed recovery or a successful health check.
  void reset() {
    _consecutiveFailures = 0;
    _openedAt = null;
    // Do not unlock an active half-open probe from another in-flight call.
  }
}
