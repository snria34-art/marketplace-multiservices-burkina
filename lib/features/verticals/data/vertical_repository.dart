import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/media/upload_media_validator.dart';
import '../../../core/engine/marketplace_resilience.dart';

enum VerticalModule {
  rides,
  rentals,
  realEstate,
  accommodations,
  events,
  jobs,
  professionals,
  agriculture,
  freight,
  health,
  beauty,
  homeServices,
  digital,
  training,
  creative,
  parcels,
}

class VerticalConfig {
  const VerticalConfig({
    required this.table,
    required this.title,
    required this.icon,
    required this.select,
    this.ownOnly = false,
    this.ownUserColumn = 'customer_id',
  });

  final String table;
  final String title;
  final int icon;
  final String select;
  final bool ownOnly;
  final String ownUserColumn;
}

class VerticalRepository {
  const VerticalRepository(this.client, {this.resilience});

  final SupabaseClient client;
  final MarketplaceResilience? resilience;
  static final _fallbackResilience = MarketplaceResilience();
  MarketplaceResilience get _retry => resilience ?? _fallbackResilience;

  Future<T> _read<T>(Future<T> Function() operation) => _retry.read(operation);

  static const configs = <VerticalModule, VerticalConfig>{
    VerticalModule.rides: VerticalConfig(
      table: 'ride_requests',
      title: 'Taxi / Moto / Déplacements',
      icon: 0,
      select: 'id,pickup,destination,status,fare_estimate,created_at',
      ownOnly: true,
    ),
    VerticalModule.rentals: VerticalConfig(
      table: 'vehicle_rentals',
      title: 'Location de véhicules',
      icon: 1,
      select: 'id,vehicle_type,brand,model,daily_price,deposit_amount,active,verification_status,service_providers(display_name)',
    ),
    VerticalModule.realEstate: VerticalConfig(
      table: 'real_estate_listings',
      title: 'Immobilier',
      icon: 2,
      select: 'id,listing_type,title,description,price,city,address,latitude,longitude,bedrooms,bathrooms,area_m2',
    ),
    VerticalModule.accommodations: VerticalConfig(
      table: 'accommodations',
      title: 'Hôtels & Hébergements',
      icon: 3,
      select: 'id,name,accommodation_type,description,address,latitude,longitude,accommodation_units(id,name,capacity,price_per_night,quantity,active)',
    ),
    VerticalModule.events: VerticalConfig(
      table: 'events',
      title: 'Événements & Billets',
      icon: 4,
      select: 'id,title,description,venue,starts_at,ends_at,capacity,ticket_price,active',
    ),
    VerticalModule.jobs: VerticalConfig(
      table: 'jobs',
      title: 'Emplois',
      icon: 5,
      select: 'id,title,description,location,active,created_at',
    ),
    VerticalModule.professionals: VerticalConfig(
      table: 'professional_profiles',
      title: 'Professionnels',
      icon: 6,
      select: 'id,profession,experience_years,service_area,bio,hourly_rate,active,service_providers(display_name)',
    ),
    VerticalModule.agriculture: VerticalConfig(
      table: 'agriculture_listings',
      title: 'Agriculture',
      icon: 7,
      select: 'id,seller_id,listing_type,name,description,price,unit,quantity,reserved_quantity,active,created_at',
    ),
    VerticalModule.freight: VerticalConfig(
      table: 'freight_requests',
      title: 'Fret & Marchandises',
      icon: 8,
      select: 'id,pickup,delivery,weight_kg,volume_m3,description,status,created_at',
      ownOnly: true,
    ),
    VerticalModule.health: VerticalConfig(
      table: 'health_products',
      title: 'Santé',
      icon: 9,
      select: 'id,name,description,price,requires_prescription,stock_quantity,active,health_providers(provider_id,provider_type,verified)',
    ),
    VerticalModule.beauty: VerticalConfig(
      table: 'beauty_services',
      title: 'Beauté & Coiffure',
      icon: 10,
      select: 'id,name,description,duration_minutes,price,active,service_providers(display_name)',
    ),
    VerticalModule.homeServices: VerticalConfig(
      table: 'home_services',
      title: 'Services à domicile',
      icon: 11,
      select: 'id,service_type,name,description,starting_price,active,service_providers(display_name)',
    ),
    VerticalModule.digital: VerticalConfig(
      table: 'digital_services',
      title: 'Services numériques',
      icon: 12,
      select: 'id,category,name,description,price,active,service_providers(display_name)',
    ),
    VerticalModule.training: VerticalConfig(
      table: 'training_courses',
      title: 'Formations',
      icon: 13,
      select: 'id,title,description,price,active,service_providers(display_name)',
    ),
    VerticalModule.creative: VerticalConfig(
      table: 'creative_services',
      title: 'Créatifs',
      icon: 14,
      select: 'id,category,name,description,starting_price,active',
    ),
    VerticalModule.parcels: VerticalConfig(
      table: 'parcels',
      title: 'Colis & Points relais',
      icon: 15,
      select: 'id,recipient_name,recipient_phone,pickup_address,delivery_address,weight_kg,status,tracking_code,created_at',
      ownOnly: true,
      ownUserColumn: 'sender_id',
    ),
  };

