import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../data/call_repository.dart';

class CallHistoryScreen extends ConsumerStatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  ConsumerState<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends ConsumerState<CallHistoryScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(callRepositoryProvider).history();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Call history')),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
            _future = ref.read(callRepositoryProvider).history();
          });
        },
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snapshot) => AsyncStateView<List<dynamic>>(
            snapshot: snapshot,
            onRetry: () => setState(() {
              _future = ref.read(callRepositoryProvider).history();
            }),
            builder: (calls) {
              if (calls.isEmpty) {
                return const EmptyState(
                  icon: Icons.call_outlined,
                  title: 'No call history',
                  message: 'Your past voice and video calls will appear here.',
                );
              }
              final myId = ref.read(authControllerProvider).user?['id'] as String?;
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: calls.length,
                itemBuilder: (context, index) {
                  final call = calls[index] as Map<String, dynamic>;
                  return _CallHistoryTile(call: call, myId: myId);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  const _CallHistoryTile({required this.call, required this.myId});

  final Map<String, dynamic> call;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final isVideo = call['kind'] == 'video';
    final status = '${call['status'] ?? ''}';
    final callerId = '${call['caller_id'] ?? ''}';
    final isMyCalled = callerId == myId; // I placed this call

    final peer = isMyCalled
        ? call['receiver'] as Map?
        : call['caller'] as Map?;
    final peerName = '${peer?['display_name'] ?? peer?['username'] ?? 'Trader'}';
    final peerAvatar = '${peer?['avatar_url'] ?? ''}';

    final (IconData statusIcon, Color statusColor, String statusLabel) =
        _statusInfo(status, isMyCalled);

    final createdAt = call['created_at'] as String?;
    final timeLabel = createdAt != null ? _formatDate(createdAt) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ExchangeCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            AssetAvatar(label: peerName, imageUrl: peerAvatar, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    peerName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 18,
                  color: AppTheme.muted,
                ),
                const SizedBox(height: 6),
                Text(
                  timeLabel,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _statusInfo(String status, bool outgoing) {
    return switch (status) {
      'ended' => (
          outgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
          AppTheme.primaryBright,
          outgoing ? 'Outgoing' : 'Incoming',
        ),
      'missed' => (
          Icons.call_missed_rounded,
          AppTheme.danger,
          'Missed',
        ),
      'declined' => (
          Icons.call_end_rounded,
          AppTheme.danger,
          outgoing ? 'Declined' : 'Declined',
        ),
      _ => (Icons.call_outlined, AppTheme.muted, status),
    };
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return _time(dt);
      if (diff.inDays == 1) return 'Yesterday';
      if (diff.inDays < 7) {
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        return days[dt.weekday - 1];
      }
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return '';
    }
  }

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
