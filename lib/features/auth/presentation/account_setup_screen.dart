import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../features/banks/data/bank_repository.dart';
import '../../../shared/forms/form_validators.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../profile/data/profile_repository.dart';
import '../data/auth_repository.dart';

// ─── Email verification screen ────────────────────────────────────────────────

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  final formKey = GlobalKey<FormState>();
  final code = TextEditingController();
  bool busy = false;
  bool sending = false;

  Future<void> verify() async {
    if (!formKey.currentState!.validate() || busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(authControllerProvider.notifier)
          .verifyEmailOtp(code.text.trim());
    } catch (error) {
      if (mounted) showApiError(context, error, title: 'Invalid code');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resend() async {
    if (sending) return;
    setState(() => sending = true);
    try {
      final result =
          await ref.read(authControllerProvider.notifier).sendEmailOtp();
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Code sent',
          message: _otpSendMessage(result),
        );
      }
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    return ExchangeScaffold(
      title: 'Verify email',
      subtitle: 'Enter the 4 digit code sent to your email',
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            InfoBanner(
              icon: Icons.mark_email_read_rounded,
              title: 'Check ${user?['email'] ?? 'your email'}',
              message:
                  'Copy the 4 digit BONDOO code from your email and paste it below to activate your account.',
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: code,
              maxLength: 4,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              validator: FormValidators.otp,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: 12,
              ),
              decoration: const InputDecoration(
                counterText: '',
                labelText: 'Verification code',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : verify,
              child: Text(busy ? 'Verifying...' : 'Verify account'),
            ),
            TextButton(
              onPressed: sending ? null : resend,
              child: Text(sending ? 'Sending...' : 'Send code again'),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signOut(),
              style: TextButton.styleFrom(foregroundColor: AppTheme.muted),
              child: const Text('Use another account'),
            ),
          ],
        ),
      ),
    );
  }
}

String _otpSendMessage(Map<String, dynamic> result) {
  final email = result['email'];
  final delivery = email is Map ? email['delivery'] : null;
  final status = delivery is Map ? delivery['status'] : null;
  if (status is String && status.isNotEmpty) {
    return 'The email provider reports the code as $status. Check your inbox and spam folder.';
  }
  return 'Code sent. Check your inbox and spam folder.';
}

// ─── Account setup screen ─────────────────────────────────────────────────────

class RequiredAccountSetupScreen extends ConsumerStatefulWidget {
  const RequiredAccountSetupScreen({super.key});

  @override
  ConsumerState<RequiredAccountSetupScreen> createState() =>
      _RequiredAccountSetupScreenState();
}

