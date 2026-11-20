import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_multiservices_burkina/core/engine/marketplace_engine.dart';

void main() {
  group('MarketplaceEngine capability policy', () {
    test('catalogue browsing remains available without backend', () {
      expect(
        MarketplaceEngine.capabilityState(
          MarketplaceCapability.browseCatalog,
          backendConfigured: false,
          authenticated: false,
        ),
        CapabilityState.available,
      );
    });

    test('public discovery capabilities work for guests when backend is configured', () {
      const capabilities = [
        MarketplaceCapability.discoverRestaurants,
        MarketplaceCapability.discoverGroupBuys,
        MarketplaceCapability.discoverMechanics,
        MarketplaceCapability.discoverServices,
        MarketplaceCapability.discoverTransport,
        MarketplaceCapability.discoverVerticals,
        MarketplaceCapability.discoverPromotions,
        MarketplaceCapability.authenticate,
      ];
      for (final capability in capabilities) {
        expect(
          MarketplaceEngine.capabilityState(
            capability,
            backendConfigured: true,
            authenticated: false,
          ),
          CapabilityState.available,
          reason: '$capability should be public discovery',
        );
      }
    });

    test('restaurant discovery requires backend but not a customer login', () {
      expect(
        MarketplaceEngine.capabilityState(
          MarketplaceCapability.discoverRestaurants,
          backendConfigured: false,
          authenticated: false,
        ),
        CapabilityState.backendRequired,
      );
      expect(
        MarketplaceEngine.capabilityState(
          MarketplaceCapability.discoverRestaurants,
          backendConfigured: true,
          authenticated: false,
        ),
        CapabilityState.available,
      );
    });

    test('seller restaurant configuration requires authentication', () {
      expect(
        MarketplaceEngine.capabilityState(
          MarketplaceCapability.configureRestaurantCatalog,
          backendConfigured: true,
          authenticated: false,
        ),
        CapabilityState.authenticationRequired,
      );
    });

    test('server-backed actions require backend configuration', () {
      expect(
        MarketplaceEngine.capabilityState(
          MarketplaceCapability.placeOrder,
          backendConfigured: false,
          authenticated: true,
        ),
        CapabilityState.backendRequired,
      );
    });

    test('server-backed actions require an authenticated session', () {
      expect(
        MarketplaceEngine.capabilityState(
          MarketplaceCapability.useMessaging,
          backendConfigured: true,
          authenticated: false,
        ),
        CapabilityState.authenticationRequired,
      );
    });

    test('engine retries safe reads but never retries mutations', () async {
      var readCalls = 0;
      final engine = MarketplaceEngine(
        null,
        resilience: MarketplaceResilience(
          wait: (_) async {},
        ),
      );

      final value = await engine.read(() async {
        readCalls++;
        if (readCalls == 1) throw TimeoutException('temporary read timeout');
        return 'loaded';
      });

      expect(value, 'loaded');
      expect(readCalls, 2);

      var mutationCalls = 0;
      await expectLater(
        engine.mutate(() async {
          mutationCalls++;
          throw StateError('unknown mutation outcome');
        }),
        throwsStateError,
      );
      expect(mutationCalls, 1);
    });

    test('authenticated server-backed actions become available', () {
      const protectedCapabilities = [
        MarketplaceCapability.configureRestaurantCatalog,
        MarketplaceCapability.manageCart,
        MarketplaceCapability.placeOrder,
        MarketplaceCapability.trackDelivery,
        MarketplaceCapability.courierOperations,
        MarketplaceCapability.manageFollows,
        MarketplaceCapability.useMessaging,
        MarketplaceCapability.readNotifications,
        MarketplaceCapability.reserveTransport,
        MarketplaceCapability.requestMechanicService,
        MarketplaceCapability.requestProfessionalService,
        MarketplaceCapability.manageVerticalWorkflows,
        MarketplaceCapability.manageSellerCatalog,
        MarketplaceCapability.readSellerFinance,
        MarketplaceCapability.readWallet,
        MarketplaceCapability.requestPayout,
        MarketplaceCapability.administerPlatform,
      ];
      for (final capability in protectedCapabilities) {
        expect(
          MarketplaceEngine.capabilityState(
            capability,
            backendConfigured: true,
            authenticated: true,
          ),
          CapabilityState.available,
        );
      }
    });
  });
}
