import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/forms/form_validators.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/admin_repository.dart';

class AdminDepositsScreen extends ConsumerStatefulWidget {
  const AdminDepositsScreen({super.key});

  @override
  ConsumerState<AdminDepositsScreen> createState() =>
      _AdminDepositsScreenState();
}

class _AdminDepositsScreenState extends ConsumerState<AdminDepositsScreen> {
  late Future<List<dynamic>> future = load();
  bool refreshing = false;
  final Set<String> crediting = {};

  Future<List<dynamic>> load() => ref.read(adminRepositoryProvider).deposits();

  Future<void> refresh() async {
    if (refreshing) return;
    setState(() => refreshing = true);
    try {
      await ref.read(adminRepositoryProvider).refreshDeposits();
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Deposits refreshed',
          message: 'The latest Bitcoin deposits have been loaded.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> credit(String depositId, String userId) async {
    if (crediting.contains(depositId)) return;
    setState(() => crediting.add(depositId));
    try {
      await ref.read(adminRepositoryProvider).creditDeposit(depositId, userId);
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Deposit credited',
          message: 'The user wallet balance has been updated.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => crediting.remove(depositId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Deposit review',
      subtitle: 'Match and credit BTC deposits',
      actions: [
        IconButton(
          onPressed: refreshing ? null : refresh,
          icon: refreshing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Sign out',
          onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
      body: FutureBuilder<List<dynamic>>(
        future: future,
        builder: (context, snapshot) => AsyncStateView<List<dynamic>>(
          snapshot: snapshot,
          onRetry: () => setState(() {
            future = load();
          }),
          builder: (rows) {
            if (rows.isEmpty) {
              return const EmptyState(
                icon: Icons.inbox_outlined,
                title: 'No deposits to review',
                message: 'New Bitcoin deposits will appear here.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final deposit = rows[index] as Map;
                final userId = TextEditingController();
                final formKey = GlobalKey<FormState>();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ExchangeCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const AssetAvatar(
                              label: 'BTC',
                              icon: Icons.currency_bitcoin_rounded,
                              color: Color(0xffffa726),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${deposit['amount_btc']} BTC',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            StatusPill(
                              label: '${deposit['status']}',
                              color: deposit['status'] == 'unmatched'
                                  ? AppTheme.warning
                                  : AppTheme.success,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${deposit['confirmations']} network confirmations',
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                        SelectableText(
                          'tx ${deposit['txid']}:${deposit['vout']}',
                        ),
                        if (deposit['from_address'] != null)
                          SelectableText('from ${deposit['from_address']}'),
                        if (deposit['status'] == 'unmatched') ...[
                          const SizedBox(height: 8),
                          Form(
                            key: formKey,
                            child: FieldContainer(
                              child: TextFormField(
                                controller: userId,
                                validator: (value) =>
                                    FormValidators.requiredText(
                                      value,
                                      label: 'User ID',
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'User ID to credit',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: crediting.contains('${deposit['id']}')
                                ? null
                                : () {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    credit(
                                      '${deposit['id']}',
                                      userId.text.trim(),
                                    );
                                  },
                            icon: const Icon(Icons.add_card_rounded),
                            label: const Text('Credit deposit'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

void showError(BuildContext context, Object error) {
  showApiError(context, error);
}
