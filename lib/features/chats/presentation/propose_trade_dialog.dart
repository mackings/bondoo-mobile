import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/forms/thousands_input_formatter.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../offers/data/offer_repository.dart';
import '../data/chat_repository.dart';

Future<void> showProposeTradeDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String conversationId,
  required String sellerUserId,
  required String sellerName,
  required VoidCallback onProposed,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppTheme.surface,
    builder: (ctx) => _ProposeTradeSheet(
      ref: ref,
      conversationId: conversationId,
      sellerUserId: sellerUserId,
      sellerName: sellerName,
      onProposed: onProposed,
    ),
  );
}

class _ProposeTradeSheet extends StatefulWidget {
  const _ProposeTradeSheet({
    required this.ref,
    required this.conversationId,
    required this.sellerUserId,
    required this.sellerName,
    required this.onProposed,
  });

  final WidgetRef ref;
  final String conversationId;
  final String sellerUserId;
  final String sellerName;
  final VoidCallback onProposed;

  @override
  State<_ProposeTradeSheet> createState() => _ProposeTradeSheetState();
}

class _ProposeTradeSheetState extends State<_ProposeTradeSheet> {
  final formKey = GlobalKey<FormState>();
  String coin = 'BTC';
  String network = 'BTC';
  String fiatCurrency = 'NGN';
  String paymentMethod = 'Bank Transfer';
  final fiatAmountCtrl = TextEditingController();
  final rateCtrl = TextEditingController();
  final walletAddressCtrl = TextEditingController();
  String buyerWalletNetwork = 'BTC';
  bool submitting = false;
  double? _marketRate;
  bool _ratesLoading = false;

  static const _networks = {
    'BTC': ['BTC'],
    'ETH': ['ERC20'],
    'USDC': ['ERC20', 'TRC20', 'BSC'],
    'USDT': ['TRC20', 'ERC20', 'BSC'],
  };

  @override
  void initState() {
    super.initState();
    _loadMarketRate();
    _prefillWalletAddress();
  }

  void _prefillWalletAddress() {
    final user = widget.ref.read(authControllerProvider).user;
    final wallets = (user?['payout_wallets'] as List? ?? []).cast<Map>();
    // Prefer exact asset+network match, then fall back to asset-only match
    final match = wallets.cast<Map?>().firstWhere(
          (w) => w?['asset'] == coin && w?['network'] == network,
          orElse: () => wallets.cast<Map?>().firstWhere(
            (w) => w?['asset'] == coin,
            orElse: () => null,
          ),
        );
    if (match != null) {
      walletAddressCtrl.text = '${match['address'] ?? ''}';
    }
  }

  Future<void> _loadMarketRate() async {
    if (!mounted) return;
    setState(() => _ratesLoading = true);
    try {
      final data = await widget.ref
          .read(offerRepositoryProvider)
          .rates(localCurrency: fiatCurrency);
      if (!mounted) return;
      final rows = (data['coins'] as List? ?? []).cast<Map>();
      final row = rows.cast<Map?>().firstWhere(
        (r) => r?['coin'] == coin,
        orElse: () => null,
      );
      final rate = fiatCurrency == 'USD'
          ? (row?['usd'] as num?)?.toDouble()
          : (row?['local'] as num?)?.toDouble();
      if (rate != null && rate > 0) {
        setState(() => _marketRate = rate);
        rateCtrl.text = NumberFormat('#,##0').format(rate.round());
      }
    } catch (_) {
      // silently skip — user can enter manually
    } finally {
      if (mounted) setState(() => _ratesLoading = false);
    }
  }

  @override
  void dispose() {
    fiatAmountCtrl.dispose();
    rateCtrl.dispose();
    walletAddressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate() || submitting) return;
    setState(() => submitting = true);
    try {
      await widget.ref.read(chatRepositoryProvider).proposeTrade(
        conversationId: widget.conversationId,
        sellerUserId: widget.sellerUserId,
        coin: coin,
        network: network,
        fiatAmount: double.parse(fiatAmountCtrl.text.replaceAll(',', '').trim()),
        fiatCurrency: fiatCurrency,
        rate: double.parse(rateCtrl.text.replaceAll(',', '').trim()),
        paymentMethod: paymentMethod,
        buyerWalletAddress: walletAddressCtrl.text.trim(),
        buyerWalletNetwork: buyerWalletNetwork,
      );
      widget.onProposed();
      if (!mounted) return;
      Navigator.pop(context);
      // Chat refreshes via onProposed — user taps "View Trade" on the proposal card
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nets = _networks[coin] ?? ['BTC'];

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Propose a trade',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'You are the buyer · ${widget.sellerName} will send crypto to escrow',
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('coin_$coin'),
                      initialValue: coin,
                      decoration: const InputDecoration(labelText: 'Coin'),
                      items: ['BTC', 'ETH', 'USDC', 'USDT']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          coin = v!;
                          network = _networks[coin]!.first;
                          buyerWalletNetwork = network;
                          _marketRate = null;
                          rateCtrl.clear();
                          walletAddressCtrl.clear();
                        });
                        _loadMarketRate();
                        _prefillWalletAddress();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('net_${coin}_$network'),
                      initialValue: nets.contains(network) ? network : nets.first,
                      decoration: const InputDecoration(labelText: 'Network'),
                      items: nets
                          .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          network = v!;
                          buyerWalletNetwork = v;
                          walletAddressCtrl.clear();
                        });
                        _prefillWalletAddress();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: fiatAmountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsInputFormatter()],
                      decoration: const InputDecoration(labelText: 'Fiat amount'),
                      validator: (v) {
                        final n = double.tryParse(v?.replaceAll(',', '').trim() ?? '');
                        return (n == null || n <= 0) ? 'Enter a valid amount' : null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('fiat_$fiatCurrency'),
                      initialValue: fiatCurrency,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      items: ['NGN', 'USD', 'GHS', 'KES', 'ZAR']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          fiatCurrency = v!;
                          _marketRate = null;
                          rateCtrl.clear();
                        });
                        _loadMarketRate();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_ratesLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Loading market rate...',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ]),
                )
              else if (_marketRate != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Market rate: ${NumberFormat('#,##0').format(_marketRate!.round())} $fiatCurrency per $coin',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
                ),
              TextFormField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandsInputFormatter()],
                decoration: InputDecoration(
                  labelText: 'Rate ($fiatCurrency per $coin)',
                  hintText: 'e.g. 1,600,000',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: 'Use market rate',
                    onPressed: _ratesLoading ? null : _loadMarketRate,
                  ),
                ),
                validator: (v) {
                  final n = double.tryParse(v?.replaceAll(',', '').trim() ?? '');
                  return (n == null || n <= 0) ? 'Enter a valid rate' : null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('pay_$paymentMethod'),
                initialValue: paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: ['Bank Transfer', 'Mobile Money', 'Cash', 'PayPal', 'Other']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => paymentMethod = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: walletAddressCtrl,
                decoration: InputDecoration(
                  labelText: 'Your $coin wallet address',
                  hintText: 'Where you receive crypto after payment',
                ),
                validator: (v) =>
                    (v == null || v.trim().length < 10) ? 'Enter a valid wallet address' : null,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: submitting ? null : _submit,
                icon: submitting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.handshake_rounded),
                label: const Text('Send Proposal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
