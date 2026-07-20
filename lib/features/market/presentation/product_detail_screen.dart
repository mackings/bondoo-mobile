import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chat_repository.dart';
import '../../chats/presentation/chat_screen.dart';
import '../../wallet/data/paystack_repository.dart';
import '../data/product_repository.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.product});

  final Map<String, dynamic> product;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _imageIndex = 0;
  bool _paying = false;
  bool _deleting = false;
  bool _togglingStock = false;
  // Local status override so UI updates immediately after seller toggles stock
  String? _statusOverride;

  Map<String, dynamic> get product => widget.product;

  List<String> get images {
    final raw = product['images'] as List? ?? [];
    return raw.cast<String>();
  }

  String get title => '${product['title'] ?? ''}';
  double get price => (product['price'] as num?)?.toDouble() ?? 0;
  String get description => '${product['description'] ?? ''}';
  String get status => _statusOverride ?? '${product['status'] ?? 'active'}';
  bool get isOutOfStock => status == 'out_of_stock';
  String get sellerId => '${(product['seller'] as Map?)?['id'] ?? product['seller_id'] ?? ''}';
  String get sellerName {
    final s = product['seller'] as Map<String, dynamic>?;
    return '${s?['display_name'] ?? 'Seller'}';
  }

  String? get myId => ref.read(authControllerProvider).user?['id'] as String?;
  bool get isOwner => sellerId == myId;

  Future<void> _chatSeller() async {
    try {
      final conversationId = await ref.read(chatRepositoryProvider).openDirect(sellerId);
      if (!mounted) return;

      final sellerMap = product['seller'] as Map<String, dynamic>? ?? {};
      final conversation = {
        'id': conversationId,
        'is_group': false,
        'name': null,
        'last_message_at': null,
        'unread_count': 0,
        'conversation_members': [
          {'user_id': sellerId, 'profiles': sellerMap},
          {'user_id': myId, 'profiles': ref.read(authControllerProvider).user},
        ],
        'messages': [],
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversation: conversation,
            productInquiry: {
              'id': '${product['id']}',
              'title': title,
              'price': price,
              'image_data_url': images.isNotEmpty ? images.first : null,
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  Future<void> _buyNow() async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      final result = await ref.read(paystackRepositoryProvider).initializePayment('${product['id']}');
      final url = result['authorization_url'] as String? ?? '';
      final reference = result['reference'] as String? ?? '';
      if (url.isEmpty) throw Exception('Could not get payment link');
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      // Chrome Custom Tab has closed — verify the payment
      if (reference.isNotEmpty && mounted) {
        await _verifyPayment(reference);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Future<void> _verifyPayment(String reference) async {
    try {
      final result = await ref.read(paystackRepositoryProvider).verifyPayment(reference);
      if (!mounted) return;
      if (result['status'] == 'success') {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Payment Successful 🎉'),
            content: Text('You have purchased "$title" for ₦${(result['amount'] as num?)?.toStringAsFixed(0) ?? price.toStringAsFixed(0)}.'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context); // go back to marketplace
                },
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      // Webhook handles fulfillment regardless — silently ignore verify errors
    }
  }

  Future<void> _toggleStock() async {
    if (_togglingStock) return;
    final newStatus = isOutOfStock ? 'active' : 'out_of_stock';
    setState(() => _togglingStock = true);
    try {
      await ref.read(productRepositoryProvider).updateProductStatus('${product['id']}', newStatus);
      if (mounted) setState(() { _statusOverride = newStatus; _togglingStock = false; });
    } catch (e) {
      if (mounted) { setState(() => _togglingStock = false); showApiError(context, e); }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Listing?'),
        content: const Text('This will permanently remove your product listing.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await ref.read(productRepositoryProvider).deleteProduct('${product['id']}');
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSold = status == 'sold';
    final priceStr = '₦${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (isOwner)
            IconButton(
              tooltip: 'Delete listing',
              onPressed: _deleting ? null : _delete,
              icon: _deleting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image gallery
            if (images.isNotEmpty)
              Stack(
                children: [
                  SizedBox(
                    height: 300,
                    width: double.infinity,
                    child: PageView.builder(
                      itemCount: images.length,
                      onPageChanged: (i) => setState(() => _imageIndex = i),
                      itemBuilder: (_, i) {
                        final bytes = _decodeDataUrl(images[i]);
                        return bytes != null
                            ? Image.memory(bytes, fit: BoxFit.cover)
                            : const Center(child: Icon(Icons.image_not_supported_rounded));
                      },
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 12,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(images.length, (i) => Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i == _imageIndex ? AppTheme.primary : Colors.white38,
                          ),
                        )),
                      ),
                    ),
                  if (isSold)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Text(
                            'SOLD',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: 3),
                          ),
                        ),
                      ),
                    )
                  else if (isOutOfStock)
                    Positioned(
                      top: 14,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Out of Stock',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        priceStr,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AssetAvatar(label: sellerName, imageUrl: '', size: 24),
                      const SizedBox(width: 8),
                      Text(
                        sellerName,
                        style: const TextStyle(color: AppTheme.muted, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Divider(color: AppTheme.border),
                    const SizedBox(height: 12),
                    Text(
                      description,
                      style: const TextStyle(height: 1.55, fontSize: 14, color: AppTheme.text),
                    ),
                  ],
                  const SizedBox(height: 28),
                  // ── Buyer view ──────────────────────────────────────────
                  if (!isOwner && !isSold) ...[
                    if (isOutOfStock) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, color: Colors.orange, size: 18),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'This item is currently out of stock. Chat the seller to ask when it will be available.',
                                style: TextStyle(color: Colors.orange, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _chatSeller,
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          label: const Text('Chat Seller'),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _chatSeller,
                              icon: const Icon(Icons.chat_bubble_outline_rounded),
                              label: const Text('Chat Seller'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _paying ? null : _buyNow,
                              icon: _paying
                                  ? const SizedBox.square(
                                      dimension: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.payment_rounded),
                              label: Text('Buy $priceStr'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ] else if (isSold) ...[
                    const Center(
                      child: Text(
                        'This item has been sold.',
                        style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  // ── Owner view ──────────────────────────────────────────
                  ] else ...[
                    // Stock toggle
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _togglingStock ? null : _toggleStock,
                        icon: _togglingStock
                            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(isOutOfStock ? Icons.check_circle_outline_rounded : Icons.inventory_2_outlined),
                        label: Text(isOutOfStock ? 'Mark Back In Stock' : 'Mark as Out of Stock'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isOutOfStock ? AppTheme.success : Colors.orange,
                          side: BorderSide(color: isOutOfStock ? AppTheme.success : Colors.orange),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.elevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.storefront_rounded, color: AppTheme.primary, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your listing. You can only delete it once any active orders are delivered.',
                              style: TextStyle(color: AppTheme.muted, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Uint8List? _decodeDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}
