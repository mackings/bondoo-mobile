import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../data/call_repository.dart';
import 'agora_call_screen.dart';

class OutgoingCallScreen extends ConsumerStatefulWidget {
  const OutgoingCallScreen({
    super.key,
    required this.call,
    required this.agora,
  });

  final Map<String, dynamic> call;
  final Map<String, dynamic> agora;

  @override
  ConsumerState<OutgoingCallScreen> createState() => _OutgoingCallScreenState();
}

class _OutgoingCallScreenState extends ConsumerState<OutgoingCallScreen> {
  Timer? _pollTimer;
  final AudioPlayer _ringback = AudioPlayer();
  bool _openingCall = false;
  String _status = 'ringing';

  String get callId => '${widget.call['id']}';
  bool get isVideo => widget.call['kind'] == 'video';

  Map? get _receiver => widget.call['receiver'] as Map?;
  String get _peerName => '${_receiver?['display_name'] ?? _receiver?['username'] ?? 'Trader'}';
  String get _peerAvatar => '${_receiver?['avatar_url'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _status = '${widget.call['status'] ?? 'ringing'}';
    _startRingback();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    unawaited(_poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ringback.stop();
    _ringback.dispose();
    super.dispose();
  }

  Future<void> _startRingback() async {
    try {
      await _ringback.setReleaseMode(ReleaseMode.loop);
      await _ringback.play(BytesSource(CallRingWav.ringbackTone()));
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_openingCall || !mounted) return;
    try {
      final call = await ref.read(callRepositoryProvider).getCall(callId);
      final next = '${call['status'] ?? _status}';
      if (!mounted) return;
      setState(() => _status = next);
      if (next == 'accepted') {
        await _openAgora();
      } else if (['declined', 'missed', 'ended'].contains(next)) {
        _pollTimer?.cancel();
        await _ringback.stop();
      }
    } catch (_) {}
  }

  Future<void> _openAgora() async {
    if (_openingCall || !mounted) return;
    _openingCall = true;
    _pollTimer?.cancel();
    // Capture navigator before any async gap to satisfy the linter.
    final nav = Navigator.of(context);
    await _ringback.stop();
    await nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => AgoraCallScreen(
          channelName: '${widget.agora['channel_name']}',
          isVideoCall: isVideo,
          token: '${widget.agora['token']}',
          uid: widget.agora['uid'] as int? ?? 0,
          callId: callId,
          peerName: _peerName,
          peerAvatarUrl: _peerAvatar,
          onEnd: () => ref.read(callRepositoryProvider).end(callId),
        ),
      ),
    );
  }

  Future<void> _cancelCall() async {
    _pollTimer?.cancel();
    await _ringback.stop();
    if (!mounted) return;
    // Fire end-call request in background so the screen closes immediately.
    unawaited(ref.read(callRepositoryProvider).end(callId).catchError((_) {}));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ended = ['declined', 'missed', 'ended'].contains(_status);
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
                label: _peerName,
                imageUrl: _peerAvatar,
                size: 112,
              ),
              const SizedBox(height: 24),
              Text(_peerName, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                ended
                    ? _statusLabel(_status)
                    : 'Calling ${isVideo ? 'video' : 'voice'}…',
                style: const TextStyle(color: AppTheme.muted),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  minimumSize: const Size.fromHeight(54),
                ),
                onPressed: _cancelCall,
                icon: const Icon(Icons.call_end_rounded),
                label: Text(ended ? 'Close' : 'Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String value) => switch (value) {
    'declined' => 'Call declined',
    'missed' => 'No answer',
    'ended' => 'Call ended',
    _ => 'Unavailable',
  };
}
