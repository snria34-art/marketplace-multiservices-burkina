import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/core/config/supabase_config.dart';

void main() {
  group('SupabaseConfig.isValidProjectUrl', () {
    test('accepts an HTTPS Supabase project URL', () {
      expect(
        SupabaseConfig.isValidProjectUrl(
          'https://piojnvhpqbyvaijzhatm.supabase.co',
        ),
        isTrue,
      );
    });

    test('rejects a project reference in place of a URL', () {
      expect(
        SupabaseConfig.isValidProjectUrl('piojnvhpqbyvaijzhatm'),
        isFalse,
      );
    });

    test('rejects HTTP and dashboard URLs', () {
      expect(
        SupabaseConfig.isValidProjectUrl(
          'http://piojnvhpqbyvaijzhatm.supabase.co',
        ),
        isFalse,
      );
      expect(
        SupabaseConfig.isValidProjectUrl(
          'https://supabase.com/dashboard/project/piojnvhpqbyvaijzhatm',
        ),
        isFalse,
      );
    });

    test('rejects credentials, query strings, and unexpected paths', () {
      expect(
        SupabaseConfig.isValidProjectUrl(
          'https://user@piojnvhpqbyvaijzhatm.supabase.co',
        ),
        isFalse,
      );
      expect(
        SupabaseConfig.isValidProjectUrl(
          'https://piojnvhpqbyvaijzhatm.supabase.co?token=x',
        ),
        isFalse,
      );
      expect(
        SupabaseConfig.isValidProjectUrl(
          'https://piojnvhpqbyvaijzhatm.supabase.co/functions/v1',
        ),
        isFalse,
      );
    });
  });

  group('SupabaseConfig.isValidPublicKey', () {
    test('accepts a modern publishable key format', () {
      expect(
        SupabaseConfig.isValidPublicKey('sb_publishable_testKey_123456'),
        isTrue,
      );
    });

    test('accepts a legacy anon JWT format', () {
      expect(
        SupabaseConfig.isValidPublicKey('eyJhbGci.eyJzdWI.signature'),
        isTrue,
      );
    });

    test('rejects project references, empty values, and secret keys', () {
      expect(
        SupabaseConfig.isValidPublicKey('piojnvhpqbyvaijzhatm'),
        isFalse,
      );
      expect(SupabaseConfig.isValidPublicKey(''), isFalse);
      expect(
        SupabaseConfig.isValidPublicKey('sb_secret_testKey_123456'),
        isFalse,
      );
      expect(
        SupabaseConfig.isValidPublicKey('sb_publishable_short'),
        isFalse,
      );
    });
  });
}
