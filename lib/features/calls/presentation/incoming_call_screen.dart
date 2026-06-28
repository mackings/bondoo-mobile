import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../data/call_repository.dart';
import 'agora_call_screen.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  const IncomingCallScreen({super.key, required this.call});

  final Map<String, dynamic> call;

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen> {
  final AudioPlayer _ringer = AudioPlayer();
  bool _busy = false;

  String get callId => '${widget.call['id']}';
  bool get isVideo => widget.call['kind'] == 'video';

  Map? get _caller => widget.call['caller'] as Map?;
  String get _callerName =>
      '${_caller?['display_name'] ?? _caller?['username'] ?? 'Trader'}';
  String get _callerAvatar => '${_caller?['avatar_url'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _startRinging();
  }

  @override
  void dispose() {
    _ringer.stop();
    _ringer.dispose();
    super.dispose();
  }

  Future<void> _startRinging() async {
    try {
      await _ringer.setReleaseMode(ReleaseMode.loop);
      await _ringer.play(BytesSource(CallRingWav.ringTone()));
    } catch (_) {}
  }

  Future<void> accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _ringer.stop();
    try {
      final response = await ref.read(callRepositoryProvider).accept(callId);
      final agora = response['agora'] as Map<String, dynamic>;
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AgoraCallScreen(
            channelName: '${agora['channel_name']}',
            isVideoCall: isVideo,
            token: '${agora['token']}',
            uid: agora['uid'] as int? ?? 0,
            callId: callId,
            peerName: _callerName,
            peerAvatarUrl: _callerAvatar,
            onEnd: () => ref.read(callRepositoryProvider).end(callId),
          ),
        ),
      );
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _ringer.stop();
    try {
      await ref.read(callRepositoryProvider).decline(callId);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showApiError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              AssetAvatar(
                label: _callerName,
                imageUrl: _callerAvatar,
                size: 112,
              ),
              const SizedBox(height: 24),
              Text(
                _callerName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Incoming ${isVideo ? 'video' : 'voice'} call',
                style: const TextStyle(color: AppTheme.muted),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: _busy ? null : decline,
                      icon: const Icon(Icons.call_end_rounded),
                      label: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: _busy ? null : accept,
                      icon: Icon(
                        isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      ),
                      label: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
