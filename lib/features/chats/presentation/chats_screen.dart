import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../offers/presentation/offers_screen.dart';
import '../../calls/presentation/call_history_screen.dart';
import '../data/chat_repository.dart';
import 'chat_helpers.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  late Future<List<dynamic>> future = load();

  Future<List<dynamic>> load() =>
      ref.read(chatRepositoryProvider).conversations();

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Chats',
      subtitle: 'Message traders and manage offers',
      actions: [
        IconButton(
          tooltip: 'Call history',
          icon: const Icon(Icons.call_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CallHistoryScreen()),
          ),
        ),
        IconButton(
          tooltip: 'Start a new chat',
          icon: const Icon(Icons.edit_square),
          onPressed: () =>
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NewChatScreen()),
              ).then(
                (_) => setState(() {
                  future = load();
                }),
              ),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: () async => setState(() {
          future = load();
        }),
        child: FutureBuilder<List<dynamic>>(
          future: future,
          builder: (context, snapshot) => AsyncStateView<List<dynamic>>(
            snapshot: snapshot,
            onRetry: () => setState(() {
              future = load();
            }),
            builder: (rows) {
              if (rows.isEmpty) {
                return EmptyState(
                  icon: Icons.forum_outlined,
                  title: 'No conversations yet',
                  message:
                      'Find a trader from offers or manage your own P2P ads.',
                  action: FilledButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const OffersScreen()),
                    ),
                    icon: const Icon(Icons.storefront_rounded),
                    label: const Text('Browse offers'),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 96),
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final conversation = rows[index] as Map<String, dynamic>;
                  final meta = conversationMeta(
                    conversation,
                    currentUserId:
                        ref.read(authControllerProvider).user?['id'] as String?,
                  );
                  final currentUserId =
                      ref.read(authControllerProvider).user?['id'] as String?;
                  final messages = (conversation['messages'] as List? ?? [])
                      .cast<Map>();
                  messages.sort(
                    (a, b) =>
                        '${b['created_at']}'.compareTo('${a['created_at']}'),
                  );
                  final last = messages.isEmpty ? null : messages.first;
                  final preview = conversationPreview(
                    last,
                    currentUserId: currentUserId,
                  );
                  final timestamp = shortDate(
                    last?['created_at'] ?? conversation['last_message_at'],
                  );
                  final unreadCount = conversation['unread_count'] as int? ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: ExchangeCard(
                      padding: const EdgeInsets.all(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () =>
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ChatScreen(conversation: conversation),
                              ),
                            ).then(
                              (_) => setState(() {
                                future = load();
                              }),
                            ),
                        child: Row(
                          children: [
                            AssetAvatar(
                              label: meta.title,
                              imageUrl: meta.avatarUrl,
                              color: index.isEven
                                  ? AppTheme.primary
                                  : AppTheme.accent,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    meta.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    preview,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppTheme.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  timestamp,
                                  style: const TextStyle(
                                    color: AppTheme.muted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (unreadCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.primaryBright,
                                      borderRadius: BorderRadius.all(
                                        Radius.circular(999),
                                      ),
                                    ),
                                    child: Text(
                                      unreadCount > 99 ? '99+' : '$unreadCount',
                                      style: const TextStyle(
                                        color: AppTheme.background,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    color: AppTheme.muted,
                                    size: 20,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
