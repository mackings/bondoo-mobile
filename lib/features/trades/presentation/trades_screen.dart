import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/coin_logo.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/trade_events.dart';
import '../data/trade_repository.dart';
import 'trade_detail_screen.dart';

class TradesScreen extends ConsumerStatefulWidget {
  const TradesScreen({super.key});

  @override
  ConsumerState<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends ConsumerState<TradesScreen> {
  List<dynamic>? _trades;
  bool _initialLoading = true;
  String? _error;
  Timer? _pollingTimer;
  StreamSubscription<String>? _eventSub;

  @override
  void initState() {
    super.initState();
    _loadTrades(initial: true);
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) => _loadTrades());
    _eventSub = TradeEvents.instance.onTradeUpdated.listen((_) => _loadTrades());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _loadTrades({bool initial = false}) async {
    if (initial) setState(() => _initialLoading = true);
    try {
      final trades = await ref.read(tradeRepositoryProvider).list();
      if (mounted) {
        setState(() {
          _trades = trades;
          _initialLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && initial) {
        setState(() {
          _initialLoading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Trades',
      subtitle: 'Your P2P trade history',
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: () => _loadTrades(initial: true), child: const Text('Retry')),
          ],
        ),
      );
    }
    final trades = _trades ?? [];
    if (trades.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_horiz_rounded,
        title: 'No trades yet',
        message: 'Visit the Offers tab to start a P2P trade.',
      );
    }
    return RefreshIndicator(
      onRefresh: () => _loadTrades(),
      child: ListView.separated(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: trades.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final trade = trades[index] as Map<String, dynamic>;
          return _TradeCard(
            trade: trade,
            myId: ref.read(authControllerProvider).user?['id'] ?? '',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TradeDetailScreen(trade: trade),
              ),
            ).then((_) => _loadTrades()),
          );
        },
      ),
    );
  }
}

class _TradeCard extends StatelessWidget {
  const _TradeCard({
    required this.trade,
    required this.myId,
    required this.onTap,
  });

  final Map<String, dynamic> trade;
  final String myId;
  final VoidCallback onTap;

  bool get _isBuyer => trade['buyer_user_id'] == myId;
  String get _status => '${trade['status']}';
  String get _coin => '${trade['coin']}';
  double get _cryptoAmount => double.tryParse('${trade['crypto_amount']}') ?? 0;
  double get _fiatAmount => double.tryParse('${trade['fiat_amount']}') ?? 0;
  String get _currency => '${trade['fiat_currency']}';

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = _statusMeta(_status);
    final counterParty = _isBuyer
        ? (trade['seller'] as Map?)
        : (trade['buyer'] as Map?);
    final counterName = counterParty != null
        ? '${counterParty['display_name'] ?? counterParty['username'] ?? 'Trader'}'
        : 'Trader';

    return GestureDetector(
      onTap: onTap,
      child: ExchangeCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CoinLogo(coin: _coin),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _isBuyer ? 'Buying $_coin' : 'Selling $_coin',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      _StatusChip(label: label, color: color, icon: icon),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_cryptoAmount.toStringAsFixed(8)} $_coin · ${_fiatAmount.toStringAsFixed(2)} $_currency',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isBuyer ? 'with $counterName (Seller)' : 'with $counterName (Buyer)',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.muted, size: 20),
          ],
        ),
      ),
    );
  }

  static (String, Color, IconData) _statusMeta(String status) => switch (status) {
        'awaiting_escrow' => ('Awaiting Escrow', AppTheme.warning, Icons.hourglass_top_rounded),
        'escrowed' => ('Escrowed', AppTheme.accent, Icons.lock_rounded),
        'payment_sent' => ('Payment Sent', AppTheme.primary, Icons.receipt_long_rounded),
        'releasing' => ('Releasing', AppTheme.primary, Icons.send_rounded),
        'completed' => ('Completed', AppTheme.success, Icons.check_circle_rounded),
        'cancelled' => ('Cancelled', AppTheme.danger, Icons.cancel_rounded),
        'disputed' => ('Disputed', AppTheme.warning, Icons.gavel_rounded),
        'refunded' => ('Refunded', AppTheme.accent, Icons.undo_rounded),
        _ => ('Unknown', AppTheme.muted, Icons.help_rounded),
      };
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, required this.icon});
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
