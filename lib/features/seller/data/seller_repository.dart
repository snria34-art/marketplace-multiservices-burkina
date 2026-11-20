import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/engine/marketplace_resilience.dart';

import 'seller_payout_validation.dart';

class SellerRepository {
  const SellerRepository(this.client, {this.resilience});

  final SupabaseClient client;
  final MarketplaceResilience? resilience;
  static final _fallbackResilience = MarketplaceResilience();
  MarketplaceResilience get _retry => resilience ?? _fallbackResilience;

  Future<T> _read<T>(Future<T> Function() operation) => _retry.read(operation);

  Future<List<Map<String, dynamic>>> dashboard() async {
    final raw = await _read(() => client.rpc('get_seller_dashboard'));

    if (raw is! List) return const [];

    return raw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String?> sellerId() async {
    final user = client.auth.currentUser;
    if (user == null) return null;

    final rows = await _read(() async => await client
        .from('sellers')
        .select('id')
        .eq('user_id', user.id)
        .limit(1));

    if ((rows as List).isEmpty) return null;
    final id = (rows.first as Map)['id']?.toString().trim();
    if (id == null || !isCanonicalUuid(id)) {
      throw StateError('seller_id_invalid');
    }
    return id;
  }

  Future<num> balance(String sellerId) async {
    const pageSize = 500;
    var lastId = 0;
    num total = 0;

    while (true) {
      final rows = await _read(() async => await client
          .from('seller_ledger')
          .select('id,amount')
          .eq('seller_id', sellerId)
          .gt('id', lastId)
          .order('id', ascending: true)
          .limit(pageSize));

      if (rows.isEmpty) break;

      for (final row in rows) {
        final entry = row as Map;
        final id = entry['id'];
        if (id is! num) {
          throw const FormatException('Identifiant de registre financier invalide.');
        }

        final amount = num.tryParse(entry['amount']?.toString() ?? '');
        if (amount == null) {
          throw const FormatException('Montant du registre financier invalide.');
        }

        total += amount;
        lastId = id.toInt();
      }

      if (rows.length < pageSize) break;
    }

    return total;
  }

  Future<String> requestPayout({
    required String sellerId,
    required num amount,
    required String provider,
  }) async {
    final issue = validateSellerPayoutRequest(
      sellerId: sellerId,
      amount: amount,
      provider: provider,
    );
    if (issue != null) throw StateError(issue);

    final raw = await client.rpc(
      'request_seller_payout_secure',
      params: {
        'p_seller_id': sellerId.trim(),
        'p_amount': amount,
        'p_provider': provider.trim().toUpperCase(),
      },
    );

    final payoutId = raw?.toString().trim() ?? '';
    if (!isValidSellerPayoutResponse(payoutId)) {
      // The server may have committed the request but returned an unexpected
      // response shape. Do not invite an automatic retry and risk duplication.
      throw StateError('payout_response_invalid');
    }
    return payoutId;
  }

  Future<List<Map<String, dynamic>>> payouts(String sellerId) async {
    final rows = await _read(() async => await client
        .from('seller_payouts')
        .select(
          'id,amount,currency,provider,status,requested_at,paid_at',
        )
        .eq('seller_id', sellerId)
        .order('requested_at', ascending: false)
        .limit(50));

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
