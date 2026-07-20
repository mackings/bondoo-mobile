import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const allOrderSteps = [
  'placed',
  'processing',
  'packed',
  'shipped',
  'out_for_delivery',
  'delivered',
  'confirmed',
];

String orderStatusLabel(String s) => switch (s) {
      'placed' => 'Order Placed',
      'processing' => 'Processing',
      'packed' => 'Packed',
      'shipped' => 'Shipped',
      'out_for_delivery' => 'Out for Delivery',
      'delivered' => 'Delivered',
      'confirmed' => 'Delivery Confirmed',
      'cancelled' => 'Cancelled',
      _ => s,
    };

Color orderStatusColor(String s) => switch (s) {
      'placed' => const Color(0xff53bdeb),
      'processing' => Colors.orange,
      'packed' => const Color(0xff00a884),
      'shipped' => const Color(0xff0a8f68),
      'out_for_delivery' => const Color(0xff1da35f),
      'delivered' => AppTheme.success,
      'confirmed' => AppTheme.primaryBright,
      'cancelled' => AppTheme.danger,
      _ => AppTheme.muted,
    };

IconData orderStatusIcon(String s) => switch (s) {
      'placed' => Icons.shopping_bag_outlined,
      'processing' => Icons.settings_outlined,
      'packed' => Icons.inventory_2_outlined,
      'shipped' => Icons.local_shipping_outlined,
      'out_for_delivery' => Icons.delivery_dining_rounded,
      'delivered' => Icons.check_circle_outline_rounded,
      'confirmed' => Icons.verified_rounded,
      'cancelled' => Icons.cancel_outlined,
      _ => Icons.circle_outlined,
    };

/// Statuses a seller can transition to from [current].
List<String> availableNextStatuses(String current) {
  const sellerStatuses = [
    'processing',
    'packed',
    'shipped',
    'out_for_delivery',
    'delivered',
    'cancelled',
  ];
  final idx = allOrderSteps.indexOf(current);
  if (idx < 0 || current == 'confirmed' || current == 'cancelled') return [];
  return sellerStatuses.where((s) {
    if (s == 'cancelled') return true;
    final si = allOrderSteps.indexOf(s);
    return si > idx;
  }).toList();
}
