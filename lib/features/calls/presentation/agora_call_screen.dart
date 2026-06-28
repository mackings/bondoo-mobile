import 'dart:async';
import 'dart:math' as math;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/call_repository.dart';

class AgoraCallScreen extends ConsumerStatefulWidget {
  const AgoraCallScreen({
    super.key,
    required this.channelName,
    required this.isVideoCall,
    required this.token,
    required this.uid,
    this.callId,
    this.peerName,
    this.peerAvatarUrl,
    this.onEnd,
  });

  final String channelName;
  final bool isVideoCall;
  final String token;
  final int uid;
  final String? callId;
  final String? peerName;
  final String? peerAvatarUrl;
  final Future<void> Function()? onEnd;

  @override
  ConsumerState<AgoraCallScreen> createState() => _AgoraCallScreenState();
}

class _AgoraCallScreenState extends ConsumerState<AgoraCallScreen> {
  late final RtcEngine _engine;
  late final RtcEngineEventHandler _eventHandler;
  Timer? _callStatusTimer;
  Timer? _durationTimer;
  final Set<int> _remoteUids = {};
  bool _engineCreated = false;
  bool _eventHandlerRegistered = false;
  bool _engineReady = false;
  bool _joined = false;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = true;
  bool _leaving = false;
  bool _remoteEnded = false;
  bool _permissionDenied = false;
  String? _errorMessage;
  String? _agoraSetupStep;
  int _durationSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initAgora();
    if (widget.callId != null) {
      _callStatusTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollCallStatus(),
      );
    }
  }

  @override
  void dispose() {
    _callStatusTimer?.cancel();
    _durationTimer?.cancel();
    unawaited(_disposeAgora());
    super.dispose();
  }

  // ─── Polling ───────────────────────────────────────────────────────────────

  Future<void> _pollCallStatus() async {
    final callId = widget.callId;
    if (callId == null || _leaving || _remoteEnded || !mounted) return;
    try {
      final call = await ref.read(callRepositoryProvider).getCall(callId);
      final status = '${call['status'] ?? ''}';
      if (['ended', 'declined', 'missed'].contains(status)) {
        await _closeBecauseRemoteEnded();
      }
    } catch (_) {}
  }

  // ─── Agora init ────────────────────────────────────────────────────────────

  Future<void> _initAgora() async {
    try {
      final appId = AppConfig.agoraAppId.trim();
      final channelName = widget.channelName.trim();
      if (appId.isEmpty) {
        throw const FormatException(
          'Agora App ID is missing. Build with --dart-define=AGORA_APP_ID=...',
        );
      }
      if (channelName.isEmpty || channelName.length > 64) {
        throw FormatException('Invalid Agora channel name: "$channelName".');
      }

      // ── Permissions ────────────────────────────────────────────────────────
      final permissions = widget.isVideoCall
          ? [Permission.microphone, Permission.camera]
          : [Permission.microphone];
      if (defaultTargetPlatform == TargetPlatform.android) {
        permissions.add(Permission.bluetoothConnect);
      }
      final statuses = await permissions.request();
      final denied = statuses.values.any((s) => !s.isGranted);
      if (denied) {
        if (mounted) {
          setState(() {
            _permissionDenied = true;
            _errorMessage = widget.isVideoCall
                ? 'Allow camera and microphone access to start a video call.'
                : 'Allow microphone access to start a voice call.';
          });
        }
        return;
      }

      // ── Create & initialise engine ─────────────────────────────────────────
      _agoraSetupStep = 'create engine';
      _engine = createAgoraRtcEngine();
      _engineCreated = true;

      _agoraSetupStep = 'initialize engine';
      await _engine.initialize(
        RtcEngineContext(
          appId: appId,
          // Communication profile — every user is a broadcaster by default.
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // ── Event handler ──────────────────────────────────────────────────────
      _eventHandler = RtcEngineEventHandler(
        onError: (err, msg) {
          if (mounted) setState(() => _errorMessage = 'Call error: $msg ($err)');
        },
        onJoinChannelSuccess: (connection, elapsed) {
          if (!mounted) return;
          setState(() => _joined = true);
          _durationTimer = Timer.periodic(
            const Duration(seconds: 1),
            (_) { if (mounted) setState(() => _durationSeconds++); },
          );
          // Ensure audio is unmuted and speaker is on after join confirmation.
          unawaited(_postJoinAudioSetup());
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          if (mounted) setState(() => _remoteUids.add(remoteUid));
        },
        onUserOffline: (connection, remoteUid, reason) {
          if (mounted) setState(() => _remoteUids.remove(remoteUid));
        },
        onLeaveChannel: (connection, stats) {
          if (mounted) {
            setState(() {
              _joined = false;
              _remoteUids.clear();
            });
          }
        },
      );
      _agoraSetupStep = 'register events';
      _engine.registerEventHandler(_eventHandler);
      _eventHandlerRegistered = true;

      // ── Audio setup — matches Agora v6 recommended order ─────────────────
      // 1. Enable the audio module first (docs: enableAudio → setAudioProfile).
      _agoraSetupStep = 'enable audio';
      await _engine.enableAudio();

      // 2. Configure quality profile after enabling.
      _agoraSetupStep = 'set audio profile';
      await _engine.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioChatroom,
      );

      // 3. Route to loudspeaker before joining (default for calls).
      _agoraSetupStep = 'set speaker route';
      await _trySetDefaultSpeakerphone(true);

      // ── Video setup ────────────────────────────────────────────────────────
      if (widget.isVideoCall) {
        _agoraSetupStep = 'enable video';
        await _engine.enableVideo();
        _agoraSetupStep = 'start camera preview';
        await _engine.startPreview();
      }

      // ── Join channel ───────────────────────────────────────────────────────
      _agoraSetupStep = 'join channel';
      final resolvedToken = widget.token.trim().isEmpty
          ? AppConfig.agoraToken.trim()
          : widget.token.trim();
      await _engine.joinChannel(
        token: resolvedToken,
        channelId: channelName,
        uid: widget.uid,
        options: ChannelMediaOptions(
          // Do NOT set channelProfile here — it conflicts with RtcEngineContext.
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          // enableAudioRecordingOrPlayout MUST be true or the SDK silently
          // disables both the microphone capture and the speaker output (v6+).
          enableAudioRecordingOrPlayout: true,
          publishMicrophoneTrack: true,
          publishCameraTrack: widget.isVideoCall,
          autoSubscribeAudio: true,
          autoSubscribeVideo: widget.isVideoCall,
        ),
      );

      _agoraSetupStep = null;
      if (mounted) setState(() => _engineReady = true);
    } catch (error) {
      final setupStep = _agoraSetupStep;
      _agoraSetupStep = null;
      await _disposeAgora();
      if (mounted) {
        setState(() => _errorMessage = _formatAgoraError(error, setupStep));
      }
    }
  }

  // Called from onJoinChannelSuccess — guarantees audio is flowing.
  Future<void> _postJoinAudioSetup() async {
    if (!_engineCreated) return;
    try {
      // Explicitly unmute so the mic publishes.
      await _engine.muteLocalAudioStream(false);
      // Explicitly subscribe to remote audio.
      await _engine.muteAllRemoteAudioStreams(false);
      if (widget.isVideoCall) {
        await _engine.muteAllRemoteVideoStreams(false);
      }
    } catch (_) {}
    // Some Android devices only accept speaker routing after a short delay.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!_engineCreated) return;
    try {
      await _engine.setEnableSpeakerphone(true);
    } catch (_) {}
  }

  Future<void> _disposeAgora() async {
    if (!_engineCreated) return;
    if (_eventHandlerRegistered) {
      _engine.unregisterEventHandler(_eventHandler);
      _eventHandlerRegistered = false;
    }
    if (_joined) {
      try { await _engine.leaveChannel(); } catch (_) {}
    }
    try { await _engine.release(); } catch (_) {}
    _engineCreated = false;
    _engineReady = false;
    _joined = false;
    _remoteUids.clear();
  }

  // ─── Controls ──────────────────────────────────────────────────────────────

  Future<void> _toggleMute() async {
    if (!_engineCreated) return;
    try {
      await _engine.muteLocalAudioStream(!_muted);
      if (mounted) setState(() => _muted = !_muted);
    } catch (e) {
      if (mounted) _showSnack('Could not toggle mute.');
    }
  }

  Future<void> _toggleCamera() async {
    if (!_engineCreated || !widget.isVideoCall) return;
    try {
      // enableLocalVideo(true) restores; (false) pauses.
      await _engine.enableLocalVideo(_cameraOff);
      if (mounted) setState(() => _cameraOff = !_cameraOff);
    } catch (e) {
      if (mounted) _showSnack('Could not toggle camera.');
    }
  }

  Future<void> _toggleSpeaker() async {
    if (!_engineCreated) return;
    try {
      await _engine.setEnableSpeakerphone(!_speakerOn);
      if (mounted) setState(() => _speakerOn = !_speakerOn);
    } catch (e) {
      if (mounted) _showSnack('Could not switch audio route.');
    }
  }

  Future<void> _switchCamera() async {
    if (!_engineCreated || !widget.isVideoCall) return;
    try {
      await _engine.switchCamera();
    } catch (_) {}
  }

  Future<void> _trySetDefaultSpeakerphone(bool on) async {
    try {
      await _engine.setDefaultAudioRouteToSpeakerphone(on);
    } catch (_) {}
  }

  Future<void> _retryPermissions() async {
    setState(() { _permissionDenied = false; _errorMessage = null; });
    await _initAgora();
  }

  Future<void> _leaveCall() async {
    if (_leaving) return;
    _leaving = true;
    _callStatusTimer?.cancel();
    _durationTimer?.cancel();
    if (_engineCreated && _joined) {
      try { await _engine.leaveChannel(); } catch (_) {}
      _joined = false;
    }
    try { await widget.onEnd?.call(); } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  Future<void> _closeBecauseRemoteEnded() async {
    if (_remoteEnded || _leaving) return;
    _remoteEnded = true;
    _callStatusTimer?.cancel();
    _durationTimer?.cancel();
    await _disposeAgora();
    if (mounted) Navigator.pop(context);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  String _formatAgoraError(Object error, String? setupStep) {
    final step = setupStep == null ? '' : ' during "$setupStep"';
    if (error is AgoraRtcException) {
      return switch (error.code) {
        -3 => 'Agora engine could not start$step. Use a 64-bit device and verify the App ID.',
        -2 => 'Bad call parameters$step. Check token, channel and user ID.',
        -102 => 'Invalid channel name$step.',
        -121 => 'Invalid user ID$step.',
        101 || -101 => 'Invalid Agora App ID$step.',
        109 || -109 => 'Agora token expired$step.',
        110 || -110 => 'Invalid Agora token$step.',
        _ => 'Agora error$step: ${error.code}',
      };
    }
    return '$error';
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leaveCall());
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _leaveCall,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.peerName ?? (widget.isVideoCall ? 'Video call' : 'Voice call'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.text,
                            ),
                          ),
                          if (_joined)
                            Text(
                              _formatDuration(_durationSeconds),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.muted,
                              ),
                            )
                          else
                            Text(
                              widget.isVideoCall ? 'Video call' : 'Voice call',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Call body ─────────────────────────────────────────────────
              Expanded(child: _buildCallBody()),

              // ── Controls ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ControlBtn(
                      tooltip: _muted ? 'Unmute' : 'Mute',
                      icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                      active: _muted,
                      onPressed: _engineCreated ? _toggleMute : null,
                    ),
                    if (widget.isVideoCall) ...[
                      _ControlBtn(
                        tooltip: _cameraOff ? 'Camera on' : 'Camera off',
                        icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                        active: _cameraOff,
                        onPressed: _engineCreated ? _toggleCamera : null,
                      ),
                      _ControlBtn(
                        tooltip: 'Switch camera',
                        icon: Icons.cameraswitch_rounded,
                        onPressed: _engineCreated ? _switchCamera : null,
                      ),
                    ],
                    _ControlBtn(
                      tooltip: _speakerOn ? 'Speaker on' : 'Earpiece',
                      icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      active: !_speakerOn,
                      onPressed: _engineCreated ? _toggleSpeaker : null,
                    ),
                    _ControlBtn(
                      tooltip: 'End call',
                      icon: Icons.call_end_rounded,
                      danger: true,
                      onPressed: _leaveCall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCallBody() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.danger, fontSize: 15),
              ),
              if (_permissionDenied) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings_rounded),
                  label: const Text('Open settings'),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _retryPermissions,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!_engineReady && !_joined) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!widget.isVideoCall) {
      return _VoiceCallBody(
        peerName: widget.peerName,
        peerAvatarUrl: widget.peerAvatarUrl,
        joined: _joined,
        durationSeconds: _durationSeconds,
      );
    }

    // ── Video layout ─────────────────────────────────────────────────────────
    return Stack(
      children: [
        Positioned.fill(child: _buildRemoteVideo()),
        Positioned(
          right: 18,
          top: 18,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 110,
              height: 150,
              color: AppTheme.elevated,
              child: _cameraOff
                  ? const Icon(Icons.videocam_off_rounded, color: AppTheme.muted)
                  : AgoraVideoView(
                      controller: VideoViewController(
                        rtcEngine: _engine,
                        canvas: const VideoCanvas(
                          uid: 0,
                          renderMode: RenderModeType.renderModeFit,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteVideo() {
    if (_remoteUids.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PeerAvatar(name: widget.peerName, avatarUrl: widget.peerAvatarUrl, size: 96),
            const SizedBox(height: 20),
            Text(
              widget.peerName ?? 'Trader',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('Waiting for video…', style: TextStyle(color: AppTheme.muted)),
          ],
        ),
      );
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine,
        canvas: VideoCanvas(
          uid: _remoteUids.first,
          renderMode: RenderModeType.renderModeFit,
        ),
        connection: RtcConnection(channelId: widget.channelName.trim()),
      ),
    );
  }
}

// ─── Voice call body ──────────────────────────────────────────────────────────

class _VoiceCallBody extends StatelessWidget {
  const _VoiceCallBody({
    this.peerName,
    this.peerAvatarUrl,
    required this.joined,
    required this.durationSeconds,
  });

  final String? peerName;
  final String? peerAvatarUrl;
  final bool joined;
  final int durationSeconds;

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PeerAvatar(name: peerName, avatarUrl: peerAvatarUrl, size: 112),
          const SizedBox(height: 20),
          Text(
            peerName ?? 'Trader',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            joined ? _fmt(durationSeconds) : 'Connecting…',
            style: const TextStyle(color: AppTheme.muted, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

// ─── Peer avatar ──────────────────────────────────────────────────────────────

class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({this.name, this.avatarUrl, this.size = 80});

  final String? name;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl ?? '';
    if (url.startsWith('http')) {
      return CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(url),
        backgroundColor: AppTheme.elevated,
        child: null,
      );
    }
    final initials = (name ?? '?').trim().isEmpty
        ? '?'
        : (name!).trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppTheme.brandGradient,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ─── Control button ───────────────────────────────────────────────────────────

class _ControlBtn extends StatelessWidget {
  const _ControlBtn({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? AppTheme.danger
        : active
            ? AppTheme.elevated
            : AppTheme.surface;
    final fg = danger ? Colors.white : AppTheme.text;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      color: fg,
      style: IconButton.styleFrom(
        backgroundColor: bg,
        disabledBackgroundColor: AppTheme.elevated.withValues(alpha: 0.4),
        disabledForegroundColor: AppTheme.muted,
        fixedSize: const Size(56, 56),
        shape: const CircleBorder(),
      ),
    );
  }
}

// ─── WAV tone generator (no external assets needed) ───────────────────────────

class CallRingWav {
  static Uint8List ringTone() => _build(
        segments: [
          (freq: 880.0, durationMs: 400),
          (freq: 0.0, durationMs: 150),
          (freq: 880.0, durationMs: 400),
          (freq: 0.0, durationMs: 1800),
        ],
      );

  static Uint8List ringbackTone() => _build(
        segments: [
          (freq: 440.0, durationMs: 1000),
          (freq: 0.0, durationMs: 3000),
        ],
      );

  static Uint8List _build({
    required List<({double freq, int durationMs})> segments,
  }) {
    const sampleRate = 22050;
    final segmentSamples = segments
        .map((s) => (sampleRate * s.durationMs / 1000.0).round())
        .toList();
    final total = segmentSamples.fold(0, (a, b) => a + b);
    final buf = ByteData(44 + total * 2);

    // WAV RIFF header
    void ws(int offset, int byte) => buf.setUint8(offset, byte);
    ws(0, 0x52); ws(1, 0x49); ws(2, 0x46); ws(3, 0x46); // "RIFF"
    buf.setUint32(4, 36 + total * 2, Endian.little);
    ws(8, 0x57); ws(9, 0x41); ws(10, 0x56); ws(11, 0x45); // "WAVE"
    ws(12, 0x66); ws(13, 0x6D); ws(14, 0x74); ws(15, 0x20); // "fmt "
    buf.setUint32(16, 16, Endian.little);
    buf.setUint16(20, 1, Endian.little); // PCM
    buf.setUint16(22, 1, Endian.little); // mono
    buf.setUint32(24, sampleRate, Endian.little);
    buf.setUint32(28, sampleRate * 2, Endian.little);
    buf.setUint16(32, 2, Endian.little);
    buf.setUint16(34, 16, Endian.little);
    ws(36, 0x64); ws(37, 0x61); ws(38, 0x74); ws(39, 0x61); // "data"
    buf.setUint32(40, total * 2, Endian.little);

    int pos = 44;
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final n = segmentSamples[i];
      for (var j = 0; j < n; j++) {
        int pcm = 0;
        if (seg.freq > 0) {
          final t = j / sampleRate;
          final env = j < n * 0.05
              ? j / (n * 0.05)
              : j > n * 0.95
                  ? (n - j) / (n * 0.05)
                  : 1.0;
          pcm = (math.sin(2 * math.pi * seg.freq * t) * 26000 * env)
              .round()
              .clamp(-32768, 32767);
        }
        buf.setInt16(pos, pcm, Endian.little);
        pos += 2;
      }
    }
    return buf.buffer.asUint8List();
  }
}
