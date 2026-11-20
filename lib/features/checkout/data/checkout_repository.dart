import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/payment_provider_availability.dart';

class CheckoutRepository {
  const CheckoutRepository(this.client);

  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> addresses() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];

    final rows = await client
        .from('delivery_addresses')
        .select(
          'id,label,recipient_name,phone,address_line,city,latitude,longitude,is_default,created_at',
        )
        .eq('customer_id', user.id)
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);

    return _maps(rows);
  }

  Future<Map<String, dynamic>> createAddress({
    String? label,
    required String recipientName,
    String? phone,
    String? addressLine,
    String? city,
    double? latitude,
    double? longitude,
    bool isDefault = false,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Vous devez être connecté.');
    }

    final row = await client
        .from('delivery_addresses')
        .insert({
          'customer_id': user.id,
          'label': label,
          'recipient_name': recipientName,
          'phone': phone,
          'address_line': addressLine,
          'city': city,
          'latitude': latitude,
          'longitude': longitude,
          'is_default': isDefault,
        })
        .select(
          'id,label,recipient_name,phone,address_line,city,latitude,longitude,is_default,created_at',
        )
        .single();

    return Map<String, dynamic>.from(row);
  }

  Future<Map<String, dynamic>> calculateDeliveryFee({
    required String cartId,
    required Map<String, dynamic> address,
  }) async {
    final raw = await client.rpc(
      'calculate_delivery_fee',
      params: {
        'p_cart_id': cartId,
        'p_delivery_address': {
          'id': address['id'],
          'latitude': address['latitude'],
          'longitude': address['longitude'],
        },
      },
    );

    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }

    throw StateError('Le devis de livraison est invalide.');
  }

  /// Checks provider credentials before creating an order or reserving stock.
  ///
  /// The Edge Function returns only a boolean; provider secrets never reach
  /// the mobile client.
  Future<void> ensurePaymentProviderConfigured({
    required String provider,
  }) async {
    final normalized = provider.trim().toUpperCase();
    if (normalized != 'WAVE' && normalized != 'CINETPAY') {
      throw StateError('Mode de paiement non pris en charge.');
    }

    final response = await client.functions.invoke(
      'check-payment-provider-config',
      body: {'provider': normalized},
    );

    final availability =
        PaymentProviderAvailability.fromResponse(response.data);
    if (availability.provider != normalized) {
      throw StateError('La réponse du fournisseur de paiement est incohérente.');
    }
    if (!availability.configured) {
      throw StateError(availability.unavailableMessage);
    }
  }

  Future<String> checkout({
    required String cartId,
    required String addressId,
    required num deliveryFee,
    String? couponCode,
    required String idempotencyKey,
    String deliveryPlaceType = 'HOME',
    DateTime? scheduledDeliveryAt,
    String? deliveryInstructions,
  }) async {
    final raw = await client.rpc(
      'checkout_cart',
      params: {
        'p_cart_id': cartId,
        'p_delivery_address': {
          'id': addressId,
          'delivery_place_type': deliveryPlaceType,
          if (scheduledDeliveryAt != null)
            'scheduled_delivery_at': scheduledDeliveryAt.toUtc().toIso8601String(),
          if (deliveryInstructions != null && deliveryInstructions.trim().isNotEmpty)
            'delivery_instructions': deliveryInstructions.trim(),
        },
        'p_delivery_fee': deliveryFee,
        'p_coupon_code': couponCode,
        'p_idempotency_key': idempotencyKey,
      },
    );

    return raw.toString();
  }

  Future<Map<String, dynamic>> createPaymentSession({
    required String orderId,
    required String provider,
  }) async {
    if (provider == 'WAVE') {
      final response = await client.functions.invoke(
        'create-wave-payment-session-v3',
        body: {'order_id': orderId},
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } else if (provider == 'CINETPAY') {
      final response = await client.functions.invoke(
        'create-cinetpay-payment-session-v3',
        body: {
          'order_id': orderId,
          'provider': 'CINETPAY',
        },
      );
      if (response.data is Map) {
        return Map<String, dynamic>.from(response.data as Map);
      }
    } else {
      throw StateError('Mode de paiement non pris en charge.');
    }

    throw StateError('Réponse de paiement invalide.');
  }

  Future<List<Map<String, dynamic>>> orders({
    int limit = 20,
    int offset = 0,
  }) async {
    final raw = await client.rpc(
      'get_my_orders_with_completion',
      params: {
        'p_limit': limit,
        'p_offset': offset,
      },
    );

    return _maps(raw);
  }

  List<Map<String, dynamic>> _maps(dynamic rows) {
    if (rows is! List) return const [];

    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
