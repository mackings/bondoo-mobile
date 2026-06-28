import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/coin_logo.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/trade_events.dart';
import '../data/trade_repository.dart';

class TradeDetailScreen extends ConsumerStatefulWidget {
  const TradeDetailScreen({super.key, required this.trade});
  final Map<String, dynamic> trade;

  @override
  ConsumerState<TradeDetailScreen> createState() => _TradeDetailScreenState();
}

// States that still need to change — keep polling until one of the
// terminal states is reached.
const _intermediateStatuses = {
  'awaiting_escrow',
  'escrowed',
  'payment_sent',
  'releasing',
};

class _TradeDetailScreenState extends ConsumerState<TradeDetailScreen> {
  late Map<String, dynamic> trade;
  bool _loading = false;
  bool _depositChecking = false;
  Timer? _pollingTimer;
  StreamSubscription<String>? _eventSub;

  @override
  void initState() {
    super.initState();
    trade = widget.trade;
    _startPollingIfNeeded();
    // Immediately refresh when a push notification arrives for this trade
    _eventSub = TradeEvents.instance.onTradeUpdated.listen((id) {
      if (id == '${trade['id']}') _refresh();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  void _startPollingIfNeeded() {
    _pollingTimer?.cancel();
    if (_intermediateStatuses.contains('${trade['status']}')) {
      _pollingTimer = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
    }
  }

  String get _myId => ref.read(authControllerProvider).user?['id'] ?? '';
  bool get _isSeller => trade['seller_user_id'] == _myId;
  bool get _isBuyer => trade['buyer_user_id'] == _myId;

  String get _status => '${trade['status']}';
  String get _coin => '${trade['coin']}';
  String get _network => '${trade['network']}';
  double get _cryptoAmount => double.tryParse('${trade['crypto_amount']}') ?? 0;
  // escrow_amount = cryptoAmount + gas buffer (for native coins like ETH/BNB/BTC)
  // equals cryptoAmount for tokens (USDT etc. — gas comes from platform wallet)
  double get _escrowAmount => double.tryParse('${trade['escrow_amount']}') ?? _cryptoAmount;
  double get _networkFee   => double.tryParse('${trade['network_fee']}')   ?? 0;
  double get _platformFee  => double.tryParse('${trade['platform_fee']}')  ?? 0;
  double get _payoutAmount => double.tryParse('${trade['payout_amount']}') ?? 0;
  double get _fiatAmount   => double.tryParse('${trade['fiat_amount']}')   ?? 0;
  String get _currency => '${trade['fiat_currency']}';
  String get _depositAddress => '${trade['deposit_address']}';
  Map? get _seller => trade['seller'] as Map?;
  List get _sellerBankAccounts => (_seller?['bank_accounts'] as List?) ?? [];
  String? get _receiptUrl => trade['payment_receipt_url'] as String?;

  Future<void> _refresh() async {
    try {
      final updated = await ref.read(tradeRepositoryProvider).get('${trade['id']}');
      if (mounted) {
        setState(() => trade = updated);
        _startPollingIfNeeded(); // restarts or cancels timer based on new status
      }
    } catch (_) {}
  }

  Future<void> _checkDeposit() async {
    setState(() => _depositChecking = true);
    try {
      final result = await ref.read(tradeRepositoryProvider).checkDeposit('${trade['id']}');
      if (!mounted) return;
      if (result['found'] == true) {
        setState(() => trade = result['trade'] as Map<String, dynamic>);
        _showSnack('Deposit confirmed! Notifying buyer.', success: true);
      } else {
        _showSnack('Deposit not found yet. Wait for blockchain confirmation and try again.');
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _depositChecking = false);
    }
  }

  Future<void> _uploadReceipt() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (image == null || !mounted) return;

    final noteCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 12,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Add a note (optional)',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'e.g. Transfer reference or bank name',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Submit Receipt'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final updated = await ref.read(tradeRepositoryProvider).paymentSent(
        '${trade['id']}',
        imagePath: image.path,
        note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      );
      if (mounted) {
        setState(() => trade = updated);
        _showSnack('Receipt submitted! Waiting for seller to confirm.', success: true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _release() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Coins'),
        content: Text(
          'Have you received ${_fiatAmount.toStringAsFixed(2)} $_currency in your bank account?\n\nThis will release ${_payoutAmount.toStringAsFixed(8)} $_coin to the buyer. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Release'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final updated = await ref.read(tradeRepositoryProvider).release('${trade['id']}');
      if (mounted) {
        setState(() => trade = updated);
        _showSnack('Coins released successfully!', success: true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final isEscrowed = _status == 'escrowed';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Trade'),
        content: Text(
          isEscrowed
              ? 'The crypto is already in escrow. Cancelling will mark this trade as cancelled — the seller must reclaim the deposited crypto manually. Are you sure?'
              : 'Are you sure you want to cancel this trade?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Trade'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    try {
      final updated = await ref.read(tradeRepositoryProvider).cancel('${trade['id']}');
      if (mounted) setState(() => trade = updated);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _dispute() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Raise Dispute'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Describe the issue. Our team will review within 2 hours.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'Describe the problem...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.warning),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit Dispute'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (reasonCtrl.text.trim().length < 10) {
      _showSnack('Please describe the issue in at least 10 characters.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await ref.read(tradeRepositoryProvider).dispute('${trade['id']}', reasonCtrl.text.trim());
      if (mounted) {
        setState(() => trade = result['trade'] as Map<String, dynamic>);
        _showSnack('Dispute submitted. Our team will contact you.', success: true);
      }
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _showSnack('$label copied');
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundSoft,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Trade'),
            Text(
              '#${('${trade['id']}').substring(0, 8).toUpperCase()}',
              style: const TextStyle(fontSize: 12, color: AppTheme.muted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refresh,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBanner(status: _status),
              const SizedBox(height: 16),
              _TradeSummaryCard(trade: trade),
              const SizedBox(height: 16),
              _buildStepContent(),
              const SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_status) {
      case 'awaiting_escrow':
        return _buildAwaitingEscrow();
      case 'escrowed':
        return _buildEscrowed();
      case 'payment_sent':
        return _buildPaymentSent();
      case 'releasing':
        return _buildReleasing();
      case 'completed':
        return _buildCompleted();
      case 'cancelled':
        return _buildTerminal(
          icon: Icons.cancel_rounded,
          color: AppTheme.danger,
          title: 'Trade Cancelled',
          message: 'This trade has been cancelled.',
        );
      case 'disputed':
        return _buildTerminal(
          icon: Icons.gavel_rounded,
          color: AppTheme.warning,
          title: 'Dispute In Progress',
          message: 'Our team is reviewing this dispute and will contact both parties within 2 hours.',
        );
      case 'refunded':
        return _buildTerminal(
          icon: Icons.undo_rounded,
          color: AppTheme.accent,
          title: 'Trade Refunded',
          message: 'The crypto has been returned to the seller.',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  // ── STEP 1: Seller deposits crypto ────────────────────────────────────────
  Widget _buildAwaitingEscrow() {
    if (_isSeller) {
      return Column(
        children: [
          _StepCard(
            step: 1,
            title: 'Send crypto to escrow',
            child: Column(
              children: [
                const Text(
                  'Send the exact amount below to the escrow address. The buyer is waiting.',
                  style: TextStyle(color: AppTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(data: _depositAddress, size: 180),
                  ),
                ),
                const SizedBox(height: 16),
                _CopyRow(
                  label: 'Deposit Address',
                  value: _depositAddress,
                  onCopy: () => _copy(_depositAddress, 'Address'),
                ),
                const SizedBox(height: 8),
                _CopyRow(
                  label: 'Send Exactly (tap to copy)',
                  value: '${_escrowAmount.toStringAsFixed(8)} $_coin',
                  onCopy: () => _copy(_escrowAmount.toStringAsFixed(8), 'Amount'),
                  highlight: true,
                ),
                const SizedBox(height: 8),
                _EscrowFeeBreakdown(
                  coin: _coin,
                  cryptoAmount: _cryptoAmount,
                  networkFee: _networkFee,
                  escrowAmount: _escrowAmount,
                  network: _network,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _depositChecking ? null : _checkDeposit,
                  icon: _depositChecking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.search_rounded),
                  label: Text(_depositChecking ? 'Checking...' : "I've sent the crypto"),
                ),
              ],
            ),
          ),
          _CancelButton(onCancel: _cancel, loading: _loading),
        ],
      );
    }

    // Buyer waiting
    return Column(
      children: [
        _StepCard(
          step: 1,
          title: 'Waiting for seller to deposit',
          child: Column(
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              ),
              const Text(
                'The seller is depositing the crypto into escrow. You will be notified once confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              _CopyRow(
                label: 'Trade amount',
                value: '${_cryptoAmount.toStringAsFixed(8)} $_coin',
              ),
            ],
          ),
        ),
        _CancelButton(onCancel: _cancel, loading: _loading),
      ],
    );
  }

  // ── STEP 2: Buyer pays fiat ───────────────────────────────────────────────
  Widget _buildEscrowed() {
    if (_isBuyer) {
      return Column(
        children: [
          _StepCard(
            step: 2,
            title: 'Pay the seller',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: AppTheme.success, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${_cryptoAmount.toStringAsFixed(8)} $_coin is locked in escrow',
                          style: const TextStyle(
                            color: AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Send this exact amount to the seller\'s account:',
                  style: TextStyle(color: AppTheme.muted),
                ),
                const SizedBox(height: 10),
                _CopyRow(
                  label: 'Amount to Pay',
                  value: '${_fiatAmount.toStringAsFixed(2)} $_currency',
                  highlight: true,
                  onCopy: () => _copy(_fiatAmount.toStringAsFixed(2), 'Amount'),
                ),
                const SizedBox(height: 14),
                if (_sellerBankAccounts.isEmpty)
                  const Text(
                    'Seller has not added bank accounts yet. Contact via chat.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13),
                  )
                else ...[
                  const Text(
                    'Seller\'s Bank Details',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  ..._sellerBankAccounts.map((acc) => _BankCard(account: acc as Map)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _uploadReceipt,
                  icon: _loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.upload_rounded),
                  label: const Text("I've Paid — Upload Receipt"),
                ),
              ],
            ),
          ),
          _DisputeButton(onDispute: _dispute, loading: _loading),
          _CancelButton(onCancel: _cancel, loading: _loading),
        ],
      );
    }

    // Seller waiting for payment
    return Column(
      children: [
        _StepCard(
          step: 2,
          title: 'Waiting for buyer\'s payment',
          child: Column(
            children: [
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              ),
              Text(
                'The buyer needs to send ${_fiatAmount.toStringAsFixed(2)} $_currency to your bank account via ${trade['payment_method']}.\n\nYou will be notified when they upload their receipt.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, height: 1.4),
              ),
            ],
          ),
        ),
        _CancelButton(onCancel: _cancel, loading: _loading),
      ],
    );
  }

  // ── STEP 3: Seller confirms & releases ────────────────────────────────────
  Widget _buildPaymentSent() {
    final receiptFullUrl = _receiptUrl != null
        ? '${AppConfig.apiBaseUrl}$_receiptUrl'
        : null;

    if (_isSeller) {
      return Column(
        children: [
          _StepCard(
            step: 3,
            title: 'Buyer has paid — release coins',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_rounded, color: AppTheme.warning, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Buyer claims to have sent ${_fiatAmount.toStringAsFixed(2)} $_currency',
                          style: const TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (receiptFullUrl != null) ...[
                  const Text('Payment Receipt:', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _showReceiptDialog(receiptFullUrl),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        receiptFullUrl,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, e) => Container(
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.elevated,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(child: Text('Tap to view receipt')),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if ('${trade['payment_note'] ?? ''}'.trim().isNotEmpty) ...[
                  const Text('Buyer note:', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('${trade['payment_note']}', style: const TextStyle(height: 1.4)),
                  const SizedBox(height: 12),
                ],
                const Text(
                  'Check your bank account, then release coins to the buyer.',
                  style: TextStyle(color: AppTheme.muted, height: 1.4),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _release,
                  style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                  icon: _loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                  label: Text('Release ${_payoutAmount.toStringAsFixed(8)} $_coin'),
                ),
              ],
            ),
          ),
          _DisputeButton(onDispute: _dispute, loading: _loading),
        ],
      );
    }

    // Buyer waiting for release
    return _StepCard(
      step: 3,
      title: 'Waiting for seller to release',
      child: Column(
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          ),
          const Text(
            'The seller is confirming your payment. Once verified, your crypto will be released to your wallet.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          _DisputeButton(onDispute: _dispute, loading: _loading),
        ],
      ),
    );
  }

  Widget _buildReleasing() {
    return _StepCard(
      step: 4,
      title: 'Processing withdrawal',
      child: Column(
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          ),
          Text(
            'Sending ${_payoutAmount.toStringAsFixed(8)} $_coin to ${_isBuyer ? 'your' : "the buyer's"} wallet...',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleted() {
    return _StepCard(
      step: 4,
      title: 'Trade Completed!',
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppTheme.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 16),
          Text(
            _isBuyer
                ? '${_payoutAmount.toStringAsFixed(8)} $_coin has been sent to your wallet!'
                : 'You released ${_payoutAmount.toStringAsFixed(8)} $_coin to the buyer.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4),
          ),
          const SizedBox(height: 12),
          // Fee summary
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.elevated.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                _SummaryRow('Trade amount', '${_cryptoAmount.toStringAsFixed(8)} $_coin'),
                if (_platformFee > 0)
                  _SummaryRow('Platform fee', '- ${_platformFee.toStringAsFixed(8)} $_coin',
                      color: Colors.orange),
                if (_networkFee > 0)
                  _SummaryRow('Network fee', '- ${_networkFee.toStringAsFixed(8)} $_coin',
                      color: AppTheme.muted),
                const Divider(height: 12),
                _SummaryRow('Received', '${_payoutAmount.toStringAsFixed(8)} $_coin',
                    bold: true, color: AppTheme.primaryBright),
              ],
            ),
          ),
          if ('${trade['withdrawal_id'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CopyRow(
              label: 'Transaction ID',
              value: '${trade['withdrawal_id']}',
              onCopy: () => _copy('${trade['withdrawal_id']}', 'Transaction ID'),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  Widget _buildTerminal({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return _StepCard(
      step: 0,
      title: title,
      child: Column(
        children: [
          Icon(icon, color: color, size: 52),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            child: const Text('Back to Home'),
          ),
        ],
      ),
    );
  }

  void _showReceiptDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppTheme.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Payment Receipt',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.65,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      'awaiting_escrow' => ('Awaiting Escrow', AppTheme.warning, Icons.hourglass_top_rounded),
      'escrowed' => ('Crypto in Escrow', AppTheme.accent, Icons.lock_rounded),
      'payment_sent' => ('Payment Sent', AppTheme.primary, Icons.receipt_long_rounded),
      'releasing' => ('Releasing...', AppTheme.primary, Icons.send_rounded),
      'completed' => ('Completed', AppTheme.success, Icons.check_circle_rounded),
      'cancelled' => ('Cancelled', AppTheme.danger, Icons.cancel_rounded),
      'disputed' => ('Disputed', AppTheme.warning, Icons.gavel_rounded),
      'refunded' => ('Refunded', AppTheme.accent, Icons.undo_rounded),
      _ => ('Unknown', AppTheme.muted, Icons.help_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _TradeSummaryCard extends StatelessWidget {
  const _TradeSummaryCard({required this.trade});
  final Map trade;

  @override
  Widget build(BuildContext context) {
    final coin = '${trade['coin']}';
    final crypto = double.tryParse('${trade['crypto_amount']}') ?? 0;
    final fiat = double.tryParse('${trade['fiat_amount']}') ?? 0;
    final currency = '${trade['fiat_currency']}';
    final rate = double.tryParse('${trade['rate']}') ?? 0;

    return ExchangeCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              CoinLogo(coin: coin),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${crypto.toStringAsFixed(8)} $coin',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    Text(
                      '${fiat.toStringAsFixed(2)} $currency · ${rate.toStringAsFixed(2)} $currency/$coin',
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniInfo(label: 'Payment', value: '${trade['payment_method']}'),
              const SizedBox(width: 12),
              _MiniInfo(label: 'Network', value: '${trade['network']}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  const _MiniInfo({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.title, required this.child});
  final int step;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExchangeCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (step > 0) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    gradient: AppTheme.brandGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '$step',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value, this.onCopy, this.highlight = false});
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.elevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: highlight ? AppTheme.primaryBright : AppTheme.text,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: onCopy,
              color: AppTheme.muted,
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
        ],
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  const _BankCard({required this.account});
  final Map account;

  String _val(dynamic v) {
    final s = '$v';
    return (s == 'null' || s.trim().isEmpty) ? '' : s.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.elevated.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_val(account['bank_name']).isNotEmpty)
            _BankRow('Bank', _val(account['bank_name'])),
          if (_val(account['account_name']).isNotEmpty)
            _BankRow('Account Name', _val(account['account_name'])),
          if (_val(account['account_number']).isNotEmpty)
            _BankRow('Account Number', _val(account['account_number']), copyable: true)
          else
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Account number not set — seller must update their profile.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          if (_val(account['currency']).isNotEmpty)
            _BankRow('Currency', _val(account['currency'])),
        ],
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow(this.label, this.value, {this.copyable = false});
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (copyable)
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$label copied')),
                );
              },
              child: const Icon(Icons.copy_rounded, size: 15, color: AppTheme.muted),
            ),
        ],
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onCancel, required this.loading});
  final VoidCallback onCancel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        onPressed: loading ? null : onCancel,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.danger,
          side: const BorderSide(color: AppTheme.danger),
        ),
        icon: const Icon(Icons.cancel_outlined, size: 18),
        label: const Text('Cancel Trade'),
      ),
    );
  }
}

