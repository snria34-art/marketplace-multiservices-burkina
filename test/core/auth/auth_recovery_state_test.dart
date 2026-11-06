import 'package:flutter_test/flutter_test.dart';

import 'package:marketplace_multiservices_burkina/core/auth/auth_recovery_state.dart';

void main() {
  setUp(AuthRecoveryState.clear);

  tearDown(AuthRecoveryState.clear);

  test('recovery form is closed until a password recovery event arrives', () {
    expect(AuthRecoveryState.pending.value, isFalse);
  });

  test('password recovery event activates the recovery form', () {
    AuthRecoveryState.activate();

    expect(AuthRecoveryState.pending.value, isTrue);
  });

  test('recovery form closes after a password update completes', () {
    AuthRecoveryState.activate();
    AuthRecoveryState.clear();

    expect(AuthRecoveryState.pending.value, isFalse);
  });
}
