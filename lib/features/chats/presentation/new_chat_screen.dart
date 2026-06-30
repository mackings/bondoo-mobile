import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../contacts/data/contacts_repository.dart';
import '../../contacts/presentation/contacts_screen.dart';
import '../data/chat_repository.dart';
import 'chat_helpers.dart';
import 'chat_screen.dart';

class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final query = TextEditingController();
  List<dynamic> users = [];
  bool busy = false;
  String? openingUserId;

  // Contacts-on-app strip
  List<BondooContact>? _bondooContacts;
  bool _contactsLoading = false;

  @override
  void initState() {
    super.initState();
    search();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() => _contactsLoading = true);
    try {
      final result =
          await ref.read(contactsRepositoryProvider).syncContacts();
      if (!mounted) return;
      setState(() => _bondooContacts = result.where((c) => c.isOnApp).toList());
    } catch (_) {
      // Silently ignore — contacts strip is best-effort
    } finally {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> search() async {
    setState(() => busy = true);
    try {
      users = await ref.read(chatRepositoryProvider).searchUsers(query.text);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(Map user) async {
    final userId = '${user['id']}';
    if (openingUserId != null) return;
    setState(() => openingUserId = userId);
    try {
      final id = await ref.read(chatRepositoryProvider).openDirect(userId);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversation: {
              'id': id,
              'is_group': false,
              'conversation_members': [
                {'user_id': user['id'], 'profiles': user},
              ],
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => openingUserId = null);
    }
  }

  Future<void> _openFromContact(BondooContact contact) async {
    final user = contact.user!;
    await open(user);
  }

  void _pushContacts() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ContactsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bondooOnApp = _bondooContacts;
    final showStrip =
        bondooOnApp != null && bondooOnApp.isNotEmpty && !_contactsLoading;

    return ExchangeScaffold(
      title: 'New chat',
      subtitle: 'Find someone on BONDOO',
      actions: [
        IconButton(
          tooltip: 'Contacts',
          icon: const Icon(Icons.person_add_rounded),
          onPressed: _pushContacts,
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── "From your contacts" horizontal strip ──────────────────────
          if (showStrip) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Text(
                    'FROM YOUR CONTACTS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _pushContacts,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('See all'),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: bondooOnApp.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final contact = bondooOnApp[index];
                  final user = contact.user!;
                  final displayName =
                      '${user['display_name'] ?? contact.name}';
                  return GestureDetector(
                    onTap: () => _openFromContact(contact),
                    child: SizedBox(
                      width: 64,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AssetAvatar(
                            label: initials(displayName),
                            imageUrl: '${user['avatar_url'] ?? ''}',
                            color: index.isEven
                                ? AppTheme.primary
                                : AppTheme.accent,
                            size: 48,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            displayName,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Search field ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextField(
              controller: query,
              decoration: InputDecoration(
                hintText: 'Search name or username',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: search,
                ),
              ),
              onSubmitted: (_) => search(),
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),

          // ── Search results ─────────────────────────────────────────────
          Expanded(
            child: users.isEmpty && !busy
                ? const EmptyState(
                    icon: Icons.person_search_rounded,
                    title: 'Find your contacts',
                    message:
                        'Search by display name or username to begin a conversation.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: users.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final user = users[index] as Map;
                      return ExchangeCard(
                        padding: EdgeInsets.zero,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          leading: AssetAvatar(
                            label: initials('${user['display_name']}'),
                            imageUrl: '${user['avatar_url'] ?? ''}',
                            color: index.isEven
                                ? AppTheme.primary
                                : AppTheme.accent,
                          ),
                          title: Text(
                            '${user['display_name']}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            '@${user['username']}',
                            style: const TextStyle(color: AppTheme.muted),
                          ),
                          trailing: openingUserId == '${user['id']}'
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: AppTheme.primaryBright,
                                ),
                          onTap: openingUserId == null
                              ? () => open(user)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

void showError(BuildContext context, Object error) {
  showApiError(context, error);
}