  Future<List<Map<String, dynamic>>> list(VerticalModule module) async {
    final config = configs[module]!;
    if (module == VerticalModule.health) {
      final rows = await _read(() => client.rpc('get_public_health_products'));
      return _maps(rows);
    }
    if (module == VerticalModule.agriculture) {
      final rows = await _read(() => client.rpc('get_public_agriculture_listings'));
      return _maps(rows);
    }
    if (config.ownOnly) {
      final user = client.auth.currentUser;
      if (user == null) return const [];
      final rows = await _read(() async => await client
          .from(config.table)
          .select(config.select)
          .eq(config.ownUserColumn, user.id)
          .order('created_at', ascending: false)
          .limit(100));
      return _maps(rows);
    }

    final rows = await _read(() async => await client
        .from(config.table)
        .select(config.select)
        .limit(100));
    return _maps(rows);
  }

  Future<String> createRide({
    required Map<String, dynamic> pickup,
    required Map<String, dynamic> destination,
  }) async =>
      (await client.rpc(
        'create_ride_request',
        params: {'p_pickup': pickup, 'p_destination': destination},
      ))
          .toString();

  Future<String> reserveEvent({
    required String eventId,
    required int quantity,
  }) async =>
      (await client.rpc(
        'reserve_event_ticket',
        params: {'p_event_id': eventId, 'p_quantity': quantity},
      ))
          .toString();

