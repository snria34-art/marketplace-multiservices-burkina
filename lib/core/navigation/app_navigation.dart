import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

String? _safeNotificationId(dynamic value) {
  if (value == null) return null;
  final id = value.toString().trim();
  if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id)) return null;
  return id;
}

String notificationRoute(Map<String, dynamic> data) {
  // Notification payloads are untrusted input. Never navigate to a route
  // supplied by the payload: only construct destinations from known routes.
  final orderId = _safeNotificationId(data['order_id']);
  final deliveryOrderId = _safeNotificationId(data['delivery_order_id']);
  final type = (data['type'] ?? '').toString().toLowerCase();

  if (deliveryOrderId != null) {
    return '/delivery/$deliveryOrderId';
  }

  if (orderId != null) {
    return '/orders/$orderId';
  }

  if (type.contains('message') || type.contains('chat')) return '/messages';
  if (type.contains('promotion') || type.contains('coupon')) {
    return '/promotions';
  }
  if (type.contains('transport')) return '/transport';
  if (type.contains('mechanic') || type.contains('service')) {
    return '/services';
  }

  return '/notifications';
}

void openNotificationRoute(Map<String, dynamic> data) {
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  final route = notificationRoute(data);
  GoRouter.of(context).go(route);
}
