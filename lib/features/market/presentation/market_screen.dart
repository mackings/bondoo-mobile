import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/product_repository.dart';
import '../data/story_repository.dart';
import 'product_create_sheet.dart';
import 'product_detail_screen.dart';
import 'story_creator.dart';
import 'story_viewer.dart';

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  List<Map<String, dynamic>> _products = [];
  bool _productsLoading = true;

  List<Map<String, dynamic>> _stories = [];
  Map<String, dynamic>? _myStory;
  bool _storiesLoading = true;

  StreamSubscription<Map<String, dynamic>>? _newStorySub;
  StreamSubscription<String>? _storyDeletedSub;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadStories().then((_) => _subscribeStories());
  }

  @override
  void dispose() {
    _newStorySub?.cancel();
    _storyDeletedSub?.cancel();
    super.dispose();
  }

  void _subscribeStories() {
    final myId = ref.read(authControllerProvider).user?['id'] as String?;
    _newStorySub = SocketService().onNewStory.listen((story) {
      if (!mounted) return;
      if ('${story['user_id']}' == myId) return;
      _loadStories();
    });
    _storyDeletedSub = SocketService().onStoryDeleted.listen((userId) {
      if (!mounted) return;
      final myId = ref.read(authControllerProvider).user?['id'] as String?;
      setState(() {
        _stories = _stories.where((s) => '${s['user_id']}' != userId).toList();
        if (userId == myId) _myStory = null;
      });
    });
  }

  Future<void> _loadProducts() async {
    if (mounted) setState(() => _productsLoading = true);
    try {
      final products = await ref.read(productRepositoryProvider).getProducts();
      if (mounted) setState(() { _products = products; _productsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _productsLoading = false);
    }
  }

  Future<void> _loadStories() async {
    if (mounted) setState(() => _storiesLoading = true);
    try {
      final repo = ref.read(storyRepositoryProvider);
      final results = await Future.wait([repo.getStories(), repo.getMyStory()]);
      if (mounted) {
        setState(() {
          _stories = results[0] as List<Map<String, dynamic>>;
          _myStory = results[1] as Map<String, dynamic>?;
          _storiesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _storiesLoading = false);
    }
  }

  Future<void> _openStoryCreator() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const StoryCreatorSheet(),
    );
    if (result == 'created') _loadStories();
  }

  Future<void> _openMyStoryViewers() async {
    if (_myStory == null) return;
    final result = await Navigator.push<String>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => StoryViewer(story: _myStory!, isOwnStory: true),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
    if (result == 'deleted') {
      if (mounted) setState(() => _myStory = null);
    } else {
      _loadStories();
    }
  }

  Future<void> _openStory(Map<String, dynamic> story) async {
    await Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => StoryViewer(story: story),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
    _loadStories();
  }

  Future<void> _openCreateSheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const ProductCreateSheet(),
    );
    if (result == 'created') _loadProducts();
  }

  Future<void> _openProduct(Map<String, dynamic> product) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product)),
    );
    if (result == 'deleted') _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async { await _loadProducts(); await _loadStories(); },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Row(
                    children: [
                      const Text('Market', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _openCreateSheet,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('List Product'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Stories row
              SliverToBoxAdapter(
                child: _StoriesRow(
                  stories: _stories,
                  myStory: _myStory,
                  loading: _storiesLoading,
                  onAddStory: _openStoryCreator,
                  onMyStory: _openMyStoryViewers,
                  onStoryTap: _openStory,
                ),
              ),

              // Products section header
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                  child: Text('Latest Listings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),

              // Products grid
              if (_productsLoading)
                const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())))
              else if (_products.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.storefront_outlined,
                    title: 'No listings yet',
                    message: 'Be the first to list a product. Tap "List Product" to get started.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  sliver: SliverGrid.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                    children: _products.map((p) => _ProductCard(product: p, onTap: () => _openProduct(p))).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Product card ─────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final images = (product['images'] as List? ?? []).cast<String>();
    final title = '${product['title'] ?? ''}';
    final price = (product['price'] as num?)?.toDouble() ?? 0;
    final isSold = '${product['status']}' == 'sold';
    final priceStr = '₦${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    final seller = product['seller'] as Map<String, dynamic>?;
    final sellerName = '${seller?['display_name'] ?? seller?['username'] ?? ''}';

    Uint8List? thumb;
    if (images.isNotEmpty) {
      final comma = images.first.indexOf(',');
      if (comma >= 0) {
        try { thumb = base64Decode(images.first.substring(comma + 1)); } catch (_) {}
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumb != null
                      ? Image.memory(thumb, fit: BoxFit.cover)
                      : Container(
                          color: AppTheme.elevated,
                          child: const Icon(Icons.image_outlined, color: AppTheme.muted, size: 36),
                        ),
                  if (isSold)
                    Container(
                      color: Colors.black45,
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(20)),
                        child: const Text('SOLD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 2)),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.3)),
                    const Spacer(),
                    Text(priceStr, style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w900, fontSize: 14)),
                    if (sellerName.isNotEmpty)
                      Text('@$sellerName', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.muted, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stories row ─────────────────────────────────────────────────────────────

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({
    required this.stories,
    required this.myStory,
    required this.loading,
    required this.onAddStory,
    required this.onMyStory,
    required this.onStoryTap,
  });

  final List<Map<String, dynamic>> stories;
  final Map<String, dynamic>? myStory;
  final bool loading;
  final VoidCallback onAddStory;
  final VoidCallback onMyStory;
  final void Function(Map<String, dynamic>) onStoryTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: loading
          ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          : ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              children: [
                _StoryTile(
                  label: 'My Story',
                  avatarUrl: '',
                  isMe: true,
                  hasStory: myStory != null,
                  viewed: false,
                  onTap: myStory != null ? onMyStory : onAddStory,
                ),
                for (final story in stories) ...[
                  const SizedBox(width: 12),
                  _StoryTile(
                    label: () {
                      final u = story['user'] as Map<String, dynamic>?;
                      return '${u?['display_name'] ?? u?['username'] ?? 'User'}';
                    }(),
                    avatarUrl: () {
                      final u = story['user'] as Map<String, dynamic>?;
                      return '${u?['avatar_url'] ?? ''}';
                    }(),
                    isMe: false,
                    hasStory: true,
                    viewed: story['viewed_by_me'] == true,
                    onTap: () => onStoryTap(story),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.label,
    required this.avatarUrl,
    required this.isMe,
    required this.hasStory,
    required this.viewed,
    required this.onTap,
  });

  final String label;
  final String avatarUrl;
  final bool isMe;
  final bool hasStory;
  final bool viewed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ringColor = viewed
        ? AppTheme.muted
        : isMe && !hasStory
            ? AppTheme.border
            : AppTheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ringColor, width: hasStory || isMe ? 2.5 : 0),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(
                    child: isMe && !hasStory
                        ? Container(
                            color: AppTheme.elevated,
                            child: const Icon(Icons.add_rounded, color: AppTheme.primary, size: 26),
                          )
                        : AssetAvatar(label: label, imageUrl: avatarUrl, size: 48),
                  ),
                ),
                if (isMe && !hasStory)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                      child: const Icon(Icons.add, color: Colors.white, size: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isMe ? 'My Story' : label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: viewed ? AppTheme.muted : AppTheme.text),
            ),
          ],
        ),
      ),
    );
  }
}
