import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/core/routing/route_access.dart';

void main() {
  group('routeRequiresAuthentication', () {
    test('protects customer routes', () {
      for (final path in [
        '/cart',
        '/checkout/cart-1',
        '/orders',
        '/orders/order-1',
        '/delivery/order-1',
        '/follows',
        '/group-buy',
        '/messages',
        '/notifications',
        '/notifications/preferences',
      ]) {
        expect(routeRequiresAuthentication(path), isTrue, reason: path);
      }
    });

    test('protects role-specific route families', () {
      expect(routeRequiresAuthentication('/admin'), isTrue);
      expect(routeRequiresAuthentication('/admin/refunds'), isTrue);
      expect(routeRequiresAuthentication('/seller'), isTrue);
      expect(routeRequiresAuthentication('/seller/products'), isTrue);
      expect(routeRequiresAuthentication('/courier'), isTrue);
    });

    test('keeps public discovery routes browseable', () {
      for (final path in [
        '/',
        '/auth/forgot-password',
        '/auth/recovery',
        '/recovery',
        '/restaurants',
        '/transport',
        '/mechanics',
        '/services',
        '/promotions',
        '/real-estate',
      ]) {
        expect(routeRequiresAuthentication(path), isFalse, reason: path);
      }
    });
  });

  group('role route classification', () {
    test('matches complete admin and seller route families only', () {
      expect(isAdminRoute('/admin'), isTrue);
      expect(isAdminRoute('/admin/accounts'), isTrue);
      expect(isAdminRoute('/administrator'), isFalse);
      expect(isSellerRoute('/seller'), isTrue);
      expect(isSellerRoute('/seller/products'), isTrue);
      expect(isSellerRoute('/seller-tools'), isFalse);
    });

    test('matches only the courier route', () {
      expect(isCourierRoute('/courier'), isTrue);
      expect(isCourierRoute('/courier/extra'), isFalse);
      expect(isCourierRoute('/orders'), isFalse);
    });

    test('allows moderators only on catalog and review moderation routes', () {
      expect(isModerationRoute('/admin/catalog-moderation'), isTrue);
      expect(isModerationRoute('/admin/reviews'), isTrue);
      expect(isModerationRoute('/admin'), isFalse);
      expect(isModerationRoute('/admin/accounts'), isFalse);
      expect(isModerationRoute('/admin/platform-health'), isFalse);
      expect(isModerationRoute('/admin/refunds'), isFalse);
    });
  });

  group('sanitizeInternalLocation', () {
    test('preserves valid internal route and query string', () {
      expect(
        sanitizeInternalLocation('/orders/order-1?tab=items'),
        '/orders/order-1?tab=items',
      );
    });

    test('rejects null, empty and relative locations', () {
      expect(sanitizeInternalLocation(null), isNull);
      expect(sanitizeInternalLocation(''), isNull);
      expect(sanitizeInternalLocation('orders/order-1'), isNull);
    });

    test('rejects external and authority-based locations', () {
      expect(sanitizeInternalLocation('https://example.com'), isNull);
      expect(sanitizeInternalLocation('//example.com/path'), isNull);
    });

    test('rejects login/status loops and parent path traversal', () {
      expect(sanitizeInternalLocation('/auth'), isNull);
      expect(sanitizeInternalLocation('/access-status'), isNull);
      expect(sanitizeInternalLocation('/orders/../admin'), isNull);
      expect(sanitizeInternalLocation('/orders/%2e%2e/admin'), isNull);
      expect(sanitizeInternalLocation('/orders/%252e%252e/admin'), isNull);
      expect(sanitizeInternalLocation(r'/orders\\..\\admin'), isNull);
    });
  });
}
