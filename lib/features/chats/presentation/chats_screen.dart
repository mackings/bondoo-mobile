import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
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
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _msgSub;

  @override
  void initState() {
    super.initState();
    // Connect socket early so the list gets live updates immediately
    final token = ref.read(authControllerProvider).token;
    if (token != null) SocketService().connect(token, AppConfig.apiBaseUrl);
    _load().then((_) { if (mounted) _subscribe(); });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() { _loading = true; _error = null; });
    }
    try {
      final rows = await ref.read(chatRepositoryProvider).conversations();
      if (mounted) {
        setState(() {
          _conversations = rows.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!silent) _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _subscribe() {
    final myId = ref.read(authControllerProvider).user?['id'] as String?;
    _msgSub = SocketService().onNewMessage.listen((msg) {
      if (!mounted) return;
      final convId = '${msg['conversation_id']}';
      final idx = _conversations.indexWhere((c) => '${c['id']}' == convId);
      if (idx == -1) {
        // New or unknown conversation — reload to pick it up
        _load(silent: true);
        return;
      }
      final conv = Map<String, dynamic>.from(_conversations[idx]);
      final msgs = List<dynamic>.from((conv['messages'] as List?) ?? [])..add(msg);
      conv['messages'] = msgs;
      conv['last_message_at'] = msg['created_at'];
      // Bump unread badge only for messages from the other person
      if ('${msg['sender_id']}' != myId) {
        conv['unread_count'] = ((conv['unread_count'] as int?) ?? 0) + 1;
      }
      setState(() {
        // Move updated conversation to the top
        _conversations = [conv, ..._conversations.where((c) => '${c['id']}' != convId)];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ExchangeScaffold(
      title: 'Chats',
      subtitle: 'Message buyers and sellers',
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
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          ).then((_) => _load(silent: true)),
        ),
      ],
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_conversations.isEmpty) {
      return const EmptyState(
        icon: Icons.forum_outlined,
        title: 'No conversations yet',
        message: 'Start a conversation by tapping a product in the marketplace.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: _conversations.length,
      itemBuilder: (context, index) {
        final conversation = _conversations[index];
        final myId = ref.read(authControllerProvider).user?['id'] as String?;
        final meta = conversationMeta(conversation, currentUserId: myId);
        final messages = (conversation['messages'] as List? ?? []).cast<Map>();
        messages.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
        final last = messages.isEmpty ? null : messages.first;
        final preview = conversationPreview(last, currentUserId: myId);
        final timestamp = shortDate(last?['created_at'] ?? conversation['last_message_at']);
        final unreadCount = (conversation['unread_count'] as int?) ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ExchangeCard(
            padding: const EdgeInsets.all(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ChatScreen(conversation: conversation)),
              ).then((_) {
                // Reset unread badge immediately then do a silent refresh
                setState(() {
                  final i = _conversations.indexWhere((c) => '${c['id']}' == '${conversation['id']}');
                  if (i != -1) {
                    _conversations[i] = Map<String, dynamic>.from(_conversations[i])
                      ..['unread_count'] = 0;
                  }
                });
                _load(silent: true);
              }),
              child: Row(
                children: [
                  AssetAvatar(
                    label: meta.title,
                    imageUrl: meta.avatarUrl,
                    color: index.isEven ? AppTheme.primary : AppTheme.accent,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          meta.title,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.muted),
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
                        style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      if (unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryBright,
                            borderRadius: BorderRadius.all(Radius.circular(999)),
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
                        const Icon(Icons.chevron_right_rounded, color: AppTheme.muted, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