class _RequiredAccountSetupScreenState
    extends ConsumerState<RequiredAccountSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _accountNumberCtrl = TextEditingController();
  final _walletProviderCtrl = TextEditingController();
  final _walletAddressCtrl = TextEditingController();
  final _bankSearchCtrl = TextEditingController();

  String _currency = 'NGN';
  String _asset = 'BTC';

  // Bank state
  List<BankInfo> _banks = [];
  List<BankInfo> _filteredBanks = [];
  BankInfo? _selectedBank;
  bool _loadingBanks = false;

  // Verification state
  VerifiedAccount? _verified;
  bool _verifying = false;
  String? _verifyError;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadBanks();
    _accountNumberCtrl.addListener(_onAccountNumberChanged);
    _bankSearchCtrl.addListener(_onBankSearch);
  }

  @override
  void dispose() {
    _accountNumberCtrl.dispose();
    _walletProviderCtrl.dispose();
    _walletAddressCtrl.dispose();
    _bankSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBanks() async {
    setState(() => _loadingBanks = true);
    try {
      final banks =
          await ref.read(bankRepositoryProvider).fetchBanks(_currency);
      if (mounted) {
        setState(() {
          _banks = banks;
          _filteredBanks = banks;
          _loadingBanks = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingBanks = false);
    }
  }

  void _onBankSearch() {
    final q = _bankSearchCtrl.text.toLowerCase();
    setState(() {
      _filteredBanks = q.isEmpty
          ? _banks
          : _banks
              .where((b) => b.name.toLowerCase().contains(q))
              .toList();
    });
  }

  void _onAccountNumberChanged() {
    // Clear any previous verification when account number changes
    if (_verified != null || _verifyError != null) {
      setState(() {
        _verified = null;
        _verifyError = null;
      });
    }
    // Auto-trigger verification when 10 digits entered and bank selected
    final number = _accountNumberCtrl.text.trim();
    if (number.length == 10 && _selectedBank != null) {
      _verifyAccount();
    }
  }

  Future<void> _verifyAccount() async {
    final number = _accountNumberCtrl.text.trim();
    if (number.length < 6 || _selectedBank == null) return;
    setState(() {
      _verifying = true;
      _verifyError = null;
      _verified = null;
    });
    try {
      final result = await ref.read(bankRepositoryProvider).verifyAccount(
            accountNumber: number,
            bankCode: _selectedBank!.code,
          );
      if (mounted) {
        setState(() {
          _verified = result;
          _verifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifyError = e.toString().replaceAll('Exception: ', '');
          _verifying = false;
        });
      }
    }
  }

  void _pickBank() async {
    final picked = await showModalBottomSheet<BankInfo>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BankPickerSheet(
        banks: _banks,
        searchCtrl: _bankSearchCtrl,
        filteredBanks: _filteredBanks,
        onFilter: _onBankSearch,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedBank = picked;
        _verified = null;
        _verifyError = null;
        _bankSearchCtrl.clear();
        _filteredBanks = _banks;
      });
      // Auto-verify if account number already entered
      final number = _accountNumberCtrl.text.trim();
      if (number.length >= 10) _verifyAccount();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBank == null) {
      showApiError(context, Exception('Please select a bank'), title: 'Bank required');
      return;
    }
    if (_verified == null) {
      showApiError(context, Exception('Please verify your account number first'), title: 'Verification required');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(profileRepositoryProvider).saveBankAccount(
            bankName: _selectedBank!.name,
            accountName: _verified!.accountName,
            accountNumber: _verified!.accountNumber,
            currency: _currency,
          );
      final user = await ref.read(profileRepositoryProvider).linkWallet(
            _asset.toLowerCase(),
            _walletProviderCtrl.text.trim(),
            _walletAddressCtrl.text.trim(),
          );
      await ref.read(authControllerProvider.notifier).updateUser(user);
    } catch (error) {
      if (mounted) showApiError(context, error, title: 'Setup failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Complete setup',
      subtitle: 'Required before trading',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            const InfoBanner(
              icon: Icons.account_balance_rounded,
              title: 'Add payout details',
              message:
                  'BONDOO needs your bank account so buyers can pay you, and your wallet address to receive crypto.',
            ),
            const SizedBox(height: 20),

            // ── Currency ──────────────────────────────────────────────────
            const _SectionLabel('Bank currency'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.currency_exchange_rounded),
              ),
              items: const ['NGN', 'USD', 'GHS', 'KES', 'ZAR']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _currency = v ?? _currency;
                  _selectedBank = null;
                  _verified = null;
                  _verifyError = null;
                });
                _loadBanks();
              },
            ),
            const SizedBox(height: 16),

            // ── Bank picker ───────────────────────────────────────────────
            const _SectionLabel('Bank name'),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _loadingBanks ? null : _pickBank,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedBank != null
                        ? AppTheme.primary
                        : AppTheme.muted.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_balance_rounded,
                        color: AppTheme.muted, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _loadingBanks
                          ? const Text('Loading banks...',
                              style: TextStyle(color: AppTheme.muted))
                          : Text(
                              _selectedBank?.name ?? 'Select your bank',
                              style: TextStyle(
                                color: _selectedBank != null
                                    ? null
                                    : AppTheme.muted,
                                fontWeight: _selectedBank != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppTheme.muted),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Account number ────────────────────────────────────────────
            const _SectionLabel('Account number'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _accountNumberCtrl,
              keyboardType: TextInputType.number,
              maxLength: 10,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Account number is required';
                if (v.trim().length < 6) return 'Enter a valid account number';
                return null;
              },
              decoration: InputDecoration(
                counterText: '',
                hintText: '10-digit NUBAN',
                prefixIcon: const Icon(Icons.tag_rounded),
                suffixIcon: _verifying
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _verified != null
                        ? const Icon(Icons.check_circle_rounded,
                            color: Colors.green)
                        : null,
              ),
            ),

            // ── Verify button (if not auto-triggered) ─────────────────────
            if (_selectedBank != null &&
                _accountNumberCtrl.text.trim().length >= 6 &&
                _verified == null &&
                !_verifying) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _verifyAccount,
                icon: const Icon(Icons.verified_user_rounded, size: 18),
                label: const Text('Verify account name'),
              ),
            ],

            // ── Verified account card ─────────────────────────────────────
            if (_verified != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            color: Colors.green, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Account verified',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _VerifiedRow(
                        label: 'Account name',
                        value: _verified!.accountName),
                    const SizedBox(height: 4),
                    _VerifiedRow(
                        label: 'Account number',
                        value: _verified!.accountNumber),
                    const SizedBox(height: 4),
                    _VerifiedRow(
                        label: 'Bank',
                        value: _selectedBank?.name ?? ''),
                  ],
                ),
              ),
            ],

            // ── Verification error ────────────────────────────────────────
            if (_verifyError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _verifyError!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Wallet section ────────────────────────────────────────────
            const _SectionLabel('Crypto wallet (for receiving coins)'),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _asset,
              decoration: const InputDecoration(
                labelText: 'Wallet asset',
                prefixIcon: Icon(Icons.generating_tokens_rounded),
              ),
              items: const ['BTC', 'ETH', 'USDC', 'USDT']
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => setState(() => _asset = v ?? _asset),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _walletProviderCtrl,
              validator: (v) =>
                  FormValidators.requiredText(v, label: 'Wallet provider'),
              decoration: const InputDecoration(
                labelText: 'Wallet provider',
                hintText: 'Binance, Trust Wallet, Coinbase…',
                prefixIcon: Icon(Icons.account_balance_wallet_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _walletAddressCtrl,
              validator: FormValidators.walletAddress,
              decoration: const InputDecoration(
                labelText: 'Wallet address',
                prefixIcon: Icon(Icons.qr_code_rounded),
              ),
            ),
            const SizedBox(height: 28),

            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save and continue'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bank picker bottom sheet ─────────────────────────────────────────────────

class _BankPickerSheet extends StatefulWidget {
  const _BankPickerSheet({
    required this.banks,
    required this.searchCtrl,
    required this.filteredBanks,
    required this.onFilter,
  });

  final List<BankInfo> banks;
  final TextEditingController searchCtrl;
  final List<BankInfo> filteredBanks;
  final VoidCallback onFilter;

  @override
  State<_BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<_BankPickerSheet> {
  late List<BankInfo> _filtered;
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _filtered = widget.banks;
    _ctrl = TextEditingController();
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase();
      setState(() {
        _filtered = q.isEmpty
            ? widget.banks
            : widget.banks
                .where((b) => b.name.toLowerCase().contains(q))
                .toList();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select bank',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search banks…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppTheme.backgroundSoft,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No banks found',
                        style: TextStyle(color: AppTheme.muted)))
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final bank = _filtered[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.12),
                          radius: 18,
                          child: Text(
                            bank.name[0],
                            style: const TextStyle(
                              color: AppTheme.primaryBright,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        title: Text(bank.name,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(bank.code,
                            style: const TextStyle(
                                color: AppTheme.muted, fontSize: 12)),
                        onTap: () => Navigator.pop(context, bank),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Small helpers ────────────────────────────────────────────────────────────

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
        letterSpacing: 0.4,
      ),
    );
  }
}

class _VerifiedRow extends StatelessWidget {
  const _VerifiedRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
