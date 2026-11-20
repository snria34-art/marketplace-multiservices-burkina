import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/navigation/app_navigation.dart';
import '../../core/providers/repository_providers.dart';
import '../../features/auth/presentation/access_status_page.dart';
import 'route_access.dart';

import '../../features/auth/presentation/sign_in_page.dart';
import '../../features/auth/presentation/forgot_password_page.dart';
import '../../features/auth/presentation/auth_recovery_page.dart';
import '../../features/cart/presentation/cart_page.dart';
import '../../features/catalog/presentation/home_page.dart';
import '../../features/checkout/presentation/checkout_page.dart';
import '../../features/checkout/presentation/orders_page.dart';
import '../../features/checkout/presentation/order_details_page.dart';
import '../../features/common/presentation/module_placeholder_page.dart';
import '../../features/courier/presentation/courier_page.dart';
import '../../features/delivery/presentation/delivery_tracking_page.dart';
import '../../features/expiry/presentation/expiry_page.dart';
import '../../features/follows/presentation/follows_page.dart';
import '../../features/group_buy/presentation/group_buy_page.dart';
import '../../features/mechanics/presentation/mechanics_page.dart';
import '../../features/messaging/presentation/messages_page.dart';
import '../../features/notifications/presentation/notification_preferences_page.dart';
import '../../features/notifications/presentation/notifications_page.dart';
import '../../features/restaurants/presentation/restaurants_page.dart';
import '../../features/seller/presentation/seller_dashboard_page.dart';
import '../../features/seller/presentation/seller_orders_page.dart';
import '../../features/seller/presentation/seller_products_page.dart';
import '../../features/seller/presentation/seller_restaurant_options_page.dart';
import '../../features/seller/presentation/seller_tools_page.dart';
import '../../features/services/presentation/services_page.dart';
import '../../features/transport/presentation/transport_page.dart';
import '../../features/promotions/presentation/promotions_page.dart';
import '../../features/seller/presentation/seller_finance_page.dart';
import '../../features/seller/presentation/seller_shop_page.dart';
import '../../features/seller/presentation/seller_coupons_page.dart';
import '../../features/seller/presentation/seller_promotions_page.dart';
import '../../features/seller/presentation/seller_clients_page.dart';
import '../../features/seller/presentation/seller_reviews_page.dart';
import '../../features/seller/presentation/seller_stats_page.dart';
import '../../features/seller/presentation/seller_settings_page.dart';
import '../../features/seller/presentation/seller_moderation_page.dart';
import '../../features/verticals/data/vertical_repository.dart';
import '../../features/verticals/presentation/vertical_discovery_page.dart';
import '../../features/admin/presentation/admin_dashboard_page.dart';
import '../../features/admin/presentation/admin_assistant_page.dart';
import '../../features/admin/presentation/admin_return_policies_page.dart';
import '../../features/admin/presentation/admin_catalog_moderation_page.dart';
import '../../features/admin/presentation/admin_platform_health_page.dart';
import '../../features/admin/presentation/admin_review_moderation_page.dart';
import '../../features/admin/presentation/admin_accounts_page.dart';
import '../../features/admin/presentation/admin_refunds_page.dart';
import '../../features/admin/presentation/admin_seller_payouts_page.dart';
import '../../features/admin/presentation/admin_partner_network_page.dart';
import '../../features/whatsapp/presentation/whatsapp_assistant_page.dart';
import '../../features/wallet/presentation/customer_wallet_page.dart';
import '../../features/businesses/presentation/businesses_mobility_page.dart';

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(SupabaseClient? client) {
    _subscription = client?.auth.onAuthStateChange.listen(
      (_) => _notifyIfActive(),
      onError: (Object error, StackTrace stackTrace) {
        // Re-evaluate guarded routes on auth-stream failure. The route guard
        // remains fail-closed if the backend cannot verify the session.
        _notifyIfActive();
      },
    );
  }

  StreamSubscription<dynamic>? _subscription;
  bool _disposed = false;

  void _notifyIfActive() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}

String _loginLocation(GoRouterState state) {
  return Uri(
    path: '/auth',
    queryParameters: {'from': state.uri.toString()},
  ).toString();
}