  Future<String> bookRental({
    required String rentalId,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async =>
      (await client.rpc(
        'create_vehicle_rental_booking',
        params: {
          'p_rental_id': rentalId,
          'p_starts_at': startsAt.toUtc().toIso8601String(),
          'p_ends_at': endsAt.toUtc().toIso8601String(),
        },
      ))
          .toString();

  Future<String> bookAccommodation({
    required String unitId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int guests,
  }) async =>
      (await client.rpc(
        'create_accommodation_booking',
        params: {
          'p_unit_id': unitId,
          'p_check_in': _date(checkIn),
          'p_check_out': _date(checkOut),
          'p_guests': guests,
        },
      ))
          .toString();

  Future<String> enrollTraining(String courseId) async =>
      (await client.rpc(
        'enroll_training_course',
        params: {'p_course_id': courseId},
      ))
          .toString();

  Future<String> orderDigital(String serviceId) async =>
      (await client.rpc(
        'create_digital_order',
        params: {'p_service_id': serviceId},
      ))
          .toString();

  Future<String> bookBeauty({
    required String serviceId,
    required DateTime scheduledAt,
  }) async =>
      (await client.rpc(
        'create_beauty_booking',
        params: {
          'p_service_id': serviceId,
          'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
        },
      ))
          .toString();

  Future<String> requestHomeService({
    required String serviceId,
    required DateTime scheduledAt,
    required Map<String, dynamic> address,
  }) async =>
      (await client.rpc(
        'create_home_service_request',
        params: {
          'p_service_id': serviceId,
          'p_scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'p_address': address,
        },
      ))
          .toString();

  Future<String> requestCreativeBooking({
    required String serviceId,
    DateTime? scheduledAt,
  }) async =>
      (await client.rpc(
        'request_creative_booking',
        params: {
          'p_service_id': serviceId,
          'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        },
      ))
          .toString();

  Future<void> cancelCreativeBooking(String bookingId) async {
    await client.rpc(
      'cancel_creative_booking',
      params: {'p_booking_id': bookingId},
    );
  }

  Future<List<Map<String, dynamic>>> myCreativeBookings() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];

    final rows = await _read(() async => await client
        .from('creative_bookings')
        .select(
          'id,service_id,scheduled_at,status,agreed_amount,creative_services(name,category)',
        )
        .eq('customer_id', user.id)
        .limit(100));

    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> providerCreativeBookings() async {
    final rows = await _read(() => client.rpc('get_provider_creative_bookings'));
    return _maps(rows);
  }

  Future<void> respondCreativeBooking({
    required String bookingId,
    required String decision,
    num? agreedAmount,
  }) async {
    await client.rpc(
      'respond_creative_booking',
      params: {
        'p_booking_id': bookingId,
        'p_decision': decision,
        'p_agreed_amount': agreedAmount,
      },
    );
  }

  Future<String> requestRealEstateVisit({
    required String listingId,
    DateTime? preferredVisitAt,
    String? message,
  }) async =>
      (await client.rpc(
        'request_real_estate_visit',
        params: {
          'p_listing_id': listingId,
          'p_preferred_visit_at':
              preferredVisitAt?.toUtc().toIso8601String(),
          'p_message': message?.trim().isEmpty == true ? null : message?.trim(),
        },
      ))
          .toString();

  Future<void> cancelRealEstateVisit(String requestId) async {
    await client.rpc(
      'cancel_real_estate_visit',
      params: {'p_request_id': requestId},
    );
  }

  Future<List<Map<String, dynamic>>> myRealEstateVisitRequests() async {
    final rows = await _read(() => client.rpc('get_my_real_estate_visit_requests'));
    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> providerRealEstateVisitRequests() async {
    final rows = await _read(() => client.rpc('get_provider_real_estate_visit_requests'));
    return _maps(rows);
  }

  Future<void> respondRealEstateVisit({
    required String requestId,
    required String decision,
  }) async {
    await client.rpc(
      'respond_real_estate_visit',
      params: {
        'p_request_id': requestId,
        'p_decision': decision,
      },
    );
  }

  Future<String> createProfessionalServiceRequest({
    required String professionalProfileId,
    required String description,
    DateTime? scheduledAt,
  }) async =>
      (await client.rpc(
        'create_professional_service_request',
        params: {
          'p_professional_profile_id': professionalProfileId,
          'p_description': description,
          'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        },
      ))
          .toString();

  Future<void> cancelProfessionalServiceRequest(String requestId) async {
    await client.rpc(
      'cancel_professional_service_request',
      params: {'p_request_id': requestId},
    );
  }

  Future<List<Map<String, dynamic>>> myProfessionalServiceRequests() async {
    final rows = await _read(() => client.rpc('get_my_professional_service_requests'));
    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> providerProfessionalServiceRequests() async {
    final rows = await _read(() => client.rpc('get_provider_professional_service_requests'));
    return _maps(rows);
  }

  Future<String> createProfessionalServiceQuote({
    required String requestId,
    required num amount,
    String? message,
  }) async =>
      (await client.rpc(
        'create_professional_service_quote',
        params: {
          'p_request_id': requestId,
          'p_amount': amount,
          'p_message': message?.trim().isEmpty == true ? null : message?.trim(),
        },
      ))
          .toString();

  Future<void> respondProfessionalServiceQuote({
    required String quoteId,
    required String decision,
  }) async {
    await client.rpc(
      'respond_professional_service_quote',
      params: {
        'p_quote_id': quoteId,
        'p_decision': decision,
      },
    );
  }

  Future<String> createAgricultureListing({
    required String listingType,
    required String name,
    String? description,
    required num price,
    required String unit,
    required num quantity,
  }) async =>
      (await client.rpc(
        'create_agriculture_listing',
        params: {
          'p_listing_type': listingType,
          'p_name': name,
          'p_description': description,
          'p_price': price,
          'p_unit': unit,
          'p_quantity': quantity,
        },
      ))
          .toString();

  Future<void> updateAgricultureListing({
    required String listingId,
    required String listingType,
    required String name,
    String? description,
    required num price,
    required String unit,
    required num quantity,
    required bool active,
  }) async {
    await client.rpc(
      'update_agriculture_listing',
      params: {
        'p_listing_id': listingId,
        'p_listing_type': listingType,
        'p_name': name,
        'p_description': description,
        'p_price': price,
        'p_unit': unit,
        'p_quantity': quantity,
        'p_active': active,
      },
    );
  }

  Future<List<Map<String, dynamic>>> myAgricultureListings() async {
    final rows = await _read(() => client.rpc('get_my_agriculture_listings'));
    return _maps(rows);
  }

  Future<String> createAgricultureOrderRequest({
    required String listingId,
    required num quantity,
  }) async =>
      (await client.rpc(
        'create_agriculture_order_request',
        params: {
          'p_listing_id': listingId,
          'p_quantity': quantity,
        },
      ))
          .toString();

  Future<void> cancelAgricultureOrderRequest(String orderId) async {
    await client.rpc(
      'cancel_agriculture_order_request',
      params: {'p_order_id': orderId},
    );
  }

  Future<List<Map<String, dynamic>>> myAgricultureOrderRequests() async {
    final rows = await _read(() => client.rpc('get_my_agriculture_order_requests'));
    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> sellerAgricultureOrderRequests() async {
    final rows = await _read(() => client.rpc('get_seller_agriculture_order_requests'));
    return _maps(rows);
  }

  Future<void> respondAgricultureOrderRequest({
    required String orderId,
    required String decision,
  }) async {
    await client.rpc(
      'respond_agriculture_order_request',
      params: {
        'p_order_id': orderId,
        'p_decision': decision,
      },
    );
  }

  Future<void> fulfillAgricultureOrderRequest(String orderId) async {
    await client.rpc(
      'fulfill_agriculture_order_request',
      params: {'p_order_id': orderId},
    );
  }

  Future<String> createHealthProduct({
    required String name,
    String? description,
    required num price,
    required bool requiresPrescription,
    required int stockQuantity,
  }) async =>
      (await client.rpc(
        'create_health_product',
        params: {
          'p_name': name,
          'p_description': description,
          'p_price': price,
          'p_requires_prescription': requiresPrescription,
          'p_stock_quantity': stockQuantity,
        },
      ))
          .toString();

  Future<void> updateHealthProduct({
    required String productId,
    required String name,
    String? description,
    required num price,
    required bool requiresPrescription,
    required int stockQuantity,
    required bool active,
  }) async {
    await client.rpc(
      'update_health_product',
      params: {
        'p_product_id': productId,
        'p_name': name,
        'p_description': description,
        'p_price': price,
        'p_requires_prescription': requiresPrescription,
        'p_stock_quantity': stockQuantity,
        'p_active': active,
      },
    );
  }

  Future<List<Map<String, dynamic>>> myHealthProducts() async {
    final rows = await _read(() => client.rpc('get_my_health_products'));
    return _maps(rows);
  }

  Future<String> createHealthOrderRequest({
    required String productId,
    required int quantity,
    Uint8List? prescriptionBytes,
    String? prescriptionMimeType,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('authentication_required');
    }

    String? prescriptionPath;
    if (prescriptionBytes != null) {
      final mimeType = prescriptionMimeType?.toLowerCase().trim();
      if (mimeType == null ||
          (mimeType != 'image/jpeg' && mimeType != 'image/png')) {
        throw ArgumentError.value(
          prescriptionMimeType,
          'prescriptionMimeType',
          'Only JPEG and PNG images are accepted.',
        );
      }
      if (prescriptionBytes.length > 10 * 1024 * 1024) {
        throw ArgumentError.value(
          prescriptionBytes.length,
          'prescriptionBytes',
          'Prescription photos must not exceed 10 MB.',
        );
      }
      UploadMediaValidator.requireMimeType(prescriptionBytes, mimeType);
      final extension = mimeType == 'image/png' ? 'png' : 'jpg';
      prescriptionPath = user.id +
          '/' +
          DateTime.now().microsecondsSinceEpoch.toString() +
          '.' +
          extension;

      await client.storage.from('health-prescriptions').uploadBinary(
            prescriptionPath,
            prescriptionBytes,
            fileOptions: FileOptions(
              contentType: mimeType,
              upsert: false,
            ),
          );
    }

    try {
      return (await client.rpc(
        'create_health_order_request',
        params: {
          'p_product_id': productId,
          'p_quantity': quantity,
          'p_prescription_path': prescriptionPath,
        },
      ))
          .toString();
    } catch (_) {
      if (prescriptionPath != null) {
        try {
          await client.storage
              .from('health-prescriptions')
              .remove([prescriptionPath]);
        } catch (_) {
          // Keep the original order error; orphan cleanup can be retried.
        }
      }
      rethrow;
    }
  }

  Future<void> cancelHealthOrderRequest(String requestId) async {
    await client.rpc(
      'cancel_health_order_request',
      params: {'p_request_id': requestId},
    );
  }

  Future<List<Map<String, dynamic>>> myHealthOrderRequests() async {
    final rows = await _read(() => client.rpc('get_my_health_order_requests'));
    return _maps(rows);
  }

  Future<List<Map<String, dynamic>>> pharmacyHealthOrderRequests() async {
    final rows = await _read(() => client.rpc('get_pharmacy_health_order_requests'));
    return _maps(rows);
  }

  Future<void> respondHealthOrderRequest({
    required String requestId,
    required String decision,
    String? reviewNote,
  }) async {
    await client.rpc(
      'respond_health_order_request',
      params: {
        'p_request_id': requestId,
        'p_decision': decision,
        'p_review_note': reviewNote?.trim().isEmpty == true
            ? null
            : reviewNote?.trim(),
      },
    );
  }

  Future<void> fulfillHealthOrderRequest(String requestId) async {
    await client.rpc(
      'fulfill_health_order_request',
      params: {'p_request_id': requestId},
    );
  }

  Future<String> createHealthPrescriptionSignedUrl(String path) async {
    return _read(() => client.storage
        .from('health-prescriptions')
        .createSignedUrl(path, 300));
  }

  Future<String> applyToJob(String jobId) async =>
      (await client.rpc(
        'apply_to_job',
        params: {'p_job_id': jobId},
      ))
          .toString();

  Future<String> createFreight({
    required Map<String, dynamic> pickup,
    required Map<String, dynamic> delivery,
    num? weightKg,
    num? volumeM3,
    String? description,
  }) async =>
      (await client.rpc(
        'create_freight_request',
        params: {
          'p_pickup': pickup,
          'p_delivery': delivery,
          'p_weight_kg': weightKg,
          'p_volume_m3': volumeM3,
          'p_description': description,
        },
      ))
          .toString();

  Future<String> createParcel({
    required String recipientName,
    required String recipientPhone,
    required Map<String, dynamic> pickupAddress,
    required Map<String, dynamic> deliveryAddress,
    num? weightKg,
  }) async =>
      (await client.rpc(
        'create_parcel_request',
        params: {
          'p_recipient_name': recipientName,
          'p_recipient_phone': recipientPhone,
          'p_pickup_address': pickupAddress,
          'p_delivery_address': deliveryAddress,
          'p_weight_kg': weightKg,
        },
      ))
          .toString();

  Future<Map<String, dynamic>> trackParcel(String trackingCode) async {
    final result = await client.rpc(
      'get_parcel_tracking',
      params: {'p_tracking_code': trackingCode},
    );
    if (result is! Map) throw StateError('Suivi colis invalide.');
    return Map<String, dynamic>.from(result);
  }

  String _date(DateTime value) => value.toIso8601String().substring(0, 10);

  List<Map<String, dynamic>> _maps(dynamic rows) {
    if (rows is! List) return const [];
    return rows
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }
}
