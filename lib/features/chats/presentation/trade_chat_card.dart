import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../trades/presentation/trade_detail_screen.dart';

class TradeProposalCard extends StatelessWidget {
  const TradeProposalCard({super.key, required this.trade});

  final Map trade;

  @override
  Widget build(BuildContext context) {
    final coin = '${trade['coin'] ?? ''}';
    final crypto = double.tryParse('${trade['crypto_amount'] ?? ''}') ?? 0;
    final fiat = double.tryParse('${trade['fiat_amount'] ?? ''}') ?? 0;
    final currency = '${trade['fiat_currency'] ?? ''}';
    final rate = double.tryParse('${trade['rate'] ?? ''}') ?? 0;
    final payment = '${trade['payment_method'] ?? ''}';
    final status = '${trade['status'] ?? 'awaiting_escrow'}';

    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Trade Proposal',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              _StatusDot(status: status),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${crypto.toStringAsFixed(8)} $coin',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 2),
          Text(
            '${fiat.toStringAsFixed(2)} $currency  ·  Rate: ${rate.toStringAsFixed(2)}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          if (payment.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'via $payment',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TradeDetailScreen(trade: Map<String, dynamic>.from(trade)),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('View Trade'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primary,
              side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: const Size(0, 36),
            ),
          ),
        ],
      ),
    );
  }
}

class TradeUpdateCard extends StatelessWidget {
  const TradeUpdateCard({super.key, required this.body, required this.trade});

  final String body;
  final Map? trade;

  @override
  Widget build(BuildContext context) {
    final coin = '${trade?['coin'] ?? ''}';
    final status = '${trade?['status'] ?? ''}';
    final (color, icon) = _statusMeta(status);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            body.isEmpty && coin.isNotEmpty
                ? 'Trade update · $coin'
                : body,
            style: TextStyle(
              fontSize: 12.5,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  static (Color, IconData) _statusMeta(String status) => switch (status) {
        'escrowed' => (AppTheme.accent, Icons.lock_rounded),
        'payment_sent' => (AppTheme.primary, Icons.receipt_long_rounded),
        'completed' => (AppTheme.success, Icons.check_circle_rounded),
        'cancelled' => (AppTheme.danger, Icons.cancel_rounded),
        'disputed' => (AppTheme.warning, Icons.gavel_rounded),
        _ => (AppTheme.muted, Icons.info_outline_rounded),
      };
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'awaiting_escrow' => AppTheme.warning,
      'escrowed' => AppTheme.accent,
      'payment_sent' => AppTheme.primary,
      'completed' => AppTheme.success,
      'cancelled' || 'disputed' => AppTheme.danger,
      _ => AppTheme.muted,
    };
    final label = switch (status) {
      'awaiting_escrow' => 'Awaiting escrow',
      'escrowed' => 'Escrowed',
      'payment_sent' => 'Payment sent',
      'releasing' => 'Releasing',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      'disputed' => 'Disputed',
      _ => status,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
