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

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(SupabaseClient? client) {
    _subscription = client?.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  StreamSubscription<dynamic>? _subscription;

  @override
  void dispose() {
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

      if (admin == null) return '/access-status?reason=admin_required';
    }

    if (isSellerRoute(path)) {
      final rows = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id);
      final hasSellerRole = rows is List &&
          rows.any((row) => row is Map && row['role'] == 'SELLER');

      if (!hasSellerRole) return '/access-status?reason=seller_required';
    }

    if (isCourierRoute(path)) {
      final rows = await client
          .from('user_roles')
          .select('role')
          .eq('user_id', user.id);
      final hasCourierRole = rows is List &&
          rows.any((row) => row is Map && row['role'] == 'COURIER');

      if (!hasCourierRole) return '/access-status?reason=courier_required';
    }

    return null;
  } catch (_) {
    // Fail closed: never open a protected route when role checks cannot run.
    return '/access-status?reason=verification_unavailable';
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseProvider);
  final authRefresh = _AuthRefreshListenable(client);

  final router = GoRouter(
    refreshListenable: authRefresh,
    redirect: (context, state) => _guardRoute(client, state),
    navigatorKey: appNavigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomePage()),
      GoRoute(path: '/auth', builder: (_, __) => const SignInPage()),
      GoRoute(
        path: '/access-status',
        builder: (_, state) => AccessStatusPage(
          reason: state.uri.queryParameters['reason'],
        ),
      ),
      GoRoute(path: '/cart', builder: (_, __) => const CartPage()),
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
      GoRoute(path: '/orders', builder: (_, __) => const OrdersPage()),
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
      GoRoute(path: '/courier', builder: (_, __) => const CourierPage()),
      GoRoute(
        path: '/restaurants',
        builder: (_, __) => const RestaurantsPage(),
      ),
      GoRoute(
        path: '/transport',
        builder: (_, __) => const TransportPage(),
      ),
      GoRoute(
        path: '/mechanics',
        builder: (_, __) => const MechanicsPage(),
      ),
      GoRoute(
        path: '/expiry',
        builder: (_, __) => const ExpiryPage(),
      ),
      GoRoute(
        path: '/follows',
        builder: (_, __) => const FollowsPage(),
      ),
      GoRoute(
        path: '/group-buy',
        builder: (_, __) => const GroupBuyPage(),
      ),
      GoRoute(
        path: '/services',
        builder: (_, __) => const ServicesPage(),
      ),
      GoRoute(
        path: '/messages',
        builder: (_, __) => const MessagesPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/notifications/preferences',
        builder: (_, __) => const NotificationPreferencesPage(),
      ),
      GoRoute(
        path: '/admin',
        builder: (_, __) => const AdminDashboardPage(),
      ),
      GoRoute(
        path: '/admin/catalog-moderation',
        builder: (_, __) => const AdminCatalogModerationPage(),
      ),
      GoRoute(
        path: '/admin/return-policies',
        builder: (_, __) => const AdminReturnPoliciesPage(),
      ),
      GoRoute(
        path: '/admin/assistant',
        builder: (_, __) => const AdminAssistantPage(),
      ),
      GoRoute(
        path: '/admin/platform-health',
        builder: (_, __) => const AdminPlatformHealthPage(),
      ),
      GoRoute(
        path: '/admin/reviews',
        builder: (_, __) => const AdminReviewModerationPage(),
      ),
      GoRoute(
        path: '/admin/accounts',
        builder: (_, __) => const AdminAccountsPage(),
      ),
      GoRoute(
        path: '/admin/refunds',
        builder: (_, __) => const AdminRefundsPage(),
      ),
      GoRoute(
        path: '/seller',
        builder: (_, __) => const SellerToolsPage(),
      ),
      GoRoute(
        path: '/seller/moderation',
        builder: (_, __) => const SellerModerationPage(),
      ),
      GoRoute(
        path: '/seller/dashboard',
        builder: (_, __) => const SellerDashboardPage(),
      ),
      GoRoute(
        path: '/seller/products',
        builder: (_, __) => const SellerProductsPage(),
      ),
      GoRoute(
        path: '/seller/orders',
        builder: (_, __) => const SellerOrdersPage(),
      ),
      GoRoute(path: '/promotions', builder: (_, __) => const PromotionsPage()),
      GoRoute(path: '/seller/shop', builder: (_, __) => const SellerShopPage()),
      GoRoute(path: '/seller/coupons', builder: (_, __) => const SellerCouponsPage()),
      GoRoute(path: '/seller/promotions', builder: (_, __) => const SellerPromotionsPage()),
      GoRoute(path: '/seller/clients', builder: (_, __) => const SellerClientsPage()),
      GoRoute(path: '/seller/reviews', builder: (_, __) => const SellerReviewsPage()),
      GoRoute(path: '/seller/stats', builder: (_, __) => const SellerStatsPage()),
      GoRoute(path: '/seller/finance', builder: (_, __) => const SellerFinancePage()),
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
          builder: (_, __) => VerticalDiscoveryPage(module: item.module),
        ),
      GoRoute(path: '/seller/stock', builder: (_, __) => const SellerProductsPage()),
      GoRoute(path: '/seller/payouts', builder: (_, __) => const SellerFinancePage()),
      GoRoute(path: '/seller/commissions', builder: (_, __) => const SellerFinancePage()),
      GoRoute(path: '/seller/settings', builder: (_, __) => const SellerSettingsPage()),
    ],
  );

  ref.onDispose(() {
    router.dispose();
    authRefresh.dispose();
  });

  return router;
});

