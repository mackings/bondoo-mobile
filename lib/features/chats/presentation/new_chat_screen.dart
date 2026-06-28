import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
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

  @override
  void initState() {
    super.initState();
    search();
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

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'New chat',
      subtitle: 'Find someone on BONDOO',
      body: Column(
        children: [
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
