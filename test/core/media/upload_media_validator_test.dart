import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/core/media/upload_media_validator.dart';

void main() {
  group('UploadMediaValidator.detectMimeType', () {
    test('detects JPEG from its signature', () {
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
        ),
        'image/jpeg',
      );
    });

    test('detects PNG from its signature', () {
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([
            0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
          ]),
        ),
        'image/png',
      );
    });

    test('detects WebP from the RIFF and WEBP markers', () {
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([
            0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00,
            0x57, 0x45, 0x42, 0x50,
          ]),
        ),
        'image/webp',
      );
    });

    test('detects HEIC from an ISO BMFF ftyp brand', () {
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([
            0x00, 0x00, 0x00, 0x10,
            0x66, 0x74, 0x79, 0x70,
            0x68, 0x65, 0x69, 0x63,
            0x00, 0x00, 0x00, 0x00,
          ]),
        ),
        'image/heic',
      );
    });

    test('detects MP4 from an ISO BMFF brand', () {
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([
            0x00, 0x00, 0x00, 0x18,
            0x66, 0x74, 0x79, 0x70,
            0x69, 0x73, 0x6f, 0x6d,
            0x00, 0x00, 0x02, 0x00,
            0x6d, 0x70, 0x34, 0x31,
            0x6d, 0x70, 0x34, 0x32,
          ]),
        ),
        'video/mp4',
      );
    });

    test('detects QuickTime from its ISO BMFF brand', () {
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([
            0x00, 0x00, 0x00, 0x10,
            0x66, 0x74, 0x79, 0x70,
            0x71, 0x74, 0x20, 0x20,
            0x00, 0x00, 0x00, 0x00,
          ]),
        ),
        'video/quicktime',
      );
    });

    test('rejects unknown and truncated content', () {
      expect(
        UploadMediaValidator.detectMimeType(Uint8List.fromList([0x00, 0x01])),
        isNull,
      );
      expect(
        UploadMediaValidator.detectMimeType(
          Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
        ),
        isNull,
      );
    });
  });

  test('rejects a MIME type that does not match the file signature', () {
    expect(
      () => UploadMediaValidator.requireMimeType(
        Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]),
        'image/png',
      ),
      throwsFormatException,
    );
  });

  test('accepts an accurate declared MIME type', () {
    expect(
      () => UploadMediaValidator.requireMimeType(
        Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
        'image/png',
      ),
      returnsNormally,
    );
  });
}
