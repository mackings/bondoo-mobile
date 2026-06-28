import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../data/wallet_repository.dart';

final money = NumberFormat.currency(symbol: r'$');

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  late Future<Map<String, dynamic>> future = load();

  Future<Map<String, dynamic>> load() =>
      ref.read(walletRepositoryProvider).summary();

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Wallet',
      subtitle: 'Balances and BTC deposits',
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) => AsyncStateView<Map<String, dynamic>>(
          snapshot: snapshot,
          onRetry: () => setState(() {
            future = load();
          }),
          builder: (data) {
            final wallets = (data['wallets'] as List).cast<Map>();
            final bank = '${(data['config'] as Map)['bank_btc_address']}';
            final balances = {
              for (final wallet in wallets)
                '${wallet['asset']}': double.parse('${wallet['balance']}'),
            };
            final total =
                (balances['BTC'] ?? 0) * 68000 +
                (balances['ETH'] ?? 0) * 3200 +
                (balances['USDC'] ?? 0);
            return RefreshIndicator(
              onRefresh: () async => setState(() {
                future = load();
              }),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  ExchangeCard(
                    padding: const EdgeInsets.all(22),
                    gradient: LinearGradient(
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.42),
                        AppTheme.backgroundSoft,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderColor: Colors.white12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.account_balance_wallet_rounded,
                              color: Colors.white70,
                              size: 19,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Total portfolio',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          money.format(total),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                        ),
                        const SizedBox(height: 18),
                        const Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            StatusPill(
                              label: 'Secure ledger',
                              icon: Icons.shield_outlined,
                            ),
                            StatusPill(
                              label: 'Verified',
                              color: AppTheme.success,
                              icon: Icons.verified_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel(
                    'Your assets',
                    caption: 'Live balances in your BONDOO wallet',
                    icon: Icons.donut_large_rounded,
                  ),
                  for (final asset in ['BTC', 'ETH', 'USDC'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: ExchangeCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            AssetAvatar(
                              label: asset,
                              color: asset == 'BTC'
                                  ? const Color(0xffffa726)
                                  : asset == 'ETH'
                                  ? const Color(0xff7a8cff)
                                  : AppTheme.success,
                              icon: asset == 'BTC'
                                  ? Icons.currency_bitcoin_rounded
                                  : asset == 'ETH'
                                  ? Icons.diamond_outlined
                                  : Icons.attach_money_rounded,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    asset,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    asset == 'BTC'
                                        ? 'Bitcoin'
                                        : asset == 'ETH'
                                        ? 'Ethereum'
                                        : 'USD Coin',
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              (balances[asset] ?? 0).toStringAsFixed(
                                asset == 'USDC' ? 2 : 8,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const SectionLabel(
                    'Deposit Bitcoin',
                    caption: 'Scan or use the address below',
                    icon: Icons.qr_code_scanner_rounded,
                  ),
                  ExchangeCard(
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            AssetAvatar(
                              label: 'BTC',
                              icon: Icons.currency_bitcoin_rounded,
                              color: Color(0xffffa726),
                              size: 42,
                            ),
                            SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                'Bitcoin deposit address',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                            ),
                            StatusPill(label: 'BTC', color: Color(0xffffa726)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: QrImageView(data: 'bitcoin:$bank', size: 180),
                        ),
                        const SizedBox(height: 14),
                        SelectableText(
                          bank,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryBright,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const InfoBanner(
                          icon: Icons.info_outline_rounded,
                          title: 'Bitcoin only',
                          message:
                              'Send BTC from a linked wallet. Your BONDOO balance is credited after confirmation.',
                          color: Color(0xffffa726),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
