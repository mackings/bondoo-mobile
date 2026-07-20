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

  Map<String, dynamic> get product => widget.product;

  List<String> get images {
    final raw = product['images'] as List? ?? [];
    return raw.cast<String>();
  }

  String get title => '${product['title'] ?? ''}';
  double get price => (product['price'] as num?)?.toDouble() ?? 0;
  String get description => '${product['description'] ?? ''}';
  String get status => '${product['status'] ?? 'active'}';
  String get sellerId => '${(product['seller'] as Map?)?['id'] ?? product['seller_id'] ?? ''}';
  String get sellerName {
    final s = product['seller'] as Map<String, dynamic>?;
    return '${s?['display_name'] ?? s?['username'] ?? 'Seller'}';
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
      if (url.isEmpty) throw Exception('Could not get payment link');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Could not open payment page');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _paying = false);
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
                  if (!isOwner && !isSold) ...[
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
                  ] else if (isSold) ...[
                    const Center(
                      child: Text(
                        'This item has been sold.',
                        style: TextStyle(color: AppTheme.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.elevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.storefront_rounded, color: AppTheme.primary, size: 18),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'This is your listing. Buyers can contact you via Chat.',
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
