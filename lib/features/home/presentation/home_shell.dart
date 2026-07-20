import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/presentation/chats_screen.dart';
import '../../market/presentation/market_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../wallet/data/paystack_repository.dart';
import '../../wallet/presentation/wallet_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int index = 0;
  bool _verificationPromptShown = false;

  bool _needsVerification(Map<String, dynamic>? user) {
    if (user == null || user['email_verified'] != true) return false;
    final va = user['virtual_account'] as Map?;
    return va == null || (va['account_number'] as String?)?.isNotEmpty != true;
  }

  void _maybeShowVerificationPrompt(Map<String, dynamic>? user) {
    if (_verificationPromptShown || !_needsVerification(user)) return;
    _verificationPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final verified = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        showDragHandle: false,
        backgroundColor: AppTheme.surface,
        builder: (_) => const _IdentityVerificationSheet(),
      );
      if (verified == true && mounted) {
        await ref.read(authControllerProvider.notifier).refreshMe();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    _maybeShowVerificationPrompt(user);

    // Tab order: Wallet → Chats → Market → Profile
    final pages = [
      const WalletScreen(),
      const ChatsScreen(),
      const MarketScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: _BottomNav(
        currentIndex: index,
        onTap: (i) => setState(() => index = i),
      ),
    );
  }
}

// ── BVN / NIN identity verification sheet ─────────────────────────────────────

class _IdentityVerificationSheet extends ConsumerStatefulWidget {
  const _IdentityVerificationSheet();

  @override
  ConsumerState<_IdentityVerificationSheet> createState() =>
      _IdentityVerificationSheetState();
}

class _IdentityVerificationSheetState
    extends ConsumerState<_IdentityVerificationSheet> {
  String _type = 'bvn';
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _ctrl.text.trim();
    if (value.length != 11 || !RegExp(r'^\d+$').hasMatch(value)) {
      setState(() => _error = 'Must be exactly 11 digits');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(paystackRepositoryProvider).identifyCustomer(
        type: _type,
        value: value,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24, 32, 24, MediaQuery.of(context).viewInsets.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 64,
              height: 64,
              margin: const EdgeInsets.only(bottom: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppTheme.brandGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.verified_user_rounded, color: Colors.white, size: 32),
            ),
            Text(
              'Verify Your Identity',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your BVN or NIN is required to activate your wallet. This is a one-time step.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, height: 1.55),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _TypeChip(
                    label: 'BVN',
                    selected: _type == 'bvn',
                    onTap: () => setState(() => _type = 'bvn'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TypeChip(
                    label: 'NIN',
                    selected: _type == 'nin',
                    onTap: () => setState(() => _type = 'nin'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              maxLength: 11,
              decoration: InputDecoration(
                labelText: '${_type.toUpperCase()} Number',
                hintText: 'Enter your 11-digit ${_type.toUpperCase()}',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Verify & Continue'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.14)
              : AppTheme.elevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            color: selected ? AppTheme.primary : AppTheme.muted,
          ),
        ),
      ),
    );
  }
}

// ── Custom bottom nav ──────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.currentIndex, required this.onTap});
  final int currentIndex;
  final void Function(int) onTap;

  static const _items = [
    _NavItem(icon: Icons.wallet_outlined, activeIcon: Icons.wallet_rounded, label: 'Wallet'),
    _NavItem(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Chats'),
    _NavItem(icon: Icons.storefront_outlined, activeIcon: Icons.storefront_rounded, label: 'Market'),
    _NavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.97),
        border: const Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = currentIndex == i;
              return _NavTile(
                item: item,
                selected: selected,
                onTap: () => onTap(i),
              );
            }),
          ),
        ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.activeIcon, required this.label});
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap});
  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                key: ValueKey(selected),
                color: selected ? AppTheme.primaryBright : AppTheme.muted,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: selected ? AppTheme.primaryBright : AppTheme.muted,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
