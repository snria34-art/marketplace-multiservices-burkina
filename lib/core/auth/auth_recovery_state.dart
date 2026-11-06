import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks whether Supabase Auth explicitly emitted a password-recovery event.
///
/// A normal signed-in session is not sufficient to open the password update
/// form. The form becomes available only after the recovery callback event.
class AuthRecoveryState {
  AuthRecoveryState._();

  static final ValueNotifier<bool> pending = ValueNotifier<bool>(false);
  static StreamSubscription<AuthState>? _subscription;

  static void attach(SupabaseClient? client) {
    if (client == null || _subscription != null) return;

    _subscription = client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          activate();
        } else if (data.event == AuthChangeEvent.signedOut) {
          clear();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        // Do not log credentials or recovery URLs. The recovery screen stays
        // closed when the event stream cannot confirm a recovery flow.
      },
    );
  }

  static void activate() {
    pending.value = true;
  }

  static void clear() {
    pending.value = false;
  }
}