Future<String?> _guardRoute(
  SupabaseClient? client,
  GoRouterState state,
) async {
  final path = state.matchedLocation;

  if (path == '/access-status') return null;

  final user = client?.auth.currentUser;
  final requiresAuth = routeRequiresAuthentication(path);

  if (user == null) {
    return requiresAuth ? _loginLocation(state) : null;
  }

  if (client == null) {
    return requiresAuth ? '/access-status?reason=verification_unavailable' : null;
  }

  // Public catalogue pages remain browseable without extra profile requests.
  // Session and role checks apply to protected routes and the login page.
  if (!requiresAuth && path != '/auth') return null;

  try {
    final profile = await client
        .from('profiles')
        .select('status')
        .eq('id', user.id)
        .maybeSingle();

    if (profile == null || profile['status'] != 'ACTIVE') {
      return '/access-status?reason=account_inactive';
    }

    if (path == '/auth') {
      return sanitizeInternalLocation(state.uri.queryParameters['from']) ?? '/';
    }

    if (isAdminRoute(path)) {
      final admin = await client
          .from('admin_users')
          .select('user_id')
          .eq('user_id', user.id)
          .eq('active', true)
          .maybeSingle();

      if (admin == null) {
        if (!isModerationRoute(path)) {
          return '/access-status?reason=admin_required';
        }

        final rows = await client
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id);
        final hasModeratorRole =
            rows.any((row) => row['role'] == 'MODERATOR');

        if (!hasModeratorRole) {
          return '/access-status?reason=moderator_required';
        }
      }
    }

    if (isSellerRoute(path)) {
      final rows = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id);
      final hasSellerRole = rows.any((row) => row['role'] == 'SELLER');
      final sellerProfile = await client
          .from('sellers')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (!hasSellerRole || sellerProfile == null) {
        return '/access-status?reason=seller_required';
      }
    }

    if (isCourierRoute(path)) {
      final rows = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id);
      final hasCourierRole = rows.any((row) => row['role'] == 'COURIER');

      if (!hasCourierRole) return '/access-status?reason=courier_required';
    }

    return null;
  } catch (_) {
    // Fail closed: never open a protected route when role checks cannot run.
    return '/access-status?reason=verification_unavailable';
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(marketplaceEngineProvider).backendClient;
  final authRefresh = _AuthRefreshListenable(client);

  final router = GoRouter(
    refreshListenable: authRefresh,
    redirect: (context, state) => _guardRoute(client, state).timeout(
      const Duration(seconds: 12),
      onTimeout: () => '/access-status?reason=verification_unavailable',
    ),
    navigatorKey: appNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomePage()),
      GoRoute(path: '/whatsapp', builder: (_, _) => const WhatsAppAssistantPage()),
      GoRoute(path: '/wallet', builder: (_, _) => const CustomerWalletPage()),
      GoRoute(path: '/auth', builder: (_, _) => const SignInPage()),
      GoRoute(
        path: '/auth/forgot-password',
        builder: (_, _) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: '/auth/recovery',
        builder: (_, _) => const AuthRecoveryPage(),
      ),
      // Some platform deep-link handlers expose only the URI path (/recovery)
      // and omit the custom-scheme host (auth). Keep this equivalent route.
      GoRoute(
        path: '/recovery',
        builder: (_, _) => const AuthRecoveryPage(),
      ),
      GoRoute(
        path: '/access-status',
        builder: (_, state) => AccessStatusPage(
          reason: state.uri.queryParameters['reason'],
        ),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartPage()),
      GoRoute(
        path: '/checkout/:cartId',
        builder: (_, state) {
          final cartId = state.pathParameters['cartId'];

          if (cartId == null || cartId.isEmpty) {
            return const ModulePlaceholderPage(
              title: 'Panier invalide',
              icon: Icons.shopping_cart_outlined,
            );
          }

          return CheckoutPage(cartId: cartId);
        },
      ),
      GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
      GoRoute(
        path: '/orders/:orderId',
        builder: (_, state) {
          final orderId = state.pathParameters['orderId'];
          if (orderId == null || orderId.isEmpty) {
            return const ModulePlaceholderPage(
              title: 'Commande invalide',
              icon: Icons.receipt_long_outlined,
            );
          }
          return OrderDetailsPage(orderId: orderId);
        },
      ),
      GoRoute(
        path: '/delivery/:orderId',
        builder: (_, state) {
          final orderId = state.pathParameters['orderId'];

          if (orderId == null || orderId.isEmpty) {
            return const ModulePlaceholderPage(
              title: 'Commande invalide',
              icon: Icons.local_shipping_outlined,
            );
          }

          return DeliveryTrackingPage(orderId: orderId);
        },
      ),
      GoRoute(path: '/courier', builder: (_, _) => const CourierPage()),
      GoRoute(
        path: '/restaurants',
        builder: (_, _) => const RestaurantsPage(),
      ),
      GoRoute(
        path: '/transport',
        builder: (_, _) => const TransportPage(),
      ),
      GoRoute(
        path: '/mechanics',
        builder: (_, _) => const MechanicsPage(),
      ),
      GoRoute(
        path: '/expiry',
        builder: (_, _) => const ExpiryPage(),
      ),
      GoRoute(
        path: '/follows',
        builder: (_, _) => const FollowsPage(),
      ),
      GoRoute(
        path: '/group-buy',
        builder: (_, _) => const GroupBuyPage(),
      ),
      GoRoute(
        path: '/services',
        builder: (_, _) => const ServicesPage(),
      ),
      GoRoute(
        path: '/businesses-mobility',
        builder: (_, _) => const BusinessesMobilityPage(),
      ),
      GoRoute(
        path: '/messages',
        builder: (_, _) => const MessagesPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/notifications/preferences',
        builder: (_, _) => const NotificationPreferencesPage(),
      ),
      GoRoute(
        path: '/admin/partner-network',
        builder: (_, _) => const AdminPartnerNetworkPage(),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, _) => const AdminDashboardPage(),
      ),
      GoRoute(
        path: '/admin/catalog-moderation',
        builder: (_, _) => const AdminCatalogModerationPage(),
      ),
      GoRoute(
        path: '/admin/return-policies',
        builder: (_, _) => const AdminReturnPoliciesPage(),
      ),
      GoRoute(
        path: '/admin/assistant',
        builder: (_, _) => const AdminAssistantPage(),
      ),
      GoRoute(
        path: '/admin/platform-health',
        builder: (_, _) => const AdminPlatformHealthPage(),
      ),
      GoRoute(
        path: '/admin/reviews',
        builder: (_, _) => const AdminReviewModerationPage(),
      ),
      GoRoute(
        path: '/admin/accounts',
        builder: (_, _) => const AdminAccountsPage(),
      ),
      GoRoute(
        path: '/admin/seller-payouts',
        builder: (_, _) => const AdminSellerPayoutsPage(),
      ),
      GoRoute(
        path: '/admin/refunds',
        builder: (_, _) => const AdminRefundsPage(),
      ),
      GoRoute(
        path: '/seller',
        builder: (_, _) => const SellerToolsPage(),
      ),
      GoRoute(
        path: '/seller/moderation',
        builder: (_, _) => const SellerModerationPage(),
      ),
      GoRoute(
        path: '/seller/dashboard',
        builder: (_, _) => const SellerDashboardPage(),
      ),
      GoRoute(
        path: '/seller/products',
        builder: (_, _) => const SellerProductsPage(),
      ),
      GoRoute(
        path: '/seller/restaurant-options',
        builder: (_, _) => const SellerRestaurantOptionsPage(),
      ),
      GoRoute(
        path: '/seller/orders',
        builder: (_, _) => const SellerOrdersPage(),
      ),
      GoRoute(path: '/promotions', builder: (_, _) => const PromotionsPage()),
      GoRoute(path: '/seller/shop', builder: (_, _) => const SellerShopPage()),
      GoRoute(path: '/seller/coupons', builder: (_, _) => const SellerCouponsPage()),
      GoRoute(path: '/seller/promotions', builder: (_, _) => const SellerPromotionsPage()),
      GoRoute(path: '/seller/clients', builder: (_, _) => const SellerClientsPage()),
      GoRoute(path: '/seller/reviews', builder: (_, _) => const SellerReviewsPage()),
      GoRoute(path: '/seller/stats', builder: (_, _) => const SellerStatsPage()),
      GoRoute(path: '/seller/finance', builder: (_, _) => const SellerFinancePage()),
      for (final item in const <({String path, VerticalModule module})>[
        (path: '/rides', module: VerticalModule.rides),
        (path: '/rentals', module: VerticalModule.rentals),
        (path: '/real-estate', module: VerticalModule.realEstate),
        (path: '/accommodations', module: VerticalModule.accommodations),
        (path: '/events', module: VerticalModule.events),
        (path: '/jobs', module: VerticalModule.jobs),
        (path: '/professionals', module: VerticalModule.professionals),
        (path: '/agriculture', module: VerticalModule.agriculture),
        (path: '/freight', module: VerticalModule.freight),
        (path: '/health', module: VerticalModule.health),
        (path: '/beauty', module: VerticalModule.beauty),
        (path: '/home-services', module: VerticalModule.homeServices),
        (path: '/digital', module: VerticalModule.digital),
        (path: '/training', module: VerticalModule.training),
        (path: '/creative', module: VerticalModule.creative),
        (path: '/parcels', module: VerticalModule.parcels),
      ])
        GoRoute(
          path: item.path,
          builder: (_, _) => VerticalDiscoveryPage(module: item.module),
        ),
      GoRoute(path: '/seller/stock', builder: (_, _) => const SellerProductsPage()),
      GoRoute(path: '/seller/payouts', builder: (_, _) => const SellerFinancePage()),
      GoRoute(path: '/seller/commissions', builder: (_, _) => const SellerFinancePage()),
      GoRoute(path: '/seller/settings', builder: (_, _) => const SellerSettingsPage()),
    ],
  );

  // The router owns its auth refresh subscription. Dispose each resource
  // exactly once when Riverpod rebuilds or disposes this provider.
  ref.onDispose(() {
    router.dispose();
    authRefresh.dispose();
  });

  return router;
});

