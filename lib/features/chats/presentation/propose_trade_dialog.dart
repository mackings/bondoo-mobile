import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
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

  static const _networks = {
    'BTC': ['BTC'],
    'ETH': ['ERC20'],
    'USDC': ['ERC20', 'TRC20', 'BSC'],
    'USDT': ['TRC20', 'ERC20', 'BSC'],
  };

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
        fiatAmount: double.parse(fiatAmountCtrl.text.trim()),
        fiatCurrency: fiatCurrency,
        rate: double.parse(rateCtrl.text.trim()),
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
                      onChanged: (v) => setState(() {
                        coin = v!;
                        network = _networks[coin]!.first;
                        buyerWalletNetwork = network;
                      }),
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
                      onChanged: (v) => setState(() {
                        network = v!;
                        buyerWalletNetwork = v;
                      }),
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
                      decoration: const InputDecoration(labelText: 'Fiat amount'),
                      validator: (v) =>
                          (v == null || double.tryParse(v.trim()) == null || double.parse(v.trim()) <= 0)
                              ? 'Enter a valid amount'
                              : null,
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
                      onChanged: (v) => setState(() => fiatCurrency = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: rateCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Rate ($fiatCurrency per $coin)',
                  hintText: 'e.g. 1600000',
                ),
                validator: (v) =>
                    (v == null || double.tryParse(v.trim()) == null || double.parse(v.trim()) <= 0)
                        ? 'Enter a valid rate'
                        : null,
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
