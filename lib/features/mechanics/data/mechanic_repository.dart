import 'package:supabase_flutter/supabase_flutter.dart';

class MechanicRepository {
  const MechanicRepository(this.client);

  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> mechanics() async {
    final rows = await client.rpc('get_public_mechanics_v2');

    return (rows as List).map((row) {
      final item = Map<String, dynamic>.from(row as Map);
      final services = item['services'];
      item['mechanic_services'] = services is List ? services : const <dynamic>[];
      item['service_open_time'] = item['service_open_time'];
      item['service_close_time'] = item['service_close_time'];
      item['service_days'] = item['service_days'];
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
    required String serviceLocationType,
    required String problemType,
    String? description,
    String? locationNote,
    required double latitude,
    required double longitude,
  }) async {
    final raw = await client.rpc(
      'create_mechanic_request_v2',
      params: {
        'p_vehicle_type': vehicleType,
        'p_service_location_type': serviceLocationType,
        'p_problem_type': problemType,
        'p_description': description,
        'p_location_note': locationNote,
        'p_latitude': latitude,
        'p_longitude': longitude,
      },
    );

    return raw.toString();
  }


  Future<void> saveServiceProfile({
    required List<String> vehicleTypes,
    required String openTime,
    required String closeTime,
    required List<int> serviceDays,
    required num homePrice,
    required num officePrice,
    required num roadsidePrice,
    String? adjustmentNote,
  }) async {
    await client.rpc(
      'save_mechanic_service_profile',
      params: {
        'p_vehicle_types': vehicleTypes,
        'p_open_time': openTime,
        'p_close_time': closeTime,
        'p_service_days': serviceDays,
        'p_home_price': homePrice,
        'p_office_price': officePrice,
        'p_roadside_price': roadsidePrice,
        'p_adjustment_note': adjustmentNote,
      },
    );
  }

  Future<List<Map<String, dynamic>>> myQuotes() async {
    final rows = await client
        .from('mechanic_quotes')
        .select(
          'id,request_id,mechanic_id,amount,currency,diagnosis,status,expires_at,created_at,mechanics(display_name,phone)',
        )
        .order('created_at', ascending: false)
        .limit(50);

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
