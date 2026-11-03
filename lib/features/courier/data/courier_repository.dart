import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CourierRepository {
  const CourierRepository(this.client);

  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> assignments() async {
    final user = client.auth.currentUser;
    if (user == null) return const [];

    final rows = await client
        .from('delivery_assignments')
        .select(
          'id,package_id,courier_id,status,assigned_at,accepted_at,completed_at',
        )
        .eq('courier_id', user.id)
        .order('assigned_at', ascending: false)
        .limit(100);

    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
  }

  Future<void> accept(String assignmentId) async {
    await client.rpc(
      'accept_delivery_assignment',
      params: {'p_assignment_id': assignmentId},
    );
  }

  Future<void> start(String packageId) async {
    await client.rpc(
      'start_package_delivery',
      params: {'p_package_id': packageId},
    );
  }

  Future<void> uploadEvidence({
    required String packageId,
    required XFile file,
    required String evidenceType,
    bool personVisible = false,
    bool personConsent = false,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Authentification requise.');
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      throw StateError('La preuve doit faire au maximum 5 Mo.');
    }
    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : 'jpg';
    final path = '${user.id}/delivery/$packageId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    final mime = file.mimeType ?? 'image/jpeg';
    await client.storage.from('order-feedback-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mime, upsert: false),
    );
    await client.rpc('attach_delivery_evidence', params: {
      'p_package_id': packageId,
      'p_storage_path': path,
      'p_media_type': mime.startsWith('video/') ? 'VIDEO' : 'IMAGE',
      'p_evidence_type': evidenceType,
      'p_duration_seconds': null,
      'p_person_visible': false,
      'p_person_consent': false,
    });
  }

  Future<void> confirmPickup({
    required String packageId,
    required String pickupCode,
  }) async {
    await client.rpc('confirm_package_pickup', params: {
      'p_package_id': packageId,
      'p_pickup_code': pickupCode,
    });
  }

  Future<void> confirmDelivery({
    required String packageId,
    required String deliveryCode,
  }) async {
    await client.rpc('confirm_package_delivery', params: {
      'p_package_id': packageId,
      'p_delivery_code': deliveryCode,
    });
  }

  Future<void> recordLocation({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) async {
    await client.rpc(
      'record_courier_location',
      params: {
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_accuracy_m': accuracy,
      },
    );
  }
}
