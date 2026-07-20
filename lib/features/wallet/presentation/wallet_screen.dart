import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../orders/presentation/orders_screen.dart';
import '../data/paystack_repository.dart';

final _nairaFmt = NumberFormat.currency(symbol: '₦', decimalDigits: 2, locale: 'en_NG');

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  Map<String, dynamic>? _walletData;
  Map<String, dynamic>? _virtualAccount;
  bool _loading = true;
  String? _error;
  bool _creatingDva = false;
  bool _balanceVisible = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        ref.read(paystackRepositoryProvider).getWallet(),
        ref.read(paystackRepositoryProvider).getVirtualAccount(),
      ]);
      if (mounted) {
        setState(() {
          _walletData     = results[0] as Map<String, dynamic>;
          _virtualAccount = results[1];
          _loading = false;
        });
        if (_virtualAccount == null) _setupVirtualAccount(showError: false);
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _setupVirtualAccount({bool showError = true}) async {
    if (mounted) setState(() => _creatingDva = true);
    try {
      final dva = await ref.read(paystackRepositoryProvider).createVirtualAccount();
      if (mounted) setState(() => _virtualAccount = dva);
    } catch (e) {
      if (mounted && showError) showApiError(context, e, title: 'Could not create account');
    } finally {
      if (mounted) setState(() => _creatingDva = false);
    }
  }

  double get _balance => (_walletData?['balance'] as num?)?.toDouble() ?? 0;

  List<Map<String, dynamic>> get _transactions {
    final raw = _walletData?['transactions'] as List? ?? [];
    return raw.cast<Map<String, dynamic>>();
  }

  String get _displayName {
    final user = ref.read(authControllerProvider).user;
    return '${user?['display_name'] ?? user?['username'] ?? 'User'}';
  }

  String get _firstName => _displayName.split(' ').first;

  void _copyAccountNumber() {
    final num = _virtualAccount?['account_number'] as String? ?? '';
    if (num.isEmpty) return;
    Clipboard.setData(ClipboardData(text: num));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Account number copied'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _showWithdrawSheet() async {
    final withdrawn = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (_) => _WithdrawSheet(
        balance: _balance,
        paystackRepo: ref.read(paystackRepositoryProvider),
      ),
    );
    if (withdrawn == true && mounted) {
      _load();
      showApiSuccess(context, title: 'Withdrawal initiated', message: 'Your funds are on the way to your bank.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.danger, size: 42),
              const SizedBox(height: 14),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 20),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Greeting ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, MediaQuery.of(context).padding.top + 14, 22, 0),
                child: Text(
                  'Hello, $_firstName',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                ),
              ),
            ),

            // ── Account card (includes balance + withdraw) ────────────────
            SliverToBoxAdapter(child: _buildAccountCard()),

            // ── Orders quick access ───────────────────────────────────────
            SliverToBoxAdapter(child: _buildOrdersSection()),

            // ── Transactions ──────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildTransactionsHeader()),
            if (_transactions.isEmpty)
              const SliverToBoxAdapter(child: _EmptyTransactions())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList.separated(
                  itemCount: _transactions.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, color: AppTheme.border),
                  itemBuilder: (_, i) => _TxTile(tx: _transactions[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountCard() {
    final accountNum = '${_virtualAccount?['accountNumber'] ?? ''}';
    final bankName   = '${_virtualAccount?['bankName'] ?? ''}';
    final acctName   = '${_virtualAccount?['accountName'] ?? _displayName}';
    final displayNum = accountNum.length == 10
        ? '${accountNum.substring(0, 3)} ${accountNum.substring(3, 6)} ${accountNum.substring(6)}'
        : accountNum;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xff1a0533), Color(0xff2d1065), Color(0xff0d3d6b)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: const Color(0xff6C22A6).withValues(alpha: 0.4), blurRadius: 28, offset: const Offset(0, 12)),
        ],
      ),
      child: Stack(
        children: [
          Positioned(top: -30, right: -20,
            child: Container(width: 130, height: 130,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)))),
          Positioned(bottom: -40, left: 60,
            child: Container(width: 160, height: 160,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.04)))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Balance ──────────────────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Available Balance', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        _balanceVisible
                            ? Text(_nairaFmt.format(_balance),
                                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5))
                            : const Text('₦ ••••••',
                                style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 2)),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _balanceVisible = !_balanceVisible),
                      child: Icon(
                        _balanceVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: Colors.white54, size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: Colors.white.withValues(alpha: 0.12)),
                const SizedBox(height: 12),
                // ── Account details ──────────────────────────────────────
                if (_creatingDva) ...[
                  const Row(children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)),
                    SizedBox(width: 8),
                    Text('Setting up your account...', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ]),
                ] else if (_virtualAccount != null) ...[
                  Text(displayNum,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 2, fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(acctName.toUpperCase(),
                              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                            const SizedBox(height: 1),
                            Text(bankName, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _copyAccountNumber,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.copy_rounded, color: Colors.white, size: 11),
                              SizedBox(width: 4),
                              Text('Copy', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // ── Withdraw button ──────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _balance > 0 ? _showWithdrawSheet : null,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 14),
                    label: const Text('Withdraw to Bank'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white30,
                      side: const BorderSide(color: Colors.white30),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      minimumSize: const Size(0, 36),
                      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _OrderShortcut(
              icon: Icons.shopping_bag_outlined,
              label: 'My Purchases',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen(initialTab: 0)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _OrderShortcut(
              icon: Icons.sell_outlined,
              label: 'My Sales',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OrdersScreen(initialTab: 1)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
      child: Row(
        children: [
          const Text('Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.elevated,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_transactions.length}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        children: [
          SizedBox(height: 24),
          Icon(Icons.receipt_long_outlined, color: AppTheme.muted, size: 44),
          SizedBox(height: 14),
          Text('No transactions yet', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          SizedBox(height: 6),
          Text(
            'Sell products to earn Naira.\nYour sales and withdrawals will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.muted, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

// ── Transaction tile ──────────────────────────────────────────────────────────

class _TxTile extends StatelessWidget {
  const _TxTile({required this.tx});
  final Map<String, dynamic> tx;

  @override
  Widget build(BuildContext context) {
    final isCredit = '${tx['type']}' == 'credit';
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
    final description = '${tx['description'] ?? ''}';
    final status = '${tx['status'] ?? 'completed'}';
    final date = _fmtDate(tx['created_at']);
    final isPending = status == 'pending';

    final color = isCredit ? AppTheme.success : AppTheme.danger;
    final bgColor = isCredit
        ? AppTheme.success.withValues(alpha: 0.12)
        : AppTheme.danger.withValues(alpha: 0.10);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(
              isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
              color: color, size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(date, style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
                    if (isPending) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Pending', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : '-'}${_nairaFmt.format(amount)}',
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '';
    try { return DateFormat('MMM d, y').format(DateTime.parse('$raw').toLocal()); } catch (_) { return ''; }
  }
}

// ── Withdraw sheet ────────────────────────────────────────────────────────────

class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({required this.balance, required this.paystackRepo});
  final double balance;
  final PaystackRepository paystackRepo;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();

  List<Map<String, dynamic>> _banks = [];
  Map<String, dynamic>? _selectedBank;
  bool _loadingBanks = true;
  bool _resolving = false;
  bool _submitting = false;

  @override
  void initState() { super.initState(); _loadBanks(); }

  @override
  void dispose() { _amountCtrl.dispose(); _accountCtrl.dispose(); _accountNameCtrl.dispose(); super.dispose(); }

  Future<void> _loadBanks() async {
    try {
      final list = await widget.paystackRepo.getBanks();
      if (mounted) setState(() { _banks = list.cast<Map<String, dynamic>>(); _loadingBanks = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingBanks = false);
    }
  }

  Future<void> _resolveAccount() async {
    final number = _accountCtrl.text.trim();
    if (number.length != 10 || _selectedBank == null) return;
    setState(() { _resolving = true; _accountNameCtrl.clear(); });
    try {
      final result = await widget.paystackRepo.resolveAccount(number, '${_selectedBank!['code']}');
      if (mounted) setState(() => _accountNameCtrl.text = '${result['account_name'] ?? ''}');
    } catch (_) {
      if (mounted) _accountNameCtrl.clear();
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _submitting) return;
    if (_selectedBank == null) { showApiError(context, 'Select a bank.'); return; }
    if (_accountNameCtrl.text.trim().isEmpty) { showApiError(context, 'Verify your account number first.'); return; }
    setState(() => _submitting = true);
    try {
      await widget.paystackRepo.withdraw(
        amount: double.parse(_amountCtrl.text.trim().replaceAll(',', '')),
        accountNumber: _accountCtrl.text.trim(),
        bankCode: '${_selectedBank!['code']}',
        accountName: _accountNameCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Withdraw to Bank', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Available: ${_nairaFmt.format(widget.balance)}', style: const TextStyle(color: AppTheme.muted, fontSize: 13)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [_thousandsFormatter],
                decoration: const InputDecoration(labelText: 'Amount (₦)', prefixText: '₦ '),
                validator: (v) {
                  final d = double.tryParse(v?.trim().replaceAll(',', '') ?? '');
                  if (d == null || d < 100) return 'Minimum ₦100';
                  if (d > widget.balance) return 'Exceeds balance';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _loadingBanks
                  ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
                  : DropdownButtonFormField<Map<String, dynamic>>(
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Bank'),
                      items: _banks.map((b) => DropdownMenuItem(value: b, child: Text('${b['name']}', overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (b) { setState(() { _selectedBank = b; _accountNameCtrl.clear(); }); _resolveAccount(); },
                      validator: (_) => _selectedBank == null ? 'Select a bank' : null,
                    ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountCtrl,
                keyboardType: TextInputType.number,
                maxLength: 10,
                decoration: InputDecoration(
                  labelText: 'Account Number',
                  counterText: '',
                  suffixIcon: _resolving ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null,
                ),
                onChanged: (_) {
                  _accountNameCtrl.clear();
                  if (_accountCtrl.text.trim().length == 10) _resolveAccount();
                },
                validator: (v) => (v?.trim().length ?? 0) != 10 ? 'Enter 10-digit account number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNameCtrl,
                readOnly: true,
                decoration: const InputDecoration(labelText: 'Account Name', helperText: 'Auto-filled on account number entry'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: const Text('Send Withdrawal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Order shortcut button ─────────────────────────────────────────────────────

class _OrderShortcut extends StatelessWidget {
  const _OrderShortcut({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.primaryBright, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

final _thousandsFormatter = TextInputFormatter.withFunction((oldValue, newValue) {
  final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return newValue.copyWith(text: '');
  final buf = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  final formatted = buf.toString();
  return TextEditingValue(
    text: formatted,
    selection: TextSelection.collapsed(offset: formatted.length),
  );
});
