import 'dart:typed_data';

/// Detects the actual container signature for file types accepted by uploads.
///
/// This is client-side input validation, not a substitute for server-side
/// content inspection. Storage policies still control who may upload.
class UploadMediaValidator {
  UploadMediaValidator._();

  static String? detectMimeType(Uint8List bytes) {
    if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) {
      return 'image/jpeg';
    }

    if (_startsWith(
      bytes,
      const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    )) {
      return 'image/png';
    }

    if (bytes.length >= 12 &&
        _ascii(bytes, 0, 4) == 'RIFF' &&
        _ascii(bytes, 8, 4) == 'WEBP') {
      return 'image/webp';
    }

    final isoBmffMime = _detectIsoBmffMimeType(bytes);
    if (isoBmffMime != null) return isoBmffMime;

    return null;
  }

  /// Throws when the declared MIME type does not match the file signature.
  static void requireMimeType(Uint8List bytes, String declaredMimeType) {
    final declared = declaredMimeType.trim().toLowerCase();
    final detected = detectMimeType(bytes);
    if (detected == null || detected != declared) {
      throw const FormatException(
        'Le contenu du fichier ne correspond pas au format annoncé.',
      );
    }
  }

  static String? _detectIsoBmffMimeType(Uint8List bytes) {
    // ISO Base Media files (MP4, QuickTime and HEIF) use an ftyp box.
    if (bytes.length < 16 || _ascii(bytes, 4, 4) != 'ftyp') {
      return null;
    }

    final boxSize = (bytes[0] << 24) |
        (bytes[1] << 16) |
        (bytes[2] << 8) |
        bytes[3];
    if (boxSize < 16 || boxSize > bytes.length || boxSize % 4 != 0) {
      return null;
    }

    final brands = <String>{_ascii(bytes, 8, 4)};
    for (var offset = 16; offset + 4 <= boxSize; offset += 4) {
      brands.add(_ascii(bytes, offset, 4));
    }

    if (brands.contains('qt  ')) return 'video/quicktime';

    const heifBrands = {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'hevm',
      'hevs',
      'mif1',
      'msf1',
    };
    if (brands.any(heifBrands.contains)) return 'image/heic';

    const mp4Brands = {
      'isom',
      'iso2',
      'mp41',
      'mp42',
      'avc1',
      'M4V ',
      'MSNV',
      'dash',
      '3gp4',
      '3gp5',
      '3g2a',
      '3g2b',
    };
    if (brands.any(mp4Brands.contains)) return 'video/mp4';

    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return false;
    }
    return true;
  }

  static String _ascii(Uint8List bytes, int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > bytes.length) {
      return '';
    }
    return String.fromCharCodes(bytes.sublist(offset, offset + length));
  }
}
