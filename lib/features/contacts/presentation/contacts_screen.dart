import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../chats/data/chat_repository.dart';
import '../../chats/presentation/chat_screen.dart';
import '../data/contacts_repository.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  List<BondooContact>? _contacts;
  bool _loading = false;
  bool _permissionDenied = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  Future<void> _sync() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    try {
      final result =
          await ref.read(contactsRepositoryProvider).syncContacts();
      if (!mounted) return;
      // If the result is empty and no permission was granted, treat it as denied.
      // The repository returns [] on denial; we can't distinguish here without
      // re-checking, so we show the list (even empty) — user can resync.
      setState(() {
        _contacts = result;
        _loading = false;
        // Treat empty-on-first-load as possible permission denial.
        _permissionDenied = result.isEmpty && _contacts == null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, error);
    }
  }

  String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  Future<void> _openChat(Map<String, dynamic> user) async {
    final userId = '${user['id']}';
    try {
      final convId =
          await ref.read(chatRepositoryProvider).openDirect(userId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversation: {
              'id': convId,
              'is_group': false,
              'conversation_members': [
                {'user_id': user['id'], 'profiles': user},
              ],
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) showApiError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onApp = (_contacts ?? []).where((c) => c.isOnApp).toList();
    final invite = (_contacts ?? []).where((c) => !c.isOnApp).toList();

    return ExchangeScaffold(
      title: 'Contacts',
      actions: [
        IconButton(
          tooltip: 'Resync contacts',
          icon: const Icon(Icons.refresh_rounded),
          onPressed: _loading ? null : _sync,
        ),
      ],
      body: Column(
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          Expanded(
            child: _buildBody(onApp, invite),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
      List<BondooContact> onApp, List<BondooContact> invite) {
    if (!_loading && _permissionDenied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts_rounded,
                size: 56, color: AppTheme.muted),
            const SizedBox(height: 16),
            const Text(
              'Contacts permission required',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.muted),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sync,
              icon: const Icon(Icons.contacts_rounded),
              label: const Text('Allow Contacts'),
            ),
          ],
        ),
      );
    }

    if (!_loading && _contacts != null && _contacts!.isEmpty) {
      return const EmptyState(
        icon: Icons.contacts_rounded,
        title: 'No contacts found',
        message:
            'We could not find any contacts. Make sure you have contacts saved on your device.',
      );
    }

    if (_contacts == null && !_loading) {
      return const EmptyState(
        icon: Icons.contacts_rounded,
        title: 'Find your contacts',
        message: 'Tap the refresh icon to sync your contacts.',
      );
    }

    return CustomScrollView(
      slivers: [
        if (onApp.isNotEmpty) ...[
          _SectionHeader(title: 'On Bondoo (${onApp.length})'),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final contact = onApp[index];
                final user = contact.user!;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
                  child: ExchangeCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      leading: AssetAvatar(
                        label: _initials(contact.name),
                        imageUrl: '${user['avatar_url'] ?? ''}',
                        color: index.isEven
                            ? AppTheme.primary
                            : AppTheme.accent,
                      ),
                      title: Text(
                        '${user['display_name'] ?? contact.name}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '@${user['username'] ?? ''}',
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                      trailing: IconButton(
                        tooltip: 'Chat',
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppTheme.primaryBright,
                        ),
                        onPressed: () => _openChat(user),
                      ),
                      onTap: () => _openChat(user),
                    ),
                  ),
                );
              },
              childCount: onApp.length,
            ),
          ),
        ],
        if (invite.isNotEmpty) ...[
          _SectionHeader(title: 'Invite friends (${invite.length})'),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final contact = invite[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: ExchangeCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.surface,
                        child: Text(
                          _initials(contact.name),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryBright,
                          ),
                        ),
                      ),
                      title: Text(
                        contact.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        contact.phone,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                      trailing: OutlinedButton(
                        onPressed: () => Share.share(
                          'Hey! Join me on Bondoo for P2P crypto trading. Download: https://bondoo.app',
                        ),
                        child: const Text('Invite'),
                      ),
                    ),
                  ),
                );
              },
              childCount: invite.length,
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
