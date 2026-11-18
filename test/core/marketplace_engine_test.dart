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

    test('authenticated server-backed actions become available', () {
      for (final capability in MarketplaceCapability.values) {
        if (capability == MarketplaceCapability.browseCatalog) continue;
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
