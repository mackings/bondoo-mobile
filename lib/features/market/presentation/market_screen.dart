import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chat_repository.dart';
import '../../chats/presentation/chat_screen.dart';
import '../../trades/data/trade_repository.dart';

class MarketScreen extends ConsumerStatefulWidget {
  const MarketScreen({super.key});

  @override
  ConsumerState<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends ConsumerState<MarketScreen> {
  List<dynamic>? _traders;
  bool _loading = true;
  String? _error;
  String? _filterType;
  String? _filterCoin;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final traders = await ref.read(tradeRepositoryProvider).getMarket(
        type: _filterType,
        coin: _filterCoin,
      );
      if (mounted) setState(() { _traders = traders; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Market',
      subtitle: 'Live traders ready to deal',
      body: Column(
        children: [
          _FilterBar(
            filterType: _filterType,
            filterCoin: _filterCoin,
            onChanged: (type, coin) {
              setState(() { _filterType = type; _filterCoin = coin; });
              _load();
            },
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    final traders = _traders ?? [];
    if (traders.isEmpty) {
      return const EmptyState(
        icon: Icons.storefront_rounded,
        title: 'No active traders',
        message: 'No one is currently advertising to buy or sell. Check back soon, or set your own status in Profile.',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
        itemCount: traders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final trader = traders[i] as Map<String, dynamic>;
          return _TraderCard(trader: trader);
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filterType,
    required this.filterCoin,
    required this.onChanged,
  });

  final String? filterType;
  final String? filterCoin;
  final void Function(String? type, String? coin) onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _Chip(
            label: 'All',
            selected: filterType == null,
            onTap: () => onChanged(null, filterCoin),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Sellers',
            selected: filterType == 'selling',
            onTap: () => onChanged(filterType == 'selling' ? null : 'selling', filterCoin),
          ),
          const SizedBox(width: 8),
          _Chip(
            label: 'Buyers',
            selected: filterType == 'buying',
            onTap: () => onChanged(filterType == 'buying' ? null : 'buying', filterCoin),
          ),
          const SizedBox(width: 16),
          for (final coin in ['BTC', 'ETH', 'USDT', 'USDC']) ...[
            _Chip(
              label: coin,
              selected: filterCoin == coin,
              onTap: () => onChanged(filterType, filterCoin == coin ? null : coin),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.elevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppTheme.primary : AppTheme.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TraderCard extends ConsumerWidget {
  const _TraderCard({required this.trader});
  final Map<String, dynamic> trader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = trader['trade_status'] as Map<String, dynamic>?;
    if (status == null) return const SizedBox.shrink();

    final name = '${trader['display_name'] ?? trader['username'] ?? 'Trader'}';
    final username = '${trader['username'] ?? ''}';
    final avatarUrl = '${trader['avatar_url'] ?? ''}';
    final type = '${status['type'] ?? ''}';
    final coin = '${status['coin'] ?? ''}';
    final network = '${status['network'] ?? ''}';
    final paymentMethod = '${status['payment_method'] ?? ''}';
    final rate = status['rate'] != null
        ? double.tryParse('${status['rate']}')
        : null;
    final currency = (trader['bank_accounts'] as List?)?.isNotEmpty == true
        ? '${(trader['bank_accounts'] as List).first['currency'] ?? ''}'
        : '';

    final isSelling = type == 'selling';
    final typeColor = isSelling ? AppTheme.success : AppTheme.accent;
    final typeLabel = isSelling ? 'Selling' : 'Buying';

    return GestureDetector(
      onTap: () => _openChat(context, ref, trader),
      child: ExchangeCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            AssetAvatar(label: name, imageUrl: avatarUrl, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '$typeLabel $coin',
                          style: TextStyle(color: typeColor, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '@$username · $network',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  if (rate != null && currency.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Rate: ${rate.toStringAsFixed(2)} $currency/$coin',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                  if (paymentMethod.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'via $paymentMethod',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.muted, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _openChat(BuildContext context, WidgetRef ref, Map<String, dynamic> trader) async {
    final myId = ref.read(authControllerProvider).user?['id'];
    final traderId = '${trader['id'] ?? ''}';
    if (traderId.isEmpty || traderId == myId) return;

    try {
      final conversationId = await ref.read(chatRepositoryProvider).openDirect(traderId);
      if (!context.mounted) return;
      // Build a minimal conversation map for ChatScreen
      final conversation = {
        'id': conversationId,
        'is_group': false,
        'name': null,
        'last_message_at': null,
        'unread_count': 0,
        'conversation_members': [
          {
            'user_id': traderId,
            'profiles': trader,
          },
          {
            'user_id': myId,
            'profiles': ref.read(authControllerProvider).user,
          },
        ],
        'messages': [],
      };
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: conversation)),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}
