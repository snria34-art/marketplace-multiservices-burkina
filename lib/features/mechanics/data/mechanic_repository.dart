import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/engine/marketplace_resilience.dart';

class MechanicRepository {
  const MechanicRepository(this.client, {this.resilience});

  final SupabaseClient client;
  final MarketplaceResilience? resilience;
  static final _fallbackResilience = MarketplaceResilience();
  MarketplaceResilience get _retry => resilience ?? _fallbackResilience;

  Future<T> _read<T>(Future<T> Function() operation) => _retry.read(operation);

  Future<List<Map<String, dynamic>>> mechanics() async {
    final rows = await _read(() => client.rpc('get_public_mechanics'));

    return (rows as List).map((row) {
      final item = Map<String, dynamic>.from(row as Map);
      final services = item['services'];
      item['mechanic_services'] = services is List ? services : const <dynamic>[];
      item['mechanic_availability'] = [
        <String, dynamic>{
          'status': item['availability_status'],
          'starts_at': item['availability_starts_at'],
          'ends_at': item['availability_ends_at'],
        },
      ];
      return item;
    }).toList();
  }

  Future<String> createRequest({
    required String vehicleType,
    required String problemType,
    String? description,
    required double latitude,
    required double longitude,
  }) async {
    final raw = await client.rpc(
      'create_mechanic_request',
      params: {
        'p_vehicle_type': vehicleType,
        'p_problem_type': problemType,
        'p_description': description,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );

    return raw.toString();
  }

  Future<List<Map<String, dynamic>>> myQuotes() async {
    final rows = await _read(() async => await client
        .from('mechanic_quotes')
        .select(
          'id,request_id,mechanic_id,amount,currency,diagnosis,status,expires_at,created_at,mechanics(display_name,phone)',
        )
        .order('created_at', ascending: false)
        .limit(50));

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<String> acceptQuote(String quoteId) async {
    final raw = await client.rpc(
      'accept_mechanic_quote',
      params: {'p_quote_id': quoteId},
    );
    return raw.toString();
  }
}