class _DisputeButton extends StatelessWidget {
  const _DisputeButton({required this.onDispute, required this.loading});
  final VoidCallback onDispute;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: OutlinedButton.icon(
        onPressed: loading ? null : onDispute,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.warning,
          side: const BorderSide(color: AppTheme.warning),
        ),
        icon: const Icon(Icons.gavel_rounded, size: 18),
        label: const Text('Raise Dispute'),
      ),
    );
  }
}

// Shows the gas fee breakdown for the seller in the awaiting_escrow step.
class _EscrowFeeBreakdown extends StatelessWidget {
  const _EscrowFeeBreakdown({
    required this.coin,
    required this.cryptoAmount,
    required this.networkFee,
    required this.escrowAmount,
    required this.network,
  });

  final String coin;
  final double cryptoAmount;
  final double networkFee;
  final double escrowAmount;
  final String network;

  String _fmt(double v) =>
      v.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

  @override
  Widget build(BuildContext context) {
    final hasGas = networkFee > 0 && escrowAmount > cryptoAmount;
    return Column(
      children: [
        if (hasGas) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Trade amount',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                    Text('${_fmt(cryptoAmount)} $coin',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Gas buffer (+20%)',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                    Text('+ ${_fmt(networkFee)} $coin',
                        style:
                            const TextStyle(color: Colors.blue, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          'Network: $network',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12),
        ),
      ],
    );
  }
}

// Simple label-value row used in fee summaries.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.value, {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
