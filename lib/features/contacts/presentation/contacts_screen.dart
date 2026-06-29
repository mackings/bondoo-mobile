import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../chats/data/chat_repository.dart';
import '../../chats/presentation/chat_screen.dart';
import '../data/contacts_repository.dart';

const _inviteLink = 'https://bondoo.ng/';

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
      final result = await ref.read(contactsRepositoryProvider).syncContacts();
      if (!mounted) return;
      setState(() {
        _contacts = result;
        _loading = false;
        _permissionDenied = result.isEmpty;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showApiError(context, error);
    }
  }

  Future<void> _openChat(Map<String, dynamic> user) async {
    try {
      final convId = await ref.read(chatRepositoryProvider).openDirect('${user['id']}');
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

  Future<void> _inviteBySms(BondooContact contact) async {
    final msg = Uri.encodeComponent(
      "Hey ${contact.name.split(' ').first}! I'm using Bondoo to chat and trade crypto P2P with contacts. "
      "Join me here: $_inviteLink",
    );

    // Try SMS deep-link first (pre-fills recipient + message)
    final smsUri = Uri.parse('sms:${contact.phone}?body=$msg');
    if (await canLaunchUrl(smsUri)) {
      await launchUrl(smsUri);
      return;
    }
    // Fallback: plain sms scheme without recipient (some Android versions)
    final fallback = Uri.parse('sms:?body=$msg');
    if (await canLaunchUrl(fallback)) {
      await launchUrl(fallback);
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final onApp   = (_contacts ?? []).where((c) => c.isOnApp).toList();
    final invite  = (_contacts ?? []).where((c) => !c.isOnApp).toList();

    return ExchangeScaffold(
      title: 'Contacts',
      actions: [
        IconButton(
          tooltip: 'Refresh',
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
          Expanded(child: _buildBody(onApp, invite)),
        ],
      ),
    );
  }

  Widget _buildBody(List<BondooContact> onApp, List<BondooContact> invite) {
    // Permission denied or no contacts at all
    if (!_loading && _permissionDenied) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts_rounded, size: 56, color: AppTheme.muted),
            const SizedBox(height: 16),
            const Text(
              'Allow contacts access',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.muted),
            ),
            const SizedBox(height: 6),
            const Text(
              'Bondoo needs your contacts to show\nwhich friends are on the app.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sync,
              icon: const Icon(Icons.contacts_rounded),
              label: const Text('Allow Contacts'),
            ),
          ],
        ),
      );
    }

    if (_contacts == null && !_loading) {
      return const EmptyState(
        icon: Icons.contacts_rounded,
        title: 'Find your contacts',
        message: 'Tap refresh to sync your contacts.',
      );
    }

    return CustomScrollView(
      slivers: [
        // ── On Bondoo ──────────────────────────────────────────────────────
        if (onApp.isNotEmpty) ...[
          _SectionHeader(title: 'ON BONDOO  •  ${onApp.length}'),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final contact = onApp[i];
                final user    = contact.user!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExchangeCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      leading: AssetAvatar(
                        label: _initials(contact.name),
                        imageUrl: '${user['avatar_url'] ?? ''}',
                        color: i.isEven ? AppTheme.primary : AppTheme.accent,
                      ),
                      title: Text(
                        '${user['display_name'] ?? contact.name}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '@${user['username'] ?? ''}  ·  ${contact.phone}',
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      trailing: FilledButton.tonal(
                        onPressed: () => _openChat(user),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(0, 34),
                        ),
                        child: const Text('Chat'),
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

        // ── Invite friends ─────────────────────────────────────────────────
        if (invite.isNotEmpty) ...[
          _SectionHeader(title: 'INVITE TO BONDOO  •  ${invite.length}'),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final contact = invite[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ExchangeCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                      trailing: OutlinedButton(
                        onPressed: () => _inviteBySms(contact),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(0, 34),
                        ),
                        child: const Text('Invite'),
                      ),
                      onTap: () => _inviteBySms(contact),
                    ),
                  ),
                );
              },
              childCount: invite.length,
            ),
          ),
        ],

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTheme.muted,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}
