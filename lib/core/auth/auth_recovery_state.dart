import 'package:flutter/foundation.dart';

/// Tracks whether Supabase Auth explicitly emitted a password-recovery event.
///
/// A normal signed-in session is not sufficient to open the password update
/// form. The form becomes available only after the recovery callback event.
class AuthRecoveryState {
  AuthRecoveryState._();

  static final ValueNotifier<bool> pending = ValueNotifier<bool>(false);

  static void activate() {
    pending.value = true;
  }

  static void clear() {
    pending.value = false;
  }
}
