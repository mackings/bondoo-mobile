import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/forms/thousands_input_formatter.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/coin_logo.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../data/offer_repository.dart';

class CreateOfferScreen extends ConsumerStatefulWidget {
  const CreateOfferScreen({super.key});

  @override
  ConsumerState<CreateOfferScreen> createState() => _CreateOfferScreenState();
}

class _CreateOfferScreenState extends ConsumerState<CreateOfferScreen>
    with SingleTickerProviderStateMixin {
  final _pageCtrl = PageController();
  int _step = 0;

  // ── form values ──────────────────────────────────────────────────────────
  String side = 'sell';
  String coin = 'BTC';
  String fiatCurrency = 'NGN';
  final _amountCtrl = TextEditingController();
  final _fiatTotalCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _paymentCtrl = TextEditingController();
  final _termsCtrl = TextEditingController();

  bool _busy = false;
  bool _syncing = false;
  Map<String, dynamic>? _rates;
  late Future<Map<String, dynamic>> _ratesFuture;

  static const _coins = ['BTC', 'ETH', 'USDC', 'USDT'];
  static const _coinNames = {
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
    'USDC': 'USD Coin',
    'USDT': 'Tether',
  };
  static const _fiatOptions = ['NGN', 'USD', 'GHS', 'KES', 'ZAR', 'EUR', 'GBP'];
  static const _fiatSymbols = {
    'NGN': '₦',
    'USD': r'$',
    'GHS': 'GH₵',
    'KES': 'KSh',
    'ZAR': 'R',
    'EUR': '€',
    'GBP': '£',
  };
  static const _paymentPresets = [
    'Bank Transfer',
    'Opay',
    'PalmPay',
    'Moniepoint',
    'Kuda',
    'GTBank',
    'Access Bank',
  ];

  final _wholeFormat = NumberFormat('#,##0');
  final _decimalFormat = NumberFormat('#,##0.########');

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_syncFromAmount);
    _fiatTotalCtrl.addListener(_syncFromFiatTotal);
    _rateCtrl.addListener(_syncFromRate);
    _ratesFuture = _loadRates();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _fiatTotalCtrl.dispose();
    _rateCtrl.dispose();
    _paymentCtrl.dispose();
    _termsCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── rates ────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _loadRates() async {
    final data = await ref.read(offerRepositoryProvider).rates(localCurrency: fiatCurrency);
    _rates = data;
    if (mounted) _applyMarketRate();
    return data;
  }

  void _reloadRates(String currency) {
    setState(() {
      fiatCurrency = currency;
      _rates = null;
      _ratesFuture = _loadRates();
    });
  }

  Map? _marketRow() {
    final rows = (_rates?['coins'] as List? ?? []).cast<Map>();
    try {
      return rows.firstWhere((r) => r['coin'] == coin);
    } catch (_) {
      return null;
    }
  }

  double? _marketFiatRate() {
    final row = _marketRow();
    if (row == null) return null;
    if (fiatCurrency == 'USD') return _parse('${row['usd']}');
    return _parse('${row['local']}');
  }

  void _applyMarketRate() {
    final v = _marketFiatRate();
    if (v == null || v <= 0) return;
    _syncing = true;
    _setText(_rateCtrl, _wholeFormat.format(v.round()));
    _syncing = false;
    _syncFromRate();
  }

  // ── field sync ───────────────────────────────────────────────────────────
  void _syncFromAmount() {
    if (_syncing) return;
    final crypto = _parse(_amountCtrl.text);
    final r = _parse(_rateCtrl.text);
    if (crypto == null || r == null || crypto <= 0 || r <= 0) return;
    _syncing = true;
    _setText(_fiatTotalCtrl, _wholeFormat.format(crypto * r));
    _syncing = false;
    setState(() {});
  }

  void _syncFromFiatTotal() {
    if (_syncing) return;
    final total = _parse(_fiatTotalCtrl.text);
    final r = _parse(_rateCtrl.text);
    if (total == null || r == null || total <= 0 || r <= 0) return;
    _syncing = true;
    _setText(_amountCtrl, _decimalFormat.format(total / r));
    _syncing = false;
    setState(() {});
  }

  void _syncFromRate() {
    if (_syncing) return;
    final crypto = _parse(_amountCtrl.text);
    if (crypto != null && crypto > 0) {
      _syncFromAmount();
      return;
    }
    final total = _parse(_fiatTotalCtrl.text);
    final r = _parse(_rateCtrl.text);
    if (total == null || r == null || total <= 0 || r <= 0) return;
    _syncing = true;
    _setText(_amountCtrl, _decimalFormat.format(total / r));
    _syncing = false;
    setState(() {});
  }

  // ── helpers ──────────────────────────────────────────────────────────────
  double? _parse(String? v) =>
      v == null ? null : double.tryParse(v.replaceAll(',', '').trim());

  void _setText(TextEditingController c, String text) {
    if (c.text == text) return;
    c.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _money(double v) {
    final sym = _fiatSymbols[fiatCurrency] ?? '$fiatCurrency ';
    return '$sym${_wholeFormat.format(v)}';
  }

  double get _totalValue => _parse(_fiatTotalCtrl.text) ?? 0;
  double get _cryptoValue => _parse(_amountCtrl.text) ?? 0;
  double get _rateValue => _parse(_rateCtrl.text) ?? 0;

  // ── premium display ──────────────────────────────────────────────────────
  Widget _premiumBadge() {
    final market = _marketFiatRate();
    if (market == null || market <= 0 || _rateValue <= 0) return const SizedBox.shrink();
    final premium = ((_rateValue - market) / market) * 100;
    final (label, color) = premium.abs() < 0.5
        ? ('At market', AppTheme.success)
        : premium > 0
            ? ('+${premium.toStringAsFixed(1)}% premium', AppTheme.warning)
            : ('${premium.toStringAsFixed(1)}% below', AppTheme.accent);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
    );
  }

  // ── navigation ───────────────────────────────────────────────────────────
  void _next() {
    if (_step == 0) {
      setState(() => _step = 1);
      _pageCtrl.animateToPage(1, duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
    } else if (_step == 1) {
      if (_rateValue <= 0 || _cryptoValue <= 0 || _totalValue <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter rate and amount first')),
        );
        return;
      }
      setState(() => _step = 2);
      _pageCtrl.animateToPage(2, duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step -= 1);
      _pageCtrl.animateToPage(_step, duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
    } else {
      Navigator.pop(context);
    }
  }

  // ── submit ───────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_paymentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select or enter a payment method')),
      );
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(offerRepositoryProvider).create(
        side: side,
        coin: coin,
        fiatCurrency: fiatCurrency,
        cryptoAmount: _cryptoValue,
        rate: _rateValue,
        minFiatAmount: _totalValue * 0.1,
        maxFiatAmount: _totalValue,
        paymentMethod: _paymentCtrl.text.trim(),
        terms: _termsCtrl.text.trim(),
      );
      if (!mounted) return;
      await showApiSuccess(
        context,
        title: 'Offer published',
        message: 'Other traders can now find you in the marketplace.',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.backgroundSoft,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _back,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('New Offer'),
              const SizedBox(height: 6),
              _StepIndicator(current: _step),
            ],
          ),
          toolbarHeight: 80,
        ),
        body: PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStep1(),
            _buildStep2(),
            _buildStep3(),
          ],
        ),
      ),
    );
  }

  // ── STEP 1: Side + Coin ──────────────────────────────────────────────────
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What do you\nwant to do?',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _SideCard(
                label: 'I want to\nBuy',
                icon: Icons.trending_down_rounded,
                color: AppTheme.success,
                selected: side == 'buy',
                onTap: () => setState(() => side = 'buy'),
              ),
              const SizedBox(width: 12),
              _SideCard(
                label: 'I want to\nSell',
                icon: Icons.trending_up_rounded,
                color: AppTheme.warning,
                selected: side == 'sell',
                onTap: () => setState(() => side = 'sell'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'Which coin?',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: _coins.map((c) => _CoinCard(
              coin: c,
              name: _coinNames[c] ?? c,
              selected: coin == c,
              onTap: () {
                setState(() => coin = c);
                _applyMarketRate();
              },
            )).toList(),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _next,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('Set Price'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 2: Currency + Rate + Amount ─────────────────────────────────────
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoinLogo(coin: coin),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    side == 'sell' ? 'Selling $coin' : 'Buying $coin',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                  ),
                  Text(
                    _coinNames[coin] ?? coin,
                    style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Currency chips
          const Text('Currency', style: TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _fiatOptions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final c = _fiatOptions[i];
                final sel = c == fiatCurrency;
                return GestureDetector(
                  onTap: () => _reloadRates(c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppTheme.primary.withValues(alpha: 0.18) : AppTheme.elevated,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: sel ? AppTheme.primary : AppTheme.border,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '${_fiatSymbols[c]} $c',
                      style: TextStyle(
                        color: sel ? AppTheme.primaryBright : AppTheme.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // Market rate banner
          FutureBuilder<Map<String, dynamic>>(
            future: _ratesFuture,
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return _RateBanner(text: 'Loading market rate...', loading: true);
              }
              final market = _marketFiatRate();
              if (market == null) return const SizedBox.shrink();
              return _RateBanner(
                text: 'Market rate: ${_money(market)} per $coin',
                loading: false,
              );
            },
          ),
          const SizedBox(height: 16),

          // Rate field
          _SectionLabel('Your rate per $coin'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsInputFormatter()],
            decoration: InputDecoration(
              hintText: 'e.g. 1,500,000',
              prefixText: '${_fiatSymbols[fiatCurrency]} ',
              suffixIcon: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: _applyMarketRate,
                  tooltip: 'Use market rate',
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_rateValue > 0) ...[
            const SizedBox(height: 8),
            Row(children: [_premiumBadge()]),
          ],
          const SizedBox(height: 16),

          // Amount
          _SectionLabel('Amount of $coin to offer'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsInputFormatter(decimal: true)],
            decoration: InputDecoration(
              hintText: '0.5',
              suffixText: coin,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),

          // Fiat total
          _SectionLabel('Total value (${_fiatSymbols[fiatCurrency]}$fiatCurrency)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _fiatTotalCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandsInputFormatter()],
            decoration: InputDecoration(
              hintText: 'e.g. 500,000',
              prefixText: '${_fiatSymbols[fiatCurrency]} ',
              suffixText: fiatCurrency,
            ),
            onChanged: (_) => setState(() {}),
          ),

          // Auto-limits preview
          if (_totalValue > 0) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: AppTheme.accent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Trade limits: ${_money(_totalValue * 0.1)} – ${_money(_totalValue)}',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Live offer preview
          if (_cryptoValue > 0 && _rateValue > 0) ...[
            const SizedBox(height: 20),
            _OfferPreviewCard(
              side: side,
              coin: coin,
              cryptoValue: _cryptoValue,
              totalValue: _totalValue,
              decimalFormat: _decimalFormat,
              moneyFn: _money,
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _next,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text('Payment Details'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 3: Payment + Terms + Publish ────────────────────────────────────
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'How will payment\nbe made?',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 20),

          // Quick-select chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _paymentPresets.map((p) {
              final sel = _paymentCtrl.text == p;
              return GestureDetector(
                onTap: () => setState(() => _paymentCtrl.text = sel ? '' : p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: sel ? AppTheme.primary.withValues(alpha: 0.18) : AppTheme.elevated,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: sel ? AppTheme.primary : AppTheme.border,
                      width: sel ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    p,
                    style: TextStyle(
                      color: sel ? AppTheme.primaryBright : AppTheme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Custom payment input
          TextFormField(
            controller: _paymentCtrl,
            decoration: const InputDecoration(
              hintText: 'Or type a custom method...',
              prefixIcon: Icon(Icons.payment_rounded),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          // Terms
          _SectionLabel('Trade instructions (optional)'),
          const SizedBox(height: 8),
          TextFormField(
            controller: _termsCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'e.g. Send payment within 15 minutes. Include your name in transfer description.',
            ),
          ),
          const SizedBox(height: 24),

          // Full offer summary
          _FinalSummaryCard(
            side: side,
            coin: coin,
            fiatCurrency: fiatCurrency,
            cryptoValue: _cryptoValue,
            totalValue: _totalValue,
            rateValue: _rateValue,
            paymentMethod: _paymentCtrl.text.trim(),
            fiatSymbol: _fiatSymbols[fiatCurrency] ?? fiatCurrency,
            decimalFormat: _decimalFormat,
            wholeFormat: _wholeFormat,
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Publish Offer'),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final done = i < current;
        final active = i == current;
        return Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: active ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: done || active ? AppTheme.primaryBright : AppTheme.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
        );
      }),
    );
  }
}

class _SideCard extends StatelessWidget {
  const _SideCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 110,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : AppTheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? color : AppTheme.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: selected ? color : AppTheme.muted, size: 26),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: selected ? color : AppTheme.muted,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinCard extends StatelessWidget {
  const _CoinCard({
    required this.coin,
    required this.name,
    required this.selected,
    required this.onTap,
  });
  final String coin;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.14) : AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CoinLogo(coin: coin, size: 34),
                if (selected)
                  const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBright, size: 18),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coin,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: selected ? AppTheme.primaryBright : AppTheme.text,
                  ),
                ),
                Text(
                  name,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RateBanner extends StatelessWidget {
  const _RateBanner({required this.text, required this.loading});
  final String text;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.public_rounded, color: AppTheme.primaryBright, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppTheme.primaryBright, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTheme.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _OfferPreviewCard extends StatelessWidget {
  const _OfferPreviewCard({
    required this.side,
    required this.coin,
    required this.cryptoValue,
    required this.totalValue,
    required this.decimalFormat,
    required this.moneyFn,
  });
  final String side;
  final String coin;
  final double cryptoValue;
  final double totalValue;
  final NumberFormat decimalFormat;
  final String Function(double) moneyFn;

  @override
  Widget build(BuildContext context) {
    final isBuy = side == 'buy';
    final color = isBuy ? AppTheme.success : AppTheme.warning;
    return ExchangeCard(
      padding: const EdgeInsets.all(14),
      borderColor: color.withValues(alpha: 0.3),
      child: Row(
        children: [
          CoinLogo(coin: coin, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${decimalFormat.format(cryptoValue)} $coin ≈ ${moneyFn(totalValue)}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          StatusPill(
            label: isBuy ? 'Buying' : 'Selling',
            color: color,
          ),
        ],
      ),
    );
  }
}

class _FinalSummaryCard extends StatelessWidget {
  const _FinalSummaryCard({
    required this.side,
    required this.coin,
    required this.fiatCurrency,
    required this.cryptoValue,
    required this.totalValue,
    required this.rateValue,
    required this.paymentMethod,
    required this.fiatSymbol,
    required this.decimalFormat,
    required this.wholeFormat,
  });
  final String side, coin, fiatCurrency, paymentMethod, fiatSymbol;
  final double cryptoValue, totalValue, rateValue;
  final NumberFormat decimalFormat, wholeFormat;

  String _money(double v) => '$fiatSymbol${wholeFormat.format(v)}';

  @override
  Widget build(BuildContext context) {
    final isBuy = side == 'buy';
    final color = isBuy ? AppTheme.success : AppTheme.warning;
    return ExchangeCard(
      padding: const EdgeInsets.all(18),
      borderColor: color.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CoinLogo(coin: coin, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isBuy ? 'Buying $coin' : 'Selling $coin',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Text(
                      '${decimalFormat.format(cryptoValue)} $coin',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              StatusPill(label: isBuy ? 'BUY' : 'SELL', color: color),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          _Row('Rate', '${_money(rateValue)} / $coin'),
          const SizedBox(height: 6),
          _Row('Total value', _money(totalValue)),
          const SizedBox(height: 6),
          _Row('Trade limits', '${_money(totalValue * 0.1)} – ${_money(totalValue)}'),
          if (paymentMethod.isNotEmpty) ...[
            const SizedBox(height: 6),
            _Row('Payment', paymentMethod),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label, value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 13))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      ],
    );
  }
}

