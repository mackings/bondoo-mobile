import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../chats/data/chat_repository.dart';
import '../../chats/presentation/chat_screen.dart';
import '../data/story_repository.dart';


class StoryViewer extends ConsumerStatefulWidget {
  const StoryViewer({super.key, required this.story, this.isOwnStory = false});
  final Map<String, dynamic> story;
  final bool isOwnStory;

  @override
  ConsumerState<StoryViewer> createState() => _StoryViewerState();
}

class _StoryViewerState extends ConsumerState<StoryViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  bool _viewMarked = false;
  bool _loadingReply = false;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..forward();
    _progress.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) Navigator.pop(context);
    });
    _maybeMarkViewed();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _maybeMarkViewed() async {
    if (_viewMarked) return;
    _viewMarked = true;
    try {
      await ref
          .read(storyRepositoryProvider)
          .markViewed('${widget.story['id']}');
    } catch (_) {}
  }

  Future<void> _reply() async {
    final myId = ref.read(authControllerProvider).user?['id'];
    final posterId = '${widget.story['user_id']}';
    if (posterId.isEmpty || posterId == myId) return;
    setState(() => _loadingReply = true);
    _progress.stop();
    try {
      final conversationId =
          await ref.read(chatRepositoryProvider).openDirect(posterId);
      if (!mounted) return;
      final poster = widget.story['user'] as Map<String, dynamic>?;
      final conversation = {
        'id': conversationId,
        'is_group': false,
        'name': null,
        'last_message_at': null,
        'unread_count': 0,
        'messages': [],
        'conversation_members': [
          {'user_id': posterId, 'profiles': poster},
          {
            'user_id': myId,
            'profiles': ref.read(authControllerProvider).user
          },
        ],
      };
      // Build a pre-filled caption so the replier's message references the story
      final storyText = widget.story['text'] as String?;
      final hasImage = widget.story['image_data_url'] != null;
      final posterName = (widget.story['user'] as Map?)?['display_name']
          ?? (widget.story['user'] as Map?)?['username']
          ?? 'their';
      final caption = [
        if (hasImage) '📷',
        if (storyText != null && storyText.isNotEmpty) '"$storyText"',
      ].join(' ');
      final initialText = caption.isNotEmpty
          ? 'Replying to $posterName\'s story: $caption\n\n'
          : 'Replying to $posterName\'s story\n\n';

      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversation: conversation,
            initialText: initialText,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _progress.forward();
        showApiError(context, e);
        setState(() => _loadingReply = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final user = story['user'] as Map<String, dynamic>?;
    final name =
        '${user?['display_name'] ?? user?['username'] ?? 'Trader'}';
    final avatarUrl = '${user?['avatar_url'] ?? ''}';
    final imageDataUrl = story['image_data_url'] as String?;
    final text = story['text'] as String?;
    final viewCount = story['view_count'] as int? ?? 0;

    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Background image ─────────────────────────────────────
            if (imageDataUrl != null)
              _StoryImage(dataUrl: imageDataUrl)
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),

            // ── Bottom gradient scrim ────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 220,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black87],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),

            // ── Top bar: progress + close ────────────────────────────
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 12,
              right: 12,
              child: Column(
                children: [
                  // Progress bar
                  AnimatedBuilder(
                    animation: _progress,
                    builder: (_, _) => LinearProgressIndicator(
                      value: _progress.value,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Poster info row
                  Row(
                    children: [
                      AssetAvatar(
                          label: name, imageUrl: avatarUrl, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14),
                            ),
                            Text(
                              '${viewCount > 0 ? '$viewCount view${viewCount == 1 ? '' : 's'} · ' : ''}just now',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 24),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Caption text ─────────────────────────────────────────
            if (text != null)
              Positioned(
                left: 20,
                right: 20,
                bottom: 96,
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      Shadow(color: Colors.black54, blurRadius: 8),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            // ── Bottom action button ──────────────────────────────────
            Positioned(
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 24,
              child: widget.isOwnStory
                  ? FilledButton.icon(
                      onPressed: () {
                        _progress.stop();
                        showModalBottomSheet<String>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Theme.of(context).colorScheme.surface,
                          shape: const RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.vertical(top: Radius.circular(20)),
                          ),
                          builder: (_) => const MyStoryViewersSheet(),
                        ).then((result) {
                          if (result == 'deleted' && context.mounted) {
                            Navigator.pop(context);
                          } else if (mounted) {
                            _progress.forward();
                          }
                        });
                      },
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(
                        viewCount == 0
                            ? 'No views yet'
                            : '$viewCount view${viewCount == 1 ? '' : 's'}',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white24,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _loadingReply ? null : _reply,
                      icon: _loadingReply
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.reply_rounded),
                      label: const Text('Reply in DM'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryImage extends StatelessWidget {
  const _StoryImage({required this.dataUrl});
  final String dataUrl;

  @override
  Widget build(BuildContext context) {
    try {
      final comma = dataUrl.indexOf(',');
      if (comma < 0) return const SizedBox.shrink();
      final bytes = base64Decode(dataUrl.substring(comma + 1));
      return Image.memory(bytes, fit: BoxFit.cover);
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}

// ── My story viewers sheet ─────────────────────────────────────────────────

class MyStoryViewersSheet extends ConsumerStatefulWidget {
  const MyStoryViewersSheet({super.key});

  @override
  ConsumerState<MyStoryViewersSheet> createState() =>
      _MyStoryViewersSheetState();
}

class _MyStoryViewersSheetState extends ConsumerState<MyStoryViewersSheet> {
  Map<String, dynamic>? _story;
  bool _loading = true;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await ref.read(storyRepositoryProvider).getMyStory();
      if (mounted) setState(() { _story = s; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _deleting = true);
    try {
      await ref.read(storyRepositoryProvider).deleteMyStory();
      if (mounted) Navigator.pop(context, 'deleted');
    } catch (e) {
      if (mounted) {
        showApiError(context, e);
        setState(() => _deleting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewers =
        (_story?['viewers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('My Story',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18)),
                const Spacer(),
                if (_story != null)
                  TextButton.icon(
                    onPressed: _deleting ? null : _delete,
                    icon: _deleting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.danger),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _story == null
                    ? const Center(
                        child: Text('No active story',
                            style: TextStyle(color: AppTheme.muted)))
                    : viewers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.visibility_off_outlined,
                                    color: AppTheme.muted, size: 36),
                                const SizedBox(height: 8),
                                Text(
                                  'No views yet',
                                  style: const TextStyle(
                                      color: AppTheme.muted,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: viewers.length,
                            itemBuilder: (_, i) {
                              final v = viewers[i];
                              final u = v['user'] as Map<String, dynamic>?;
                              final uName =
                                  '${u?['display_name'] ?? u?['username'] ?? 'User'}';
                              final avatarUrl = '${u?['avatar_url'] ?? ''}';
                              return ListTile(
                                leading: AssetAvatar(
                                    label: uName,
                                    imageUrl: avatarUrl,
                                    size: 40),
                                title: Text(uName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                  '@${u?['username'] ?? ''}',
                                  style: const TextStyle(
                                      color: AppTheme.muted, fontSize: 12),
                                ),
                                trailing: const Icon(
                                    Icons.visibility_outlined,
                                    color: AppTheme.muted,
                                    size: 18),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
