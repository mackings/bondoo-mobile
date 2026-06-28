import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/coin_logo.dart';
import '../../../shared/widgets/exchange_ui.dart';

final fiatFormat = NumberFormat.currency(symbol: '');
final compactNumber = NumberFormat('#,##0.########');
final compactCurrency = NumberFormat.compactCurrency(symbol: '');

String offerTitle(Map offer) {
  final side = '${offer['side']}'.toUpperCase();
  return '$side ${offer['coin']}';
}

class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.offer,
    required this.onTap,
    this.marketRate,
    this.onTrade,
  });

  final Map offer;
  final VoidCallback onTap;
  final Map? marketRate;
  final VoidCallback? onTrade;

  @override
  Widget build(BuildContext context) {
    final side = '${offer['side']}';
    final sideColor = side == 'buy' ? AppTheme.success : AppTheme.warning;
    final currency = '${offer['fiat_currency']}';
    final user = offer['user'] as Map?;
    final rate = double.parse('${offer['rate']}');
    final localCurrency = '${marketRate?['local_currency'] ?? 'NGN'}';
    final localRate = double.tryParse('${marketRate?['local'] ?? ''}');
    final usdRate = double.tryParse('${marketRate?['usd'] ?? ''}');
    final change = double.tryParse('${marketRate?['usd_24h_change'] ?? ''}');
    final localOfferRate =
        currency.toUpperCase() == localCurrency && localRate != null
        ? rate
        : currency.toUpperCase() == 'USD' &&
              localRate != null &&
              usdRate != null &&
              usdRate > 0
        ? rate * (localRate / usdRate)
        : null;
    final premium =
        currency.toUpperCase() == 'USD' && usdRate != null && usdRate > 0
        ? ((rate - usdRate) / usdRate) * 100
        : localOfferRate != null && localRate != null && localRate > 0
        ? ((localOfferRate - localRate) / localRate) * 100
        : null;
    return ExchangeCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CoinLogo(coin: '${offer['coin']}'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offerTitle(offer),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        user == null
                            ? 'BONDOO trader'
                            : '${user['display_name']} · @${user['username']}',
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: side == 'buy' ? 'Buying' : 'Selling',
                  color: sideColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (marketRate != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.public_rounded,
                      color: AppTheme.primaryBright,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Global: ${_money(usdRate, 'USD')} / ${_money(localRate, localCurrency)}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (change != null)
                      Text(
                        '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: change >= 0
                              ? AppTheme.success
                              : AppTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    label: 'Rate',
                    value: '${fiatFormat.format(rate)} $currency',
                    subvalue: localOfferRate == null
                        ? null
                        : '≈ ${_money(localOfferRate, localCurrency)}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Metric(
                    label: 'Available',
                    value:
                        '${compactNumber.format(double.parse('${offer['crypto_amount']}'))} ${offer['coin']}',
                    subvalue: localOfferRate == null
                        ? null
                        : '≈ ${_money(localOfferRate * double.parse('${offer['crypto_amount']}'), localCurrency)}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${offer['payment_method']} · ${fiatFormat.format(double.parse('${offer['min_fiat_amount']}'))} - ${fiatFormat.format(double.parse('${offer['max_fiat_amount']}'))} $currency',
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                ),
                if (premium != null)
                  StatusPill(
                    label:
                        '${premium >= 0 ? '+' : ''}${premium.toStringAsFixed(1)}%',
                    color: premium.abs() <= 2
                        ? AppTheme.success
                        : premium > 0
                        ? AppTheme.warning
                        : AppTheme.accent,
                  ),
              ],
            ),
            if (onTrade != null) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onTap,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.muted,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      label: const Text('Chat'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onTrade,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      label: const Text('Trade'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class OfferMessageCard extends StatefulWidget {
  const OfferMessageCard({super.key, required this.offer});

  final Map offer;

  @override
  State<OfferMessageCard> createState() => _OfferMessageCardState();
}

class _OfferMessageCardState extends State<OfferMessageCard> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: InkWell(
        onTap: () => setState(() => expanded = !expanded),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CoinLogo(coin: '${offer['coin']}', size: 38),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offerTitle(offer),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${offer['crypto_amount']} ${offer['coin']} at ${offer['rate']} ${offer['fiat_currency']}',
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AppTheme.muted,
                ),
              ],
            ),
            if (expanded) ...[
              const SizedBox(height: 10),
              _OfferDetailRow(
                label: 'Limits',
                value:
                    '${fiatFormat.format(double.parse('${offer['min_fiat_amount']}'))} - ${fiatFormat.format(double.parse('${offer['max_fiat_amount']}'))} ${offer['fiat_currency']}',
              ),
              _OfferDetailRow(
                label: 'Payment',
                value: '${offer['payment_method'] ?? 'Not specified'}',
              ),
              if ('${offer['terms'] ?? ''}'.trim().isNotEmpty)
                _OfferDetailRow(label: 'Terms', value: '${offer['terms']}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferDetailRow extends StatelessWidget {
  const _OfferDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.subvalue});

  final String label;
  final String value;
  final String? subvalue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.elevated.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (subvalue != null) ...[
            const SizedBox(height: 2),
            Text(
              subvalue!,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

String _money(double? value, String currency) {
  if (value == null) return '-- $currency';
  final formatted = value >= 100000
      ? compactCurrency.format(value)
      : fiatFormat.format(value);
  return '$formatted $currency';
}
