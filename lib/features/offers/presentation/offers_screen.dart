import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/presentation/chat_screen.dart';
import '../../trades/presentation/start_trade_screen.dart';
import '../data/offer_repository.dart';
import 'create_offer_screen.dart';
import 'offer_widgets.dart';

class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key, this.initialMine = false});

  final bool initialMine;

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  String side = 'all';
  late bool showingMine;
  late Future<Map<String, dynamic>> future;
  String? openingOfferId;
  String? tradingOfferId;

  @override
  void initState() {
    super.initState();
    showingMine = widget.initialMine;
    future = load();
  }

  Future<Map<String, dynamic>> load() async {
    final repo = ref.read(offerRepositoryProvider);
    final offers = await repo.list(side: side, mine: showingMine);
    Map<String, dynamic> rates;
    try {
      rates = await repo.rates(localCurrency: 'NGN');
    } catch (_) {
      rates = {
        'source': 'unavailable',
        'local_currency': 'NGN',
        'coins': <dynamic>[],
      };
    }
    return {'offers': offers, 'rates': rates};
  }

  void refresh() => setState(() {
    future = load();
  });

  Future<void> openTrade(Map<String, dynamic> offer) async {
    final myId = ref.read(authControllerProvider).user?['id'];
    if ('${offer['user_id']}' == '$myId') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't trade your own offer.")),
      );
      return;
    }
    setState(() => tradingOfferId = '${offer['id']}');
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StartTradeScreen(offer: offer)),
    ).then((_) {
      if (mounted) setState(() => tradingOfferId = null);
    });
  }

  Future<void> openOffer(Map<String, dynamic> offer) async {
    if (showingMine) return;
    final id = '${offer['id']}';
    if (openingOfferId != null) return;
    setState(() => openingOfferId = id);
    try {
      final conversationId = await ref
          .read(offerRepositoryProvider)
          .openChat(id);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversation: {
              'id': conversationId,
              'is_group': false,
              'conversation_members': [
                {'user_id': offer['user_id'], 'profiles': offer['user']},
              ],
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => openingOfferId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Offers',
      subtitle: showingMine ? 'Manage your P2P ads' : 'Find P2P crypto trades',
      actions: [
        IconButton(
          tooltip: 'Create offer',
          icon: const Icon(Icons.add_rounded),
          onPressed: () =>
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateOfferScreen()),
              ).then((created) {
                if (created == true) {
                  showingMine = true;
                  refresh();
                }
              }),
        ),
      ],
      body: Column(
        children: [
          SegmentedButton<bool>(
            selected: {showingMine},
            onSelectionChanged: (value) {
              showingMine = value.first;
              refresh();
            },
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.storefront_rounded),
                label: Text('Marketplace'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.inventory_2_rounded),
                label: Text('My offers'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            selected: {side},
            onSelectionChanged: (value) {
              side = value.first;
              refresh();
            },
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'buy', label: Text('Buyers')),
              ButtonSegment(value: 'sell', label: Text('Sellers')),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: future,
              builder: (context, snapshot) => AsyncStateView<Map<String, dynamic>>(
                snapshot: snapshot,
                onRetry: refresh,
                builder: (data) {
                  final offers = data['offers'] as List<dynamic>;
                  final rates = data['rates'] as Map<String, dynamic>;
                  final rateByCoin = {
                    for (final row in (rates['coins'] as List? ?? []))
                      '${(row as Map)['coin']}': row,
                  };
                  if (offers.isEmpty) {
                    return EmptyState(
                      icon: showingMine
                          ? Icons.inventory_2_outlined
                          : Icons.local_offer_outlined,
                      title: showingMine
                          ? 'No offers created'
                          : 'No offers yet',
                      message: showingMine
                          ? 'Create an offer so other traders can find you from the marketplace.'
                          : 'Create the first P2P offer or adjust your filters.',
                      action: FilledButton.icon(
                        onPressed: () =>
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const CreateOfferScreen(),
                              ),
                            ).then((created) {
                              if (created == true) {
                                showingMine = true;
                                refresh();
                              }
                            }),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create offer'),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: () async => refresh(),
                    child: ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: offers.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final offer = offers[index] as Map<String, dynamic>;
                        return Stack(
                          children: [
                            OfferCard(
                              offer: offer,
                              marketRate: rateByCoin['${offer['coin']}'],
                              onTap: showingMine
                                  ? () {}
                                  : () => openOffer(offer),
                              onTrade: showingMine
                                  ? null
                                  : () => openTrade(offer),
                            ),
                            if (openingOfferId == '${offer['id']}')
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: AppTheme.background.withValues(
                                      alpha: 0.45,
                                    ),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
