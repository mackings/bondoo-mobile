import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/coin_logo.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../trades/data/trade_events.dart';
import '../../trades/data/trade_repository.dart';
import '../../trades/presentation/trade_detail_screen.dart';
import '../data/wallet_repository.dart';

double _usdValue(String asset, double amount) => switch (asset) {
      'BTC' => amount * 68000,
      'ETH' => amount * 3200,
      _ => amount,
    };

final _compact = NumberFormat.compactCurrency(symbol: r'$');
final _full    = NumberFormat.currency(symbol: r'$');

// Default first network per coin (shown before any user selection)
const _defaultNetwork = {
  'BTC':  'BTC',
  'ETH':  'ERC20',
  'USDC': 'ERC20',
  'USDT': 'TRC20',
};

const _assetNetworks = {
  'BTC':  ['BTC'],
  'ETH':  ['ERC20'],
  'USDC': ['ERC20', 'TRC20', 'BSC'],
  'USDT': ['TRC20', 'ERC20', 'BSC'],
};

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  late Future<_WalletData> _future = _load();
  String _selectedAsset = 'BTC';

  // Per-asset selected network (persists across asset switches)
  final Map<String, String> _selectedNetworks = {
    'BTC':  'BTC',
    'ETH':  'ERC20',
    'USDC': 'ERC20',
    'USDT': 'TRC20',
  };

  bool _checkingDeposit = false;
  Map<String, dynamic>? _depositResult;

  bool _verifyingOnchain = false;
  Map<String, dynamic>? _onchainVerifyResult;

  Timer? _pollingTimer;
  StreamSubscription<String>? _eventSub;

  String get _selectedNetwork =>
      _selectedNetworks[_selectedAsset] ?? _defaultNetwork[_selectedAsset] ?? 'BTC';

  Future<_WalletData> _load() async {
    final walletRepo = ref.read(walletRepositoryProvider);
    final tradeRepo  = ref.read(tradeRepositoryProvider);
    final results = await Future.wait([
      walletRepo.getWallet(),
      tradeRepo.list(),
      walletRepo.getWithdrawals(),
    ]);
    final raw = results[0] as Map<String, dynamic>;
    return _WalletData(
      balances: (raw['balances'] as Map).map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
      addresses: (raw['addresses'] as Map).map(
        (k, v) => MapEntry(
          k as String,
          (v as Map).map((nk, nv) => MapEntry(nk as String, nv as String)),
        ),
      ),
      derivationPaths: (raw['derivation_paths'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k as String,
          (v as Map).map((nk, nv) => MapEntry(nk as String, nv as String)),
        ),
      ),
      walletIndex: raw['wallet_index'] as int? ?? 0,
      trades:      results[1] as List,
      withdrawals: results[2] as List,
    );
  }

  void _refresh() => setState(() => _future = _load());

  @override
  void initState() {
    super.initState();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    _eventSub     = TradeEvents.instance.onTradeUpdated.listen((_) => _refresh());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  Future<void> _checkDeposit(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _checkingDeposit = true;
      _depositResult   = null;
    });
    try {
      final result = await ref.read(walletRepositoryProvider).checkDeposit(
        coin:    _selectedAsset,
        network: _selectedNetwork,
      );
      if (mounted) setState(() => _depositResult = result);
      if (result['credited'] == true || result['already_credited'] == true) {
        _refresh();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingDeposit = false);
    }
  }

  Future<void> _verifyOnchain(BuildContext context) async {
    setState(() {
      _verifyingOnchain    = true;
      _onchainVerifyResult = null;
    });
    try {
      final result = await ref.read(walletRepositoryProvider).getOnchainBalance(
        coin:    _selectedAsset,
        network: _selectedNetwork,
      );
      if (mounted) setState(() => _onchainVerifyResult = result);
    } catch (e) {
      if (mounted) showApiError(context, e, title: 'Verification failed');
    } finally {
      if (mounted) setState(() => _verifyingOnchain = false);
    }
  }

  void _showWithdrawSheet(BuildContext context, _WalletData data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => _WithdrawSheet(
        widgetRef: ref,
        coin:      _selectedAsset,
        network:   _selectedNetwork,
        balance:   data.balances[_selectedAsset] ?? 0,
        onWithdrawn: _refresh, // sheet shows its own success dialog
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: FutureBuilder<_WalletData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError && !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.danger, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.muted),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            );
          }
          final data = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                _buildHeroSliver(context, data),
                _buildAssetPickerSliver(data),
                _buildAssetDetailSliver(data),
                _buildDepositSliver(context, data),
                _buildHdInfoSliver(context, data),
                _buildTradesHeaderSliver(context, data),
                _buildTradesSliver(context, data),
                _buildWithdrawHistorySliver(context, data),
                const SliverToBoxAdapter(child: SizedBox(height: 96)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── HERO BALANCE CARD ───────────────────────────────────────────────────────
  Widget _buildHeroSliver(BuildContext context, _WalletData data) {
    final totalUsd   = data.balances.entries.fold(0.0, (s, e) => s + _usdValue(e.key, e.value));
    final selectedBal = data.balances[_selectedAsset] ?? 0;
    final selectedUsd = _usdValue(_selectedAsset, selectedBal);

    return SliverToBoxAdapter(
      child: Container(
        margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff1a1a2e), Color(0xff16213e), AppTheme.backgroundSoft],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'My Wallet',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _full.format(totalUsd),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.trending_up_rounded, color: AppTheme.success, size: 15),
                  const SizedBox(width: 4),
                  const Text(
                    'Total portfolio value',
                    style: TextStyle(color: Colors.white54, fontSize: 12.5),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'On-chain',
                          style: TextStyle(
                            color: AppTheme.success,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    CoinLogo(coin: _selectedAsset, size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedAsset,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            _coinName(_selectedAsset),
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          selectedBal.toStringAsFixed(
                            _selectedAsset == 'USDC' || _selectedAsset == 'USDT' ? 2 : 8,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _compact.format(selectedUsd),
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── ASSET PICKER CHIPS ──────────────────────────────────────────────────────
  Widget _buildAssetPickerSliver(_WalletData data) {
    return SliverToBoxAdapter(
      child: Container(
        color: AppTheme.backgroundSoft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Row(
            children: ['BTC', 'ETH', 'USDC', 'USDT'].map((asset) {
              final selected = _selectedAsset == asset;
              final bal      = data.balances[asset] ?? 0;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedAsset       = asset;
                  _depositResult       = null;
                  _onchainVerifyResult = null;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primary.withValues(alpha: 0.18) : AppTheme.elevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppTheme.primary : AppTheme.border,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CoinLogo(coin: asset, size: 26),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            asset,
                            style: TextStyle(
                              color: selected ? AppTheme.primary : AppTheme.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            bal.toStringAsFixed(asset == 'USDC' || asset == 'USDT' ? 2 : 4),
                            style: TextStyle(
                              color: selected
                                  ? AppTheme.primary.withValues(alpha: 0.7)
                                  : AppTheme.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // ── ALL ASSETS DETAIL LIST ──────────────────────────────────────────────────
  Widget _buildAssetDetailSliver(_WalletData data) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(title: 'Assets', icon: Icons.donut_large_rounded),
            const SizedBox(height: 12),
            ExchangeCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: ['BTC', 'ETH', 'USDC', 'USDT'].asMap().entries.map((entry) {
                  final i      = entry.key;
                  final asset  = entry.value;
                  final bal    = data.balances[asset] ?? 0;
                  final usd    = _usdValue(asset, bal);
                  final isLast = i == 3;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            CoinLogo(coin: asset, size: 40),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _coinName(asset),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    asset,
                                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  bal.toStringAsFixed(
                                    asset == 'USDC' || asset == 'USDT' ? 2 : 8,
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _compact.format(usd),
                                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!isLast)
                        const Divider(height: 1, indent: 70, color: AppTheme.border),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DEPOSIT / WITHDRAW ──────────────────────────────────────────────────────
  Widget _buildDepositSliver(BuildContext context, _WalletData data) {
    final networks = _assetNetworks[_selectedAsset] ?? <String>[];
    final address  = data.addresses[_selectedAsset]?[_selectedNetwork] ?? '';
    final qrData   = _qrData(_selectedAsset, _selectedNetwork, address);

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _SectionHeader(
                  title: 'Deposit $_selectedAsset',
                  icon: Icons.qr_code_scanner_rounded,
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  label: const Text('Withdraw'),
                  onPressed: () => _showWithdrawSheet(context, data),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExchangeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Network selector (only shown when coin has multiple networks)
                  if (networks.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: networks.map((net) {
                          final selected = _selectedNetwork == net;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedNetworks[_selectedAsset] = net;
                              _depositResult       = null;
                              _onchainVerifyResult = null;
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppTheme.primary.withValues(alpha: 0.15)
                                    : AppTheme.elevated,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: selected ? AppTheme.primary : AppTheme.border,
                                  width: selected ? 1.5 : 1,
                                ),
                              ),
                              child: Text(
                                net,
                                style: TextStyle(
                                  color: selected ? AppTheme.primary : AppTheme.text,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // QR code
                  if (address.isNotEmpty)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: QrImageView(data: qrData, size: 160),
                      ),
                    ),
                  const SizedBox(height: 12),

                  // Address — selectable so user can copy manually
                  SelectableText(
                    address.isEmpty ? 'Loading address...' : address,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryBright,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Copy button
                  OutlinedButton.icon(
                    onPressed: address.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: address));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Address copied')),
                            );
                          },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: const Text('Copy Address'),
                  ),
                  const SizedBox(height: 10),

                  // Check deposit button
                  FilledButton.icon(
                    onPressed: (_checkingDeposit || address.isEmpty)
                        ? null
                        : () => _checkDeposit(context),
                    icon: _checkingDeposit
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Check for Deposit'),
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.success),
                  ),

                  // Deposit result banner
                  if (_depositResult != null) ...[
                    const SizedBox(height: 10),
                    _DepositResultBanner(result: _depositResult!),
                  ],
                  const SizedBox(height: 8),

                  // Verify on-chain button
                  OutlinedButton.icon(
                    onPressed: (_verifyingOnchain || address.isEmpty)
                        ? null
                        : () => _verifyOnchain(context),
                    icon: _verifyingOnchain
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('Verify on-chain'),
                  ),

                  // On-chain verify result
                  if (_onchainVerifyResult != null) ...[
                    const SizedBox(height: 8),
                    _OnchainVerifyBanner(result: _onchainVerifyResult!),
                  ],
                  const SizedBox(height: 10),

                  // Warning banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xffffa726).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xffffa726),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Send only $_selectedAsset on $_selectedNetwork to this address. '
                            'After sending, tap "Check for Deposit" to credit your balance.',
                            style: const TextStyle(
                              color: Color(0xffffa726),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── TRADES HEADER ───────────────────────────────────────────────────────────
  Widget _buildTradesHeaderSliver(BuildContext context, _WalletData data) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 12),
        child: Row(
          children: [
            const Icon(Icons.swap_horiz_rounded, color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            const Text(
              'Trade History',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const Spacer(),
            Text(
              '${data.trades.length} trade${data.trades.length == 1 ? '' : 's'}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // ── TRADES LIST ─────────────────────────────────────────────────────────────
  Widget _buildTradesSliver(BuildContext context, _WalletData data) {
    if (data.trades.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
          child: ExchangeCard(
            child: const Column(
              children: [
                SizedBox(height: 12),
                Icon(Icons.receipt_long_rounded, color: AppTheme.muted, size: 36),
                SizedBox(height: 10),
                Text('No trades yet', style: TextStyle(fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text(
                  'Open the Market tab to start a P2P trade.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
                SizedBox(height: 12),
              ],
            ),
          ),
        ),
      );
    }

    final myId = ref.read(authControllerProvider).user?['id'] ?? '';

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      sliver: SliverList.separated(
        itemCount: data.trades.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final trade = data.trades[i] as Map<String, dynamic>;
          return _TradeTile(
            trade: trade,
            myId: myId,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => TradeDetailScreen(trade: trade)),
            ).then((_) => _refresh()),
          );
        },
      ),
    );
  }

  // ── HD WALLET DISCLOSURE ─────────────────────────────────────────────────
  Widget _buildHdInfoSliver(BuildContext context, _WalletData data) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionHeader(
              title: 'Wallet Verification',
              icon: Icons.fingerprint_rounded,
            ),
            const SizedBox(height: 12),
            ExchangeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tag_rounded, color: AppTheme.primary, size: 16),
                      const SizedBox(width: 8),
                      const Text(
                        'Wallet Index',
                        style: TextStyle(color: AppTheme.muted, fontSize: 13),
                      ),
                      const Spacer(),
                      Text(
                        '#${data.walletIndex}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppTheme.primaryBright,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: AppTheme.border),
                  const Text(
                    'Derivation Paths',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...data.derivationPaths.entries.expand((coinEntry) {
                    return coinEntry.value.entries.map((netEntry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 52,
                              child: Text(
                                '${coinEntry.key}\n${netEntry.key}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.muted,
                                  height: 1.35,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: netEntry.value));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Path copied')),
                                  );
                                },
                                child: Text(
                                  netEntry.value,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    color: AppTheme.primaryBright,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    });
                  }),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.elevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'You can verify any address above using a BIP39 mnemonic tool '
                      'with the platform seed phrase and the derivation path shown. '
                      'Tap a path to copy it.',
                      style: TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── WITHDRAWAL HISTORY ───────────────────────────────────────────────────
  Widget _buildWithdrawHistorySliver(BuildContext context, _WalletData data) {
    if (data.withdrawals.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _SectionHeader(
                  title: 'Withdrawals',
                  icon: Icons.arrow_upward_rounded,
                ),
                const Spacer(),
                Text(
                  '${data.withdrawals.length}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ExchangeCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: data.withdrawals.asMap().entries.map((e) {
                  final i = e.key;
                  final w = e.value as Map<String, dynamic>;
                  final coin     = '${w['coin'] ?? ''}';
                  final network  = '${w['network'] ?? ''}';
                  final amount   = (w['amount'] as num?)?.toDouble() ?? 0;
                  final txid     = '${w['txid'] ?? ''}';
                  final status   = '${w['status'] ?? 'completed'}';
                  final date     = _formatDate(w['created_at']);
                  final isLast   = i == data.withdrawals.length - 1;
                  final short    = txid.length > 12 ? '${txid.substring(0, 12)}…' : txid;
                  final isStable = coin == 'USDC' || coin == 'USDT';

                  Color statusColor;
                  Widget statusIcon;
                  if (status == 'pending') {
                    statusColor = Colors.orange;
                    statusIcon  = const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                    );
                  } else if (status == 'failed') {
                    statusColor = AppTheme.danger;
                    statusIcon  = const Icon(Icons.error_outline, color: AppTheme.danger, size: 14);
                  } else {
                    statusColor = AppTheme.danger;
                    statusIcon  = const SizedBox.shrink();
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                color: statusColor,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Sent $coin · $network',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (status != 'completed') ...[
                                        const SizedBox(width: 6),
                                        statusIcon,
                                        const SizedBox(width: 4),
                                        Text(
                                          status,
                                          style: TextStyle(
                                            color: statusColor,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (txid.isNotEmpty)
                                    GestureDetector(
                                      onTap: () {
                                        Clipboard.setData(ClipboardData(text: txid));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Txid copied')),
                                        );
                                      },
                                      child: Text(
                                        'txid: $short · $date',
                                        style: const TextStyle(
                                          color: AppTheme.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      date,
                                      style: const TextStyle(
                                        color: AppTheme.muted,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '-${amount.toStringAsFixed(isStable ? 2 : 8)} $coin',
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!isLast) const Divider(height: 1, indent: 68, color: AppTheme.border),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── QR data helper ──────────────────────────────────────────────────────────
String _qrData(String coin, String network, String address) {
  if (address.isEmpty) return address;
  if (coin == 'BTC' || network == 'BTC') return 'bitcoin:$address';
  if (network == 'TRC20')                return 'tron:$address';
  return 'ethereum:$address';
}

// ── Deposit result banner ────────────────────────────────────────────────────
class _DepositResultBanner extends StatelessWidget {
  const _DepositResultBanner({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final found           = result['found'] as bool? ?? false;
    final credited        = result['credited'] as bool? ?? false;
    final alreadyCredited = result['already_credited'] as bool? ?? false;
    final txid            = result['txid'] as String? ?? '';
    final amount          = result['amount'] as String? ?? '';
    final coin            = result['coin'] as String? ?? '';

    final Color color;
    final IconData icon;
    final String message;

    if (!found) {
      color   = AppTheme.muted;
      icon    = Icons.search_off_rounded;
      message = 'No deposit found yet. After sending, wait for at least 1 confirmation then check again.';
    } else if (alreadyCredited) {
      color   = AppTheme.muted;
      icon    = Icons.check_circle_outline_rounded;
      message = 'This deposit ($amount $coin) was already credited to your balance.';
    } else if (credited) {
      color   = AppTheme.success;
      icon    = Icons.check_circle_rounded;
      final short = txid.length > 16 ? '${txid.substring(0, 16)}...' : txid;
      message = '$amount $coin credited to your wallet!\nTxid: $short';
    } else {
      color   = AppTheme.muted;
      icon    = Icons.info_outline_rounded;
      message = 'Deposit detected but not yet credited.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── On-chain verify banner ───────────────────────────────────────────────────
class _OnchainVerifyBanner extends StatelessWidget {
  const _OnchainVerifyBanner({required this.result});
  final Map<String, dynamic> result;

  @override
  Widget build(BuildContext context) {
    final onchain = (result['onchain_balance'] as num?)?.toDouble() ?? 0;
    final inapp   = (result['inapp_balance']   as num?)?.toDouble() ?? 0;
    final coin    = '${result['coin'] ?? ''}';
    final isStable = coin == 'USDC' || coin == 'USDT';
    final dp       = isStable ? 4 : 8;

    final diff    = (onchain - inapp).abs();
    final synced  = diff < (isStable ? 0.0001 : 0.00000001);

    final color   = synced ? AppTheme.success : const Color(0xffffa726);
    final icon    = synced ? Icons.check_circle_rounded : Icons.warning_amber_rounded;
    final label   = synced ? 'Balances match' : 'Difference detected';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color, fontWeight: FontWeight.w800, fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _balanceRow('On-chain', onchain, coin, dp),
          const SizedBox(height: 4),
          _balanceRow('In-app',   inapp,   coin, dp),
          if (!synced) ...[
            const SizedBox(height: 8),
            Text(
              'Tap "Check for Deposit" to sync any undetected deposit.',
              style: TextStyle(color: color, fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _balanceRow(String label, double amount, String coin, int dp) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.muted, fontSize: 12),
          ),
        ),
        Text(
          '${amount.toStringAsFixed(dp)} $coin',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Withdraw bottom sheet ────────────────────────────────────────────────────
class _WithdrawSheet extends StatefulWidget {
  const _WithdrawSheet({
    required this.widgetRef,
    required this.coin,
    required this.network,
    required this.balance,
    required this.onWithdrawn,
  });

  final WidgetRef widgetRef;
  final String coin;
  final String network;
  final double balance;
  final VoidCallback onWithdrawn;

  @override
  State<_WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends State<_WithdrawSheet> {
  final formKey    = GlobalKey<FormState>();
  final amountCtrl  = TextEditingController();
  final addressCtrl = TextEditingController();
  bool submitting = false;

  @override
  void dispose() {
    amountCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!formKey.currentState!.validate() || submitting) return;
    setState(() => submitting = true);
    try {
      final result = await widget.widgetRef.read(walletRepositoryProvider).withdraw(
        coin:      widget.coin,
        network:   widget.network,
        amount:    double.parse(amountCtrl.text.trim()),
        toAddress: addressCtrl.text.trim(),
      );
      widget.onWithdrawn();
      if (!mounted) return;
      Navigator.pop(context);
      showApiSuccess(
        context,
        title: 'Withdrawal Sent',
        message:
            '${result['amount']} ${result['coin']} broadcast on ${result['network']}.\n\n'
            'Txid: ${result['txid']}',
      );
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStable = widget.coin == 'USDC' || widget.coin == 'USDT';
    final decimals  = isStable ? 2 : 8;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 8, 20, MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Withdraw ${widget.coin}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Balance: ${widget.balance.toStringAsFixed(decimals)} ${widget.coin} · '
              'Network: ${widget.network}',
              style: const TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.coin})',
                suffixText: widget.coin,
              ),
              validator: (v) {
                final d = double.tryParse(v?.trim() ?? '');
                if (d == null || d <= 0) return 'Enter a valid amount';
                if (d > widget.balance) return 'Exceeds your balance';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: addressCtrl,
              decoration: InputDecoration(
                labelText: '${widget.coin} destination address',
                hintText: 'External wallet address',
              ),
              validator: (v) =>
                  (v == null || v.trim().length < 10) ? 'Enter a valid address' : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: submitting ? null : _submit,
              icon: submitting
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Send Withdrawal'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Trade tile ──────────────────────────────────────────────────────────────
class _TradeTile extends StatelessWidget {
  const _TradeTile({
    required this.trade,
    required this.myId,
    required this.onTap,
  });

  final Map<String, dynamic> trade;
  final String myId;
  final VoidCallback onTap;

  bool   get _isBuyer => trade['buyer_user_id'] == myId;
  String get _coin    => '${trade['coin'] ?? ''}';
  String get _status  => '${trade['status'] ?? ''}';
  double get _crypto  => double.tryParse('${trade['crypto_amount'] ?? ''}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor, statusIcon) = _statusMeta(_status);
    final counterParty = _isBuyer ? (trade['seller'] as Map?) : (trade['buyer'] as Map?);
    final counterName  =
        '${counterParty?['display_name'] ?? counterParty?['username'] ?? 'Trader'}';
    final date = _formatDate(trade['created_at']);

    return GestureDetector(
      onTap: onTap,
      child: ExchangeCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CoinLogo(coin: _coin, size: 44),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: _isBuyer ? AppTheme.success : AppTheme.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.background, width: 2),
                    ),
                    child: Icon(
                      _isBuyer
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isBuyer ? 'Bought $_coin' : 'Sold $_coin',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$counterName · $date',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_isBuyer ? '+' : '-'}${_crypto.toStringAsFixed(4)} $_coin',
                  style: TextStyle(
                    color: _isBuyer ? AppTheme.success : AppTheme.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ],
    );
  }
}

// ── Helpers ─────────────────────────────────────────────────────────────────
String _coinName(String coin) => switch (coin) {
      'BTC'  => 'Bitcoin',
      'ETH'  => 'Ethereum',
      'USDC' => 'USD Coin',
      'USDT' => 'Tether',
      _      => coin,
    };

(String, Color, IconData) _statusMeta(String status) => switch (status) {
      'pending'       => ('Pending',       AppTheme.muted,    Icons.hourglass_empty_rounded),
      'escrowed'      => ('Escrowed',      AppTheme.primary,  Icons.lock_rounded),
      'payment_sent'  => ('Pay Sent',      AppTheme.accent,   Icons.send_rounded),
      'releasing'     => ('Releasing',     AppTheme.accent,   Icons.sync_rounded),
      'completed'     => ('Completed',     AppTheme.success,  Icons.check_circle_rounded),
      'cancelled'     => ('Cancelled',     AppTheme.danger,   Icons.cancel_rounded),
      'disputed'      => ('Disputed',      AppTheme.danger,   Icons.gavel_rounded),
      _               => (status,          AppTheme.muted,    Icons.info_outline_rounded),
    };

String _formatDate(dynamic raw) {
  if (raw == null) return '';
  try {
    final dt = DateTime.parse('$raw').toLocal();
    return DateFormat('MMM d').format(dt);
  } catch (_) {
    return '';
  }
}

// ── Data model ──────────────────────────────────────────────────────────────
class _WalletData {
  final Map<String, double>              balances;
  final Map<String, Map<String, String>> addresses;
  final Map<String, Map<String, String>> derivationPaths;
  final int                              walletIndex;
  final List                             trades;
  final List                             withdrawals;

  const _WalletData({
    required this.balances,
    required this.addresses,
    required this.derivationPaths,
    required this.walletIndex,
    required this.trades,
    required this.withdrawals,
  });
}
