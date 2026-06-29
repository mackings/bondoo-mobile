import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/forms/form_validators.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../admin/presentation/admin_dashboard_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../trades/data/trade_repository.dart';
import '../data/profile_repository.dart';




class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final profileFormKey = GlobalKey<FormState>();
  final bankFormKey = GlobalKey<FormState>();
  final walletFormKey = GlobalKey<FormState>();
  late Future<Map<String, dynamic>> future = load();
  final displayName = TextEditingController();
  final username = TextEditingController();
  final bankName = TextEditingController();
  final accountName = TextEditingController();
  final accountNumber = TextEditingController();
  final walletProvider = TextEditingController();
  final walletAddress = TextEditingController();
  final imagePicker = ImagePicker();
  final Set<String> pendingActions = {};
  String? hydratedProfileId;
  String bankCurrency = 'NGN';
  String walletAsset = 'BTC';

  // Trade status
  bool tradeStatusActive = false;
  String tradeStatusType = 'selling';
  String tradeStatusCoin = 'BTC';
  String tradeStatusNetwork = 'BTC';
  String tradeStatusPaymentMethod = 'Bank Transfer';
  final tradeStatusRate = TextEditingController();

  Future<Map<String, dynamic>> load() =>
      ref.read(profileRepositoryProvider).load();

  Future<void> saveProfile() async {
    if (!profileFormKey.currentState!.validate() ||
        pendingActions.contains('profile')) {
      return;
    }
    setState(() => pendingActions.add('profile'));
    try {
      await ref
          .read(profileRepositoryProvider)
          .saveProfile(
            displayName: displayName.text.trim(),
            username: username.text.trim().toLowerCase(),
          );
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Profile updated',
          message: 'Your account details have been saved.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => pendingActions.remove('profile'));
    }
  }


  Future<void> uploadAvatar() async {
    if (pendingActions.contains('avatar')) return;
    try {
      final picked = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 76,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.length > 650000) {
        if (mounted) {
          showApiError(
            context,
            const ApiException('Choose a smaller profile picture.'),
          );
        }
        return;
      }
      final extension = picked.name.split('.').last.toLowerCase();
      final mimeType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
      final imageDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      setState(() => pendingActions.add('avatar'));
      final user = await ref
          .read(profileRepositoryProvider)
          .uploadAvatar(imageDataUrl);
      await ref.read(authControllerProvider.notifier).updateUser(user);
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Photo updated',
          message: 'Your profile picture has been saved.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => pendingActions.remove('avatar'));
    }
  }

  Future<void> saveBankAccount() async {
    if (!bankFormKey.currentState!.validate() ||
        pendingActions.contains('bank')) {
      return;
    }
    setState(() => pendingActions.add('bank'));
    try {
      final user = await ref
          .read(profileRepositoryProvider)
          .saveBankAccount(
            bankName: bankName.text.trim(),
            accountName: accountName.text.trim(),
            accountNumber: accountNumber.text.trim(),
            currency: bankCurrency,
          );
      await ref.read(authControllerProvider.notifier).updateUser(user);
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Bank account saved',
          message: 'Your payout bank account has been updated.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => pendingActions.remove('bank'));
    }
  }

  Future<void> linkWallet() async {
    if (!walletFormKey.currentState!.validate() ||
        pendingActions.contains('wallet')) {
      return;
    }
    setState(() => pendingActions.add('wallet'));
    try {
      final user = await ref
          .read(profileRepositoryProvider)
          .linkWallet(
            walletAsset.toLowerCase(),
            walletProvider.text.trim(),
            walletAddress.text.trim(),
          );
      await ref.read(authControllerProvider.notifier).updateUser(user);
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Wallet saved',
          message: 'Your $walletAsset payout wallet has been saved.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => pendingActions.remove('wallet'));
    }
  }

  Future<void> saveTradeStatus() async {
    if (pendingActions.contains('tradeStatus')) return;
    setState(() => pendingActions.add('tradeStatus'));
    try {
      final rate = double.tryParse(tradeStatusRate.text.trim());
      await ref.read(tradeRepositoryProvider).setTradeStatus(
        type: tradeStatusType,
        coin: tradeStatusCoin,
        network: tradeStatusNetwork,
        paymentMethod: tradeStatusPaymentMethod,
        rate: rate,
        active: true,
      );
      setState(() {
        tradeStatusActive = true;
        future = load();
      });
      if (mounted) {
        await showApiSuccess(context, title: 'Status active', message: 'You are now visible in the Market.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => pendingActions.remove('tradeStatus'));
    }
  }

  Future<void> stopTradeStatus() async {
    if (pendingActions.contains('tradeStatus')) return;
    setState(() => pendingActions.add('tradeStatus'));
    try {
      await ref.read(tradeRepositoryProvider).clearTradeStatus();
      setState(() {
        tradeStatusActive = false;
        future = load();
      });
      if (mounted) {
        await showApiSuccess(context, title: 'Status cleared', message: 'You are no longer visible in the Market.');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => pendingActions.remove('tradeStatus'));
    }
  }

  @override
  void dispose() {
    displayName.dispose();
    username.dispose();
    bankName.dispose();
    accountName.dispose();
    accountNumber.dispose();
    walletProvider.dispose();
    walletAddress.dispose();
    tradeStatusRate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Profile',
      subtitle: 'Account, security, and wallets',
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) => AsyncStateView<Map<String, dynamic>>(
          snapshot: snapshot,
          onRetry: () => setState(() {
            future = load();
          }),
          builder: (data) {
            final profile = data['profile'] as Map<String, dynamic>;
            final email = '${profile['email'] ?? ''}';
            final roles = (data['roles'] as List)
                .map((role) => role['role'])
                .toSet();
            final profileId = '${profile['id'] ?? profile['email'] ?? ''}';
            if (hydratedProfileId != profileId) {
              displayName.text = '${profile['display_name'] ?? ''}';
              username.text = '${profile['username'] ?? ''}';
              final banks = (profile['bank_accounts'] as List? ?? []);
              if (banks.isNotEmpty) {
                final bank = banks.first as Map;
                bankName.text = '${bank['bank_name'] ?? ''}';
                accountName.text = '${bank['account_name'] ?? ''}';
                accountNumber.text = '${bank['account_number'] ?? ''}';
                bankCurrency = '${bank['currency'] ?? 'NGN'}';
              }
              final wallets = (profile['payout_wallets'] as List? ?? []);
              if (wallets.isNotEmpty) {
                final wallet = wallets.first as Map;
                walletAsset = '${wallet['asset'] ?? 'BTC'}';
                walletProvider.text = '${wallet['provider'] ?? ''}';
                walletAddress.text = '${wallet['address'] ?? ''}';
              }
              final ts = profile['trade_status'] as Map?;
              if (ts != null) {
                tradeStatusActive = ts['active'] == true;
                tradeStatusType = '${ts['type'] ?? 'selling'}';
                tradeStatusCoin = '${ts['coin'] ?? 'BTC'}';
                tradeStatusNetwork = '${ts['network'] ?? 'BTC'}';
                tradeStatusPaymentMethod = '${ts['payment_method'] ?? 'Bank Transfer'}';
                tradeStatusRate.text = ts['rate'] != null ? '${ts['rate']}' : '';
              }
              hydratedProfileId = profileId;
            }
            final isVerified = profile['email_verified'] == true;
            final bankAccounts = profile['bank_accounts'] as List? ?? [];
            final payoutWallets = profile['payout_wallets'] as List? ?? [];

            return ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                ExchangeCard(
                  padding: const EdgeInsets.all(22),
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.42),
                      AppTheme.accent.withValues(alpha: 0.20),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderColor: Colors.white12,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AssetAvatar(
                                label: initials('${profile['display_name']}'),
                                imageUrl: '${profile['avatar_url'] ?? ''}',
                                size: 62,
                              ),
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: Material(
                                  color: AppTheme.primary,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: pendingActions.contains('avatar')
                                        ? null
                                        : uploadAvatar,
                                    child: Padding(
                                      padding: const EdgeInsets.all(7),
                                      child: pendingActions.contains('avatar')
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.camera_alt_rounded,
                                              size: 15,
                                              color: Colors.white,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${profile['display_name']}',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '@${profile['username']}',
                                  style: const TextStyle(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(
                            label: isVerified ? 'Verified' : 'Pending',
                            icon: isVerified
                                ? Icons.verified_rounded
                                : Icons.schedule_rounded,
                            color: isVerified
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.mail_outline_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                email,
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                const SectionLabel(
                  'Account details',
                  caption: 'Your public BONDOO identity',
                  icon: Icons.manage_accounts_rounded,
                ),
                ExchangeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Form(
                        key: profileFormKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: displayName,
                              validator: (value) => FormValidators.requiredText(
                                value,
                                label: 'Display name',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Display name',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: username,
                              validator: FormValidators.username,
                              decoration: const InputDecoration(
                                labelText: 'Username',
                                prefixIcon: Icon(Icons.alternate_email),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: pendingActions.contains('profile')
                            ? null
                            : saveProfile,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Save changes'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel(
                  'Bank account',
                  caption: 'Where buyers send fiat payments',
                  icon: Icons.account_balance_rounded,
                ),
                ExchangeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (bankAccounts.isNotEmpty) ...[
                        InfoBanner(
                          icon: Icons.account_balance_rounded,
                          title:
                              '${bankAccounts.first['bank_name'] ?? ''} · ${bankAccounts.first['currency'] ?? ''}',
                          message: [
                            if ((bankAccounts.first['account_name'] ?? '').toString().isNotEmpty)
                              bankAccounts.first['account_name'],
                            if ((bankAccounts.first['account_number'] ?? '').toString().isNotEmpty)
                              bankAccounts.first['account_number']
                            else
                              '⚠ Account number missing — fill in below',
                          ].join(' · '),
                          color: (bankAccounts.first['account_number'] ?? '').toString().isEmpty
                              ? AppTheme.warning
                              : AppTheme.accent,
                        ),
                        const SizedBox(height: 14),
                      ],
                      Form(
                        key: bankFormKey,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: bankCurrency,
                              decoration: const InputDecoration(
                                labelText: 'Currency',
                              ),
                              items: const ['NGN', 'USD', 'GHS', 'KES', 'ZAR']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => bankCurrency = value ?? bankCurrency,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: bankName,
                              validator: (value) => FormValidators.requiredText(
                                value,
                                label: 'Bank name',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Bank name',
                                prefixIcon: Icon(Icons.account_balance_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: accountName,
                              validator: (value) => FormValidators.requiredText(
                                value,
                                label: 'Account name',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Account name',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: accountNumber,
                              keyboardType: TextInputType.number,
                              validator: (value) => FormValidators.requiredText(
                                value,
                                label: 'Account number',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Account number',
                                prefixIcon: Icon(Icons.numbers_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: pendingActions.contains('bank')
                            ? null
                            : saveBankAccount,
                        icon: const Icon(Icons.account_balance_rounded),
                        label: const Text('Save bank account'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel(
                  'Payout wallet',
                  caption: 'Where sellers send crypto after payment proof',
                  icon: Icons.account_balance_wallet_rounded,
                ),
                ExchangeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final wallet in payoutWallets) ...[
                        InfoBanner(
                          icon: Icons.wallet_rounded,
                          title: '${wallet['asset']} · ${wallet['provider']}',
                          message: '${wallet['address']}',
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (payoutWallets.isNotEmpty) const SizedBox(height: 4),
                      Form(
                        key: walletFormKey,
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: walletAsset,
                              decoration: const InputDecoration(
                                labelText: 'Asset',
                              ),
                              items: const ['BTC', 'ETH', 'USDC', 'USDT']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(
                                () => walletAsset = value ?? walletAsset,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: walletProvider,
                              validator: (value) => FormValidators.requiredText(
                                value,
                                label: 'Wallet provider',
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Wallet provider',
                                hintText: 'Binance, Trust Wallet, Coinbase...',
                                prefixIcon: Icon(Icons.account_tree_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: walletAddress,
                              validator: FormValidators.walletAddress,
                              decoration: const InputDecoration(
                                labelText: 'Wallet address',
                                prefixIcon: Icon(Icons.wallet_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: pendingActions.contains('wallet')
                            ? null
                            : linkWallet,
                        icon: const Icon(Icons.wallet_rounded),
                        label: const Text('Save payout wallet'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const SectionLabel(
                  'Trading status',
                  caption: 'Appear in the Market so others can find you',
                  icon: Icons.storefront_rounded,
                ),
                ExchangeCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (tradeStatusActive)
                        InfoBanner(
                          icon: Icons.storefront_rounded,
                          title: 'Active · ${tradeStatusType == 'selling' ? 'Selling' : 'Buying'} $tradeStatusCoin',
                          message: 'You are visible in the Market. Tap "Stop" to hide.',
                          color: AppTheme.success,
                        ),
                      if (tradeStatusActive) const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('ts_type_$tradeStatusType'),
                              initialValue: tradeStatusType,
                              decoration: const InputDecoration(labelText: 'I am'),
                              items: const [
                                DropdownMenuItem(value: 'selling', child: Text('Selling')),
                                DropdownMenuItem(value: 'buying', child: Text('Buying')),
                              ],
                              onChanged: (v) => setState(() => tradeStatusType = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('ts_coin_$tradeStatusCoin'),
                              initialValue: tradeStatusCoin,
                              decoration: const InputDecoration(labelText: 'Coin'),
                              items: ['BTC', 'ETH', 'USDC', 'USDT']
                                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                                  .toList(),
                              onChanged: (v) => setState(() {
                                tradeStatusCoin = v!;
                                tradeStatusNetwork = switch (v) {
                                  'BTC' => 'BTC',
                                  'ETH' => 'ERC20',
                                  _ => 'TRC20',
                                };
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('ts_net_${tradeStatusCoin}_$tradeStatusNetwork'),
                              initialValue: tradeStatusNetwork,
                              decoration: const InputDecoration(labelText: 'Network'),
                              items: switch (tradeStatusCoin) {
                                'BTC' => ['BTC'],
                                'ETH' => ['ERC20'],
                                _ => ['TRC20', 'ERC20', 'BSC'],
                              }
                                  .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                                  .toList(),
                              onChanged: (v) => setState(() => tradeStatusNetwork = v!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('ts_pay_$tradeStatusPaymentMethod'),
                              initialValue: tradeStatusPaymentMethod,
                              decoration: const InputDecoration(labelText: 'Payment'),
                              items: ['Bank Transfer', 'Mobile Money', 'Cash', 'PayPal', 'Other']
                                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                  .toList(),
                              onChanged: (v) => setState(() => tradeStatusPaymentMethod = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: tradeStatusRate,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Your rate (optional)',
                          hintText: 'e.g. 1600000',
                          prefixIcon: const Icon(Icons.price_change_outlined),
                          suffixText: bankCurrency,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: pendingActions.contains('tradeStatus') ? null : saveTradeStatus,
                              icon: const Icon(Icons.storefront_rounded),
                              label: const Text('Go Live'),
                            ),
                          ),
                          if (tradeStatusActive) ...[
                            const SizedBox(width: 10),
                            OutlinedButton(
                              onPressed: pendingActions.contains('tradeStatus') ? null : stopTradeStatus,
                              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
                              child: const Text('Stop'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (roles.contains('admin')) ...[
                  const SizedBox(height: 24),
                  const SectionLabel(
                    'Administration',
                    caption: 'Operations and transaction review',
                    icon: Icons.admin_panel_settings_rounded,
                  ),
                  ExchangeCard(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminDashboardScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.monitor_heart_outlined),
                      label: const Text('Open admin dashboard'),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).signOut(),
                  style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String initials(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed == 'null') return 'B';
  return trimmed.characters.first.toUpperCase();
}

void showError(BuildContext context, Object error) {
  showApiError(context, error);
}
