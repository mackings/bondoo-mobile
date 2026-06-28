import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/coin_logo.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/trade_repository.dart';
import 'trade_detail_screen.dart';

const _networks = {
  'BTC':  ['BTC'],
  'ETH':  ['ERC20'],
  'USDT': ['TRC20', 'ERC20', 'BSC'],
  'USDC': ['ERC20', 'BSC'],
};

// Native coins whose escrow deposit equals cryptoAmount + gas
const _nativeCoins = {'ETH', 'BNB', 'BTC', 'TRX'};

class StartTradeScreen extends ConsumerStatefulWidget {
  const StartTradeScreen({super.key, required this.offer});
  final Map<String, dynamic> offer;

  @override
  ConsumerState<StartTradeScreen> createState() => _StartTradeScreenState();
}

class _StartTradeScreenState extends ConsumerState<StartTradeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fiatCtrl = TextEditingController();
  final _walletCtrl = TextEditingController();
  String? _network;
  bool _loading = false;

  Map get offer => widget.offer;
  String get coin => '${offer['coin']}';
  double get rate => double.tryParse('${offer['rate']}') ?? 0;
  double get minFiat => double.tryParse('${offer['min_fiat_amount']}') ?? 0;
  double get maxFiat => double.tryParse('${offer['max_fiat_amount']}') ?? 0;
  String get currency => '${offer['fiat_currency']}';
  List<String> get networks => _networks[coin] ?? ['BTC'];

  double get cryptoAmount {
    final fiat = double.tryParse(_fiatCtrl.text) ?? 0;
    return rate > 0 ? fiat / rate : 0;
  }

  bool get isNative => _nativeCoins.contains(coin.toUpperCase());

  @override
  void initState() {
    super.initState();
    _network = networks.first;
    _fiatCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _fiatCtrl.dispose();
    _walletCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final trade = await ref.read(tradeRepositoryProvider).create(
            offerId: '${offer['id']}',
            fiatAmount: double.parse(_fiatCtrl.text),
            network: _network!,
            buyerWalletAddress: _walletCtrl.text.trim(),
            buyerWalletNetwork: _network!,
          );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => TradeDetailScreen(trade: trade)),
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = offer['user'] as Map?;
    final crypto = cryptoAmount;

    // Estimate fees from cached offer data for preview (live quote comes after create)
    final estimatedPlatformFeeRate = 0.01; // 1% default
    final estPlatformFee = crypto * estimatedPlatformFeeRate;
    final estPayout = crypto - estPlatformFee;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Start Trade'),
        backgroundColor: AppTheme.backgroundSoft,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Offer summary ───────────────────────────────────────────
              ExchangeCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CoinLogo(coin: coin),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${offer['side']}'.toUpperCase() == 'SELL'
                                ? 'Buying $coin from'
                                : 'Selling $coin to',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12),
                          ),
                          Text(
                            user != null
                                ? '${user['display_name'] ?? user['username']}'
                                : 'Trader',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${rate.toStringAsFixed(2)} $currency',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primaryBright,
                          ),
                        ),
                        Text('per $coin',
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── Fiat amount ─────────────────────────────────────────────
              _Label('Amount to pay ($currency)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _fiatCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d+\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  hintText:
                      '${minFiat.toStringAsFixed(0)} – ${maxFiat.toStringAsFixed(0)}',
                  prefixText: '$currency ',
                  suffixText: coin,
                ),
                validator: (v) {
                  final val = double.tryParse(v ?? '');
                  if (val == null || val <= 0) return 'Enter a valid amount';
                  if (val < minFiat) {
                    return 'Minimum is ${minFiat.toStringAsFixed(0)} $currency';
                  }
                  if (val > maxFiat) {
                    return 'Maximum is ${maxFiat.toStringAsFixed(0)} $currency';
                  }
                  return null;
                },
              ),

              // ── Fee breakdown (shown once user types an amount) ─────────
              if (crypto > 0) ...[
                const SizedBox(height: 12),
                _FeeBreakdownCard(
                  coin: coin,
                  cryptoAmount: crypto,
                  estPlatformFee: estPlatformFee,
                  estPayout: estPayout,
                  isNative: isNative,
                ),
              ],
              const SizedBox(height: 20),

              // ── Network ─────────────────────────────────────────────────
              _Label('Network'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _network,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lan_rounded)),
                dropdownColor: AppTheme.surface,
                items: networks
                    .map((n) =>
                        DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setState(() => _network = v),
              ),
              const SizedBox(height: 20),

              // ── Wallet address ──────────────────────────────────────────
              _Label('Your $coin wallet address'),
              const SizedBox(height: 4),
              const Text(
                'Crypto will be sent here when the trade completes.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _walletCtrl,
                decoration: const InputDecoration(
                  hintText: 'Paste your wallet address',
                  prefixIcon:
                      Icon(Icons.account_balance_wallet_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().length < 10) {
                    return 'Enter a valid wallet address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // ── Payment method ──────────────────────────────────────────
              ExchangeCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.payment_rounded,
                        color: AppTheme.muted, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Payment: ${offer['payment_method']}',
                        style: const TextStyle(
                            color: AppTheme.muted, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              if ('${offer['terms'] ?? ''}'.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                ExchangeCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          color: AppTheme.muted, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${offer['terms']}',
                          style: const TextStyle(
                              color: AppTheme.muted,
                              fontSize: 13,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),

              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Confirm Trade'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Fee breakdown card ───────────────────────────────────────────────────────

class _FeeBreakdownCard extends StatelessWidget {
  const _FeeBreakdownCard({
    required this.coin,
    required this.cryptoAmount,
    required this.estPlatformFee,
    required this.estPayout,
    required this.isNative,
  });

  final String coin;
  final double cryptoAmount;
  final double estPlatformFee;
  final double estPayout;
  final bool isNative;

  String _fmt(double v) => v.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          _Row(
            label: 'Trade amount',
            value: '${_fmt(cryptoAmount)} $coin',
            isBold: false,
          ),
          const Divider(height: 16, color: AppTheme.backgroundSoft),
          _Row(
            label: 'Platform fee (~1%)',
            value: '- ${_fmt(estPlatformFee)} $coin',
            valueColor: Colors.orange,
          ),
          if (isNative) ...[
            const SizedBox(height: 4),
            _Row(
              label: 'Network gas fee',
              value: 'Estimated at trade creation',
              valueColor: AppTheme.muted,
              isBold: false,
              isSmall: true,
            ),
          ],
          const Divider(height: 16, color: AppTheme.backgroundSoft),
          _Row(
            label: 'You receive ≈',
            value: '${_fmt(estPayout)} $coin',
            valueColor: AppTheme.primaryBright,
            isBold: true,
          ),
          if (isNative) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 13, color: Colors.blue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The exact deposit amount (including gas) is shown after confirming.',
                      style: TextStyle(
                          color: Colors.blue.shade300,
                          fontSize: 11,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
    this.isSmall = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;
  final bool isSmall;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
                color: AppTheme.muted,
                fontSize: isSmall ? 11 : 13)),
        Text(value,
            style: TextStyle(
              color: valueColor,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              fontSize: isSmall ? 11 : 13,
            )),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}
