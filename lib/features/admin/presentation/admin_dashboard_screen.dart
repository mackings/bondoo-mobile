import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/admin_repository.dart';
import 'admin_deposits_screen.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  late Future<Map<String, dynamic>> future = load();

  Future<Map<String, dynamic>> load() =>
      ref.read(adminRepositoryProvider).overview();

  Future<void> reload() async {
    final next = load();
    setState(() {
      future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Admin',
      subtitle: 'App activity, money movement, and system health',
      actions: [
        IconButton(onPressed: reload, icon: const Icon(Icons.refresh_rounded)),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
      body: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) => AsyncStateView<Map<String, dynamic>>(
          snapshot: snapshot,
          onRetry: reload,
          builder: (overview) =>
              AdminDashboardBody(overview: overview, onRefresh: reload),
        ),
      ),
    );
  }
}

class AdminDashboardBody extends StatelessWidget {
  const AdminDashboardBody({
    super.key,
    required this.overview,
    required this.onRefresh,
  });

  final Map<String, dynamic> overview;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final metrics = mapValue(overview['metrics']);
    final users = mapValue(metrics['users']);
    final offers = mapValue(metrics['offers']);
    final chats = mapValue(metrics['chats']);
    final escrows = mapValue(metrics['escrows']);
    final deposits = mapValue(metrics['deposits']);
    final wallets = mapValue(metrics['wallets']);
    final system = mapValue(overview['system']);
    final recent = mapValue(overview['recent']);
    final recentUsers = listValue(recent['users']);
    final recentEscrows = listValue(recent['escrows']);
    final recentDeposits = listValue(recent['deposits']);
    final events = listValue(recent['events']);
    final walletBalances = listValue(wallets['balances_by_asset']);
    final offerStatus = mapValue(offers['by_status']);
    final escrowStatus = mapValue(escrows['by_status']);
    final depositStatus = mapValue(deposits['by_status']);
    final messageKinds = mapValue(chats['by_kind']);
    final escrowVolumes = listValue(escrows['volume_by_coin']);
    final depositVolumes = listValue(deposits['volume_by_status']);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AdminMetricGrid(
            cards: [
              AdminMetric(
                label: 'Users',
                value: '${users['total'] ?? 0}',
                detail:
                    '${users['verified'] ?? 0} verified · ${users['new_24h'] ?? 0} new today',
                icon: Icons.people_alt_rounded,
                color: AppTheme.primary,
                onTap: () => openAdminDetail(
                  context,
                  title: 'Users',
                  subtitle: 'Accounts, verification, and setup state',
                  children: [
                    AdminSimpleLine(
                      label: 'Total users',
                      value: '${users['total'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Verified users',
                      value: '${users['verified'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Unverified users',
                      value: '${users['unverified'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'New today',
                      value: '${users['new_24h'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'New this week',
                      value: '${users['new_7d'] ?? 0}',
                    ),
                    const SizedBox(height: 20),
                    AdminRecentSection(
                      title: 'Recent Users',
                      icon: Icons.people_alt_rounded,
                      emptyTitle: 'No users yet',
                      rows: recentUsers.map(userRow).toList(),
                    ),
                  ],
                ),
              ),
              AdminMetric(
                label: 'Escrows',
                value: '${escrows['open'] ?? 0}',
                detail:
                    '${escrows['payout_pending'] ?? 0} payout · ${escrows['disputed'] ?? 0} disputed',
                icon: Icons.security_rounded,
                color: AppTheme.warning,
                onTap: () => openAdminDetail(
                  context,
                  title: 'Escrows',
                  subtitle: 'Escrow status, volume, and recent events',
                  children: [
                    AdminSimpleLine(
                      label: 'Total escrows',
                      value: '${escrows['total'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Open escrows',
                      value: '${escrows['open'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Payout pending',
                      value: '${escrows['payout_pending'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Disputed',
                      value: '${escrows['disputed'] ?? 0}',
                    ),
                    const SizedBox(height: 20),
                    AdminMapSection(
                      title: 'Escrow Status',
                      caption: 'Current transaction state breakdown',
                      icon: Icons.security_rounded,
                      values: escrowStatus,
                    ),
                    const SizedBox(height: 20),
                    AdminRecentSection(
                      title: 'Volume By Coin',
                      icon: Icons.pie_chart_rounded,
                      emptyTitle: 'No escrow volume yet',
                      rows: escrowVolumes
                          .map(
                            (row) => AdminInfoRow(
                              icon: Icons.security_rounded,
                              title: '${row['coin'] ?? 'Coin'}',
                              subtitle:
                                  '${row['count'] ?? 0} escrows · fees ${formatNumber(row['total_fees'])}',
                              trailing: formatNumber(row['total_amount']),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    AdminRecentSection(
                      title: 'Recent Escrows',
                      icon: Icons.receipt_long_rounded,
                      emptyTitle: 'No escrow activity yet',
                      rows: recentEscrows.map(escrowRow).toList(),
                    ),
                    const SizedBox(height: 20),
                    AdminRecentSection(
                      title: 'Escrow Events',
                      icon: Icons.timeline_rounded,
                      emptyTitle: 'No events yet',
                      rows: events.map(eventRow).toList(),
                    ),
                  ],
                ),
              ),
              AdminMetric(
                label: 'Deposits',
                value: '${deposits['unmatched'] ?? 0}',
                detail:
                    '${deposits['credited'] ?? 0} credited · ${deposits['total'] ?? 0} total',
                icon: Icons.currency_bitcoin_rounded,
                color: const Color(0xffffa726),
                onTap: () => openAdminDetail(
                  context,
                  title: 'Deposits',
                  subtitle: 'BTC deposits and matching status',
                  children: [
                    AdminSimpleLine(
                      label: 'Total deposits',
                      value: '${deposits['total'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Unmatched deposits',
                      value: '${deposits['unmatched'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Credited deposits',
                      value: '${deposits['credited'] ?? 0}',
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AdminDepositsScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.monitor_heart_outlined),
                      label: const Text('Review BTC deposits'),
                    ),
                    const SizedBox(height: 20),
                    AdminMapSection(
                      title: 'Deposit Status',
                      caption: 'Current BTC deposit breakdown',
                      icon: Icons.currency_bitcoin_rounded,
                      values: depositStatus,
                    ),
                    const SizedBox(height: 20),
                    AdminRecentSection(
                      title: 'Volume By Status',
                      icon: Icons.bar_chart_rounded,
                      emptyTitle: 'No deposit volume yet',
                      rows: depositVolumes
                          .map(
                            (row) => AdminInfoRow(
                              icon: Icons.currency_bitcoin_rounded,
                              title: '${row['status'] ?? 'Status'}',
                              subtitle: '${row['count'] ?? 0} deposits',
                              trailing: '${formatNumber(row['total_btc'])} BTC',
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 20),
                    AdminRecentSection(
                      title: 'Recent Deposits',
                      icon: Icons.currency_bitcoin_rounded,
                      emptyTitle: 'No deposits yet',
                      rows: recentDeposits.map(depositRow).toList(),
                    ),
                  ],
                ),
              ),
              AdminMetric(
                label: 'Messages',
                value: '${chats['messages_24h'] ?? 0}',
                detail:
                    '${chats['messages'] ?? 0} total · ${chats['conversations'] ?? 0} chats',
                icon: Icons.forum_rounded,
                color: AppTheme.success,
                onTap: () => openAdminDetail(
                  context,
                  title: 'Messages',
                  subtitle: 'Chat volume and content types',
                  children: [
                    AdminSimpleLine(
                      label: 'Conversations',
                      value: '${chats['conversations'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Total messages',
                      value: '${chats['messages'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Messages today',
                      value: '${chats['messages_24h'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Messages this week',
                      value: '${chats['messages_7d'] ?? 0}',
                    ),
                    const SizedBox(height: 20),
                    AdminMapSection(
                      title: 'Message Types',
                      caption: 'Chat activity by content type',
                      icon: Icons.message_rounded,
                      values: messageKinds,
                    ),
                  ],
                ),
              ),
              AdminMetric(
                label: 'Offers',
                value: '${offers['active'] ?? 0}',
                detail: '${offers['total'] ?? 0} total offers',
                icon: Icons.local_offer_rounded,
                color: AppTheme.primaryBright,
                onTap: () => openAdminDetail(
                  context,
                  title: 'Offers',
                  subtitle: 'Marketplace listing status',
                  children: [
                    AdminSimpleLine(
                      label: 'Total offers',
                      value: '${offers['total'] ?? 0}',
                    ),
                    AdminSimpleLine(
                      label: 'Active offers',
                      value: '${offers['active'] ?? 0}',
                    ),
                    const SizedBox(height: 20),
                    AdminMapSection(
                      title: 'Offer Status',
                      caption: 'Marketplace listings by status',
                      icon: Icons.local_offer_rounded,
                      values: offerStatus,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionLabel(
            'Operations',
            caption: 'Quick actions for live app management',
            icon: Icons.admin_panel_settings_rounded,
          ),
          ExchangeCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminDepositsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Review BTC deposits'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel(
            'System Health',
            caption: 'Production configuration checks',
            icon: Icons.health_and_safety_rounded,
          ),
          ExchangeCard(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HealthPill(label: 'API', ok: system['api'] == 'ok'),
                HealthPill(label: 'Database', ok: system['database'] == 'ok'),
                HealthPill(
                  label: 'Email',
                  ok: system['email_configured'] == true,
                ),
                HealthPill(
                  label: 'Agora',
                  ok: system['agora_configured'] == true,
                ),
                HealthPill(
                  label: 'Bybit',
                  ok: system['bybit_configured'] == true,
                ),
                HealthPill(
                  label: system['bybit_dry_run'] == true
                      ? 'Bybit dry run'
                      : 'Bybit live',
                  ok: system['bybit_dry_run'] != true,
                ),
                HealthPill(
                  label: 'BTC address',
                  ok: system['bank_btc_address_configured'] == true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel(
            'Analytics Pages',
            caption: 'Open each area for its full data',
            icon: Icons.dashboard_customize_rounded,
          ),
          AdminNavigationTile(
            icon: Icons.wallet_rounded,
            title: 'Wallet Balances',
            subtitle: 'Aggregate user balances by asset',
            onTap: () => openAdminDetail(
              context,
              title: 'Wallet Balances',
              subtitle: 'Aggregate user balances by asset',
              children: [
                if (walletBalances.isEmpty)
                  const EmptyState(
                    icon: Icons.wallet_outlined,
                    title: 'No wallet balances yet',
                    message:
                        'Wallet totals will appear after user wallets exist.',
                  )
                else
                  ...walletBalances.map(
                    (row) => AdminInfoRow(
                      icon: Icons.account_balance_wallet_rounded,
                      title: '${row['asset'] ?? 'Asset'}',
                      subtitle: '${row['wallet_count'] ?? 0} wallets',
                      trailing: formatNumber(row['total_balance']),
                    ),
                  ),
              ],
            ),
          ),
          AdminNavigationTile(
            icon: Icons.health_and_safety_rounded,
            title: 'System Health',
            subtitle: 'API, database, email, Agora, Bybit, BTC address',
            onTap: () => openAdminDetail(
              context,
              title: 'System Health',
              subtitle: 'Production configuration checks',
              children: [
                ExchangeCard(
                  child: Column(
                    children: [
                      AdminSimpleLine(
                        label: 'API',
                        value: system['api'] == 'ok' ? 'OK' : 'Check',
                      ),
                      AdminSimpleLine(
                        label: 'Database',
                        value: system['database'] == 'ok' ? 'OK' : 'Check',
                      ),
                      AdminSimpleLine(
                        label: 'Email configured',
                        value: system['email_configured'] == true
                            ? 'Yes'
                            : 'No',
                      ),
                      AdminSimpleLine(
                        label: 'Agora configured',
                        value: system['agora_configured'] == true
                            ? 'Yes'
                            : 'No',
                      ),
                      AdminSimpleLine(
                        label: 'Bybit configured',
                        value: system['bybit_configured'] == true
                            ? 'Yes'
                            : 'No',
                      ),
                      AdminSimpleLine(
                        label: 'Bybit mode',
                        value: system['bybit_dry_run'] == true
                            ? 'Dry run'
                            : 'Live',
                      ),
                      AdminSimpleLine(
                        label: 'BTC address configured',
                        value: system['bank_btc_address_configured'] == true
                            ? 'Yes'
                            : 'No',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AdminInfoRow userRow(Map<String, dynamic> row) {
    return AdminInfoRow(
      icon: row['role'] == 'admin'
          ? Icons.admin_panel_settings_rounded
          : Icons.person_rounded,
      title: '${row['display_name'] ?? row['username'] ?? 'User'}',
      subtitle:
          '${row['email'] ?? ''}\n${row['email_verified'] == true ? 'verified' : 'unverified'} · ${row['setup_complete'] == true ? 'setup complete' : 'setup incomplete'}',
      trailing: shortDate(row['created_at']),
    );
  }

  AdminInfoRow escrowRow(Map<String, dynamic> row) {
    return AdminInfoRow(
      icon: Icons.security_rounded,
      title: '${formatNumber(row['amount'])} ${row['coin'] ?? ''}',
      subtitle: humanEventName('${row['status'] ?? 'unknown'}'),
      trailing: shortDate(row['created_at']),
    );
  }

  AdminInfoRow depositRow(Map<String, dynamic> row) {
    return AdminInfoRow(
      icon: Icons.currency_bitcoin_rounded,
      title: '${formatNumber(row['amount_btc'])} BTC',
      subtitle: humanEventName('${row['status'] ?? 'unknown'}'),
      trailing: shortDate(row['created_at']),
    );
  }

  AdminInfoRow eventRow(Map<String, dynamic> row) {
    return AdminInfoRow(
      icon: Icons.timeline_rounded,
      title: humanEventName('${row['event_type'] ?? 'event'}'),
      subtitle: 'Escrow ${shortId('${row['escrow_transaction_id'] ?? ''}')}',
      trailing: shortDate(row['created_at']),
    );
  }
}

void openAdminDetail(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<Widget> children,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => AdminDetailScreen(
        title: title,
        subtitle: subtitle,
        children: children,
      ),
    ),
  );
}

class AdminDetailScreen extends StatelessWidget {
  const AdminDetailScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: title,
      subtitle: subtitle,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: children,
      ),
    );
  }
}

class AdminNavigationTile extends StatelessWidget {
  const AdminNavigationTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: ExchangeCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AssetAvatar(label: title, icon: icon, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminMetric {
  const AdminMetric({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class AdminMetricGrid extends StatelessWidget {
  const AdminMetricGrid({super.key, required this.cards});

  final List<AdminMetric> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 720 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: columns == 3 ? 1.75 : 1.35,
          ),
          itemBuilder: (context, index) {
            final card = cards[index];
            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: card.onTap,
              child: ExchangeCard(
                padding: const EdgeInsets.all(14),
                borderColor: card.color.withValues(alpha: 0.26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(card.icon, color: card.color),
                    const Spacer(),
                    Text(
                      card.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            card.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: AppTheme.muted,
                          size: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      card.detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class HealthPill extends StatelessWidget {
  const HealthPill({super.key, required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: label,
      icon: ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
      color: ok ? AppTheme.success : AppTheme.warning,
    );
  }
}

class AdminMapSection extends StatelessWidget {
  const AdminMapSection({
    super.key,
    required this.title,
    required this.caption,
    required this.icon,
    required this.values,
  });

  final String title;
  final String caption;
  final IconData icon;
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionLabel(title, caption: caption, icon: icon),
        if (values.isEmpty)
          EmptyState(
            icon: icon,
            title: 'No data yet',
            message: 'This breakdown will update as activity grows.',
          )
        else
          ExchangeCard(
            child: Column(
              children: values.entries
                  .map(
                    (entry) => AdminSimpleLine(
                      label: entry.key.replaceAll('_', ' '),
                      value: '${entry.value}',
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

class AdminRecentSection extends StatelessWidget {
  const AdminRecentSection({
    super.key,
    required this.title,
    required this.icon,
    required this.emptyTitle,
    required this.rows,
  });

  final String title;
  final IconData icon;
  final String emptyTitle;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionLabel(title, icon: icon),
        if (rows.isEmpty)
          EmptyState(
            icon: icon,
            title: emptyTitle,
            message: 'New activity will appear here.',
          )
        else
          ...rows,
      ],
    );
  }
}

class AdminInfoRow extends StatelessWidget {
  const AdminInfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ExchangeCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            AssetAvatar(label: title, icon: icon, size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              trailing,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminSimpleLine extends StatelessWidget {
  const AdminSimpleLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.primaryBright,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> mapValue(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry('$key', value));
  }
  return {};
}

List<Map<String, dynamic>> listValue(Object? value) {
  if (value is! List) return [];
  return value
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry('$key', value)))
      .toList();
}

String formatNumber(Object? value) {
  final number = value is num ? value : num.tryParse('$value');
  if (number == null) return '0';
  if (number == number.roundToDouble()) return '${number.toInt()}';
  return number.toStringAsFixed(number.abs() >= 1 ? 4 : 8);
}

String shortDate(Object? value) {
  final parsed = DateTime.tryParse('$value');
  if (parsed == null) return '';
  final local = parsed.toLocal();
  return '${local.month}/${local.day}';
}

String shortId(String value) {
  if (value.length <= 8) return value;
  return value.substring(value.length - 8);
}

String humanEventName(String value) {
  final words = value
      .replaceAll('_', ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return 'Unknown';
  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}
