import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/engine/marketplace_resilience.dart';

class NotificationRepository {
  const NotificationRepository(this.client, {this.resilience});

  final SupabaseClient client;
  final MarketplaceResilience? resilience;
  static final _fallbackResilience = MarketplaceResilience();
  MarketplaceResilience get _retry => resilience ?? _fallbackResilience;

  Future<T> _read<T>(Future<T> Function() operation) => _retry.read(operation);

  Future<List<Map<String, dynamic>>> list({int limit = 100}) async {
    final user = client.auth.currentUser;
    if (user == null) return const [];
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'Doit être compris entre 1 et 200.');
    }

    final rows = await _read(() async => await client
        .from('notifications')
        .select('id,type,title,body,data,read_at,created_at')
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .limit(limit));

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> markRead(String notificationId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');
    final id = notificationId.trim();
    if (id.isEmpty) throw ArgumentError.value(notificationId, 'notificationId');

    await client
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .eq('user_id', user.id);
  }
}
