import 'package:image_picker/image_picker.dart';

import '../../../core/media/upload_media_validator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CourierRepository {
  const CourierRepository(this.client);

  final SupabaseClient client;

  Future<List<Map<String, dynamic>>> assignments() async {
    if (client.auth.currentUser == null) return const [];

    final rows = await client.rpc('get_courier_assignments');
    if (rows is! List) return const [];

    return rows
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
    const maxBytes = 5 * 1024 * 1024;
    final fileSize = await file.length();
    if (fileSize <= 0 || fileSize > maxBytes) {
      throw StateError('La preuve doit faire au maximum 5 Mo.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw StateError('La preuve doit faire au maximum 5 Mo.');
    }
    final sourceExtension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    const mimeByExtension = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
      'heic': 'image/heic',
    };
    const extensionByMime = {
      'image/jpeg': 'jpg',
      'image/png': 'png',
      'image/webp': 'webp',
      'image/heic': 'heic',
    };
    final mime =
        file.mimeType?.toLowerCase() ?? mimeByExtension[sourceExtension];
    if (mime == null || !extensionByMime.containsKey(mime)) {
      throw StateError('Format de preuve non pris en charge.');
    }
    UploadMediaValidator.requireMimeType(bytes, mime);
    final extension = extensionByMime[mime]!;
    final path = '${user.id}/delivery/$packageId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client.storage.from('order-feedback-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mime, upsert: false),
    );
    try {
      await client.rpc('attach_delivery_evidence', params: {
        'p_package_id': packageId,
        'p_storage_path': path,
        'p_media_type': mime.startsWith('video/') ? 'VIDEO' : 'IMAGE',
        'p_evidence_type': evidenceType,
        'p_duration_seconds': null,
        'p_person_visible': personVisible,
        'p_person_consent': personConsent,
      });
    } catch (_) {
      // Avoid retaining an uploaded delivery file without its database record.
      try {
        await client.storage.from('order-feedback-media').remove([path]);
      } catch (_) {
        // Preserve the original RPC error if cleanup is unavailable.
      }
      rethrow;
    }
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
