import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../data/order_repository.dart';
import '../utils/order_utils.dart';
import 'order_detail_screen.dart';




final _nfmt = NumberFormat.currency(symbol: '₦', decimalDigits: 2, locale: 'en_NG');

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<Map<String, dynamic>> _purchases = [];
  List<Map<String, dynamic>> _sales = [];
  bool _loadingPurchases = true;
  bool _loadingSales = true;
  String? _purchasesError;
  String? _salesError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    _loadPurchases();
    _loadSales();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _loadPurchases() async {
    setState(() {
      _loadingPurchases = true;
      _purchasesError = null;
    });
    try {
      final list = await ref.read(orderRepositoryProvider).getMyOrders();
      if (mounted) setState(() { _purchases = list; _loadingPurchases = false; });
    } catch (e) {
      if (mounted) setState(() { _purchasesError = '$e'; _loadingPurchases = false; });
    }
  }

  Future<void> _loadSales() async {
    setState(() {
      _loadingSales = true;
      _salesError = null;
    });
    try {
      final list = await ref.read(orderRepositoryProvider).getMySales();
      if (mounted) setState(() { _sales = list; _loadingSales = false; });
    } catch (e) {
      if (mounted) setState(() { _salesError = '$e'; _loadingSales = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Orders', style: TextStyle(fontWeight: FontWeight.w900)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppTheme.primary,
          labelColor: AppTheme.primaryBright,
          unselectedLabelColor: AppTheme.muted,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          tabs: const [
            Tab(text: 'My Purchases'),
            Tab(text: 'My Sales'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _OrderList(
            orders: _purchases,
            loading: _loadingPurchases,
            error: _purchasesError,
            emptyIcon: Icons.shopping_bag_outlined,
            emptyMessage: 'No purchases yet',
            emptySubtitle: 'Browse the marketplace and buy a product to see your purchases here.',
            onRefresh: _loadPurchases,
          ),
          _OrderList(
            orders: _sales,
            loading: _loadingSales,
            error: _salesError,
            emptyIcon: Icons.storefront_outlined,
            emptyMessage: 'No sales yet',
            emptySubtitle: 'List a product in the marketplace to start selling.',
            onRefresh: _loadSales,
          ),
        ],
      ),
    );
  }
}

// ── Order list ────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  const _OrderList({
    required this.orders,
    required this.loading,
    required this.error,
    required this.emptyIcon,
    required this.emptyMessage,
    required this.emptySubtitle,
    required this.onRefresh,
  });

  final List<Map<String, dynamic>> orders;
  final bool loading;
  final String? error;
  final IconData emptyIcon;
  final String emptyMessage;
  final String emptySubtitle;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 42),
              const SizedBox(height: 14),
              Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 20),
              FilledButton(onPressed: onRefresh, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, color: AppTheme.muted, size: 52),
              const SizedBox(height: 16),
              Text(emptyMessage, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              Text(emptySubtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _OrderCard(order: orders[i]),
      ),
    );
  }
}

// ── Order card ────────────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final snapshot = order['product_snapshot'] as Map<String, dynamic>? ?? {};
    final product = order['product'] as Map<String, dynamic>?;
    final title = '${product?['title'] ?? snapshot['title'] ?? 'Product'}';
    final status = '${order['status'] ?? 'placed'}';
    final amount = (order['amount'] as num?)?.toDouble() ?? 0;
    final date = _fmtDate(order['created_at']);
    final color = orderStatusColor(status);
    final images = product?['images'] as List? ?? [];
    final firstImage = images.isNotEmpty ? '${images[0]}' : null;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrderDetailScreen(order: order)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: firstImage != null
                  ? Image.memory(
                      _decodeImage(firstImage),
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _placeholder(),
                    )
                  : _placeholder(),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      orderStatusLabel(status),
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        _nfmt.format(amount),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppTheme.primaryBright),
                      ),
                      const Spacer(),
                      Text(date, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.muted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: AppTheme.elevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.image_outlined, color: AppTheme.muted, size: 22),
      );

  Uint8List _decodeImage(String dataUrl) {
    final b64 = dataUrl.contains(',') ? dataUrl.split(',').last : dataUrl;
    return base64Decode(b64);
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '';
    try {
      return DateFormat('MMM d, y').format(DateTime.parse('$raw').toLocal());
    } catch (_) {
      return '';
    }
  }
}
