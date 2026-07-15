import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/socket_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/exchange_ui.dart';
import '../../auth/data/auth_repository.dart';
import '../../calls/data/call_repository.dart';
import '../../calls/presentation/outgoing_call_screen.dart';
import '../../offers/presentation/offer_widgets.dart';
import '../data/chat_repository.dart';
import 'chat_helpers.dart';
import 'new_chat_screen.dart';
import 'propose_trade_dialog.dart';
import 'trade_chat_card.dart';
import 'transfer_dialog.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversation});

  final Map<String, dynamic> conversation;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final text = TextEditingController();
  final recorder = AudioRecorder();
  final imagePicker = ImagePicker();
  final _scrollCtrl = ScrollController();
  final _socketSvc = SocketService();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  String? _loadError;
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  bool sending = false;
  bool transferring = false;
  bool recording = false;
  bool startingCall = false;
  int recordingMs = 0;
  Timer? recordingTimer;

  String get id => widget.conversation['id'] as String;
  ConversationMeta get meta => conversationMeta(
    widget.conversation,
    currentUserId: ref.read(authControllerProvider).user?['id'] as String?,
  );

  @override
  void initState() {
    super.initState();
    _loadMessages().then((_) { if (mounted) _initSocket(); });
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent && mounted) setState(() { _loading = true; _loadError = null; });
    try {
      final repo = ref.read(chatRepositoryProvider);
      final msgs = await repo.messages(id);
      unawaited(repo.markRead(id));
      if (mounted) {
        setState(() {
          _messages = msgs.cast<Map<String, dynamic>>();
          _loading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (!silent) _loadError = '$e';
          _loading = false;
        });
      }
    }
  }

  void _initSocket() {
    final token = ref.read(authControllerProvider).token;
    if (token == null) return;
    _socketSvc.connect(token, AppConfig.apiBaseUrl);
    _socketSvc.join(id);
    _msgSub = _socketSvc.onNewMessage
        .where((msg) => '${msg['conversation_id']}' == id)
        .listen((msg) {
      if (!mounted) return;
      // Deduplicate — the real message replaces any optimistic copy by ID
      if (_messages.any((m) => m['id'] == msg['id'])) return;
      setState(() => _messages.add(msg));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
      unawaited(ref.read(chatRepositoryProvider).markRead(id));
    });
  }

  Future<void> send() async {
    final body = text.text.trim();
    if (body.isEmpty) return;

    // Optimistic: show message immediately with a pending (clock) indicator
    final myId = ref.read(authControllerProvider).user?['id'] as String?;
    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    text.clear();
    setState(() {
      _messages.add({
        'id': tempId,
        'conversation_id': id,
        'sender_id': myId,
        'kind': 'text',
        'body': body,
        'read_by': <dynamic>[],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        '_pending': true,
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());

    try {
      if (_socketSvc.connected) {
        await _socketSvc.sendText(id, body);
        // WS listener already added the real message; drop the optimistic copy
      } else {
        await ref.read(chatRepositoryProvider).sendMessage(id, body);
        await _loadMessages(silent: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == tempId));
        text.text = body;
        showError(context, error);
      }
      return;
    }
    if (mounted) setState(() => _messages.removeWhere((m) => m['id'] == tempId));
  }

  Future<void> startCall({required bool video}) async {
    if (startingCall) return;
    setState(() => startingCall = true);
    try {
      final response = await ref
          .read(callRepositoryProvider)
          .invite(conversationId: id, video: video);
      final call = response['call'] as Map<String, dynamic>;
      final agora = response['agora'] as Map<String, dynamic>;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OutgoingCallScreen(call: call, agora: agora),
        ),
      );
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => startingCall = false);
    }
  }

  Future<void> startVoiceNote() async {
    if (sending || recording) return;
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) showApiError(context, 'Allow microphone access to record voice notes.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/bondoo-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 64000, numChannels: 1),
        path: path,
      );
      recordingTimer?.cancel();
      setState(() { recording = true; recordingMs = 0; });
      recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => recordingMs += 1000);
      });
    } catch (error) {
      if (mounted) showError(context, error);
    }
  }

  Future<void> cancelVoiceNote() async {
    recordingTimer?.cancel();
    final path = await recorder.stop();
    if (path != null) {
      try { await File(path).delete(); } catch (_) {}
    }
    if (mounted) setState(() { recording = false; recordingMs = 0; });
  }

  Future<void> stopAndSendVoiceNote() async {
    if (!recording || sending) return;
    recordingTimer?.cancel();
    setState(() => sending = true);
    try {
      final path = await recorder.stop();
      if (path == null) return;
      final file = File(path);
      // recorder.stop() returns before the OS finishes writing the M4A moov/mdat
      // atoms — the file starts as a 28-byte ftyp stub. Poll until it grows.
      for (var i = 0; i < 20 && (await file.length()) <= 28; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      final bytes = await file.readAsBytes();
      debugPrint('[VoiceNote] recording size: ${bytes.length} bytes');
      try { await file.delete(); } catch (_) {}
      if (bytes.length <= 100 || recordingMs < 500) throw Exception('Voice note is too short.');
      final audioDataUrl = 'data:audio/mp4;base64,${base64Encode(bytes)}';
      await ref.read(chatRepositoryProvider).sendVoiceNote(
        conversationId: id,
        audioDataUrl: audioDataUrl,
        durationMs: recordingMs,
      );
      // Server broadcasts new_message via WS; fallback: reload
      if (!_socketSvc.connected) await _loadMessages(silent: true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() { sending = false; recording = false; recordingMs = 0; });
    }
  }

  Future<void> pickAndSendImage() async {
    if (sending || recording) return;
    try {
      final image = await imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 78,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      if (bytes.isEmpty) throw Exception('Selected image is empty.');
      final mimeType = image.mimeType ?? _imageMimeType(image.name);
      final imageDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      if (imageDataUrl.length > 4_000_000) throw Exception('Image is too large. Please choose a smaller image.');
      setState(() => sending = true);
      await ref.read(chatRepositoryProvider).sendImage(conversationId: id, imageDataUrl: imageDataUrl);
      // Server broadcasts new_message via WS; fallback: reload
      if (!_socketSvc.connected) await _loadMessages(silent: true);
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> transfer() async {
    final recipient = meta.otherId;
    if (recipient == null || transferring) return;
    final payload = await showDialog<TransferPayload>(
      context: context,
      builder: (_) => TransferDialog(recipientName: meta.title),
    );
    if (payload == null) return;
    setState(() => transferring = true);
    try {
      await ref.read(chatRepositoryProvider).sendTransfer(
        conversationId: id,
        recipientId: recipient,
        asset: payload.asset,
        amount: payload.amount,
        note: payload.note,
      );
      if (!_socketSvc.connected) await _loadMessages(silent: true);
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Transfer sent',
          message: '${payload.amount} ${payload.asset} was sent to ${meta.title}.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  void _scrollToEnd() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _socketSvc.leave(id);
    recordingTimer?.cancel();
    recorder.dispose();
    text.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 4,
        title: Row(
          children: [
            AssetAvatar(label: meta.title, imageUrl: meta.avatarUrl, size: 38),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(meta.title, style: const TextStyle(fontSize: 17)),
                  const Text(
                    'Secure conversation',
                    style: TextStyle(color: AppTheme.muted, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            onPressed: startingCall ? null : () => startCall(video: false),
            icon: const Icon(Icons.call_rounded),
          ),
          IconButton(
            tooltip: 'Video call',
            onPressed: startingCall ? null : () => startCall(video: true),
            icon: const Icon(Icons.videocam_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.background, AppTheme.backgroundSoft],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          children: [
            Expanded(child: _buildMessageList()),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: const BoxDecoration(
                  color: AppTheme.surface,
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: recording ? _buildRecordingBar() : _buildInputBar(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.only(left: 14),
            decoration: BoxDecoration(
              color: AppTheme.elevated,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.fiber_manual_record_rounded, color: AppTheme.danger, size: 13),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Recording ${formatDuration(recordingMs)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.text, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: cancelVoiceNote,
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppTheme.muted,
                    minimumSize: const Size.square(40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Send voice note',
          onPressed: sending ? null : stopAndSendVoiceNote,
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.square(48),
            shape: const CircleBorder(),
          ),
          icon: sending
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded),
        ),
      ],
    );
  }

  Widget _buildInputBar() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Send crypto',
          onPressed: transferring ? null : transfer,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: AppTheme.muted,
            minimumSize: const Size.square(40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: transferring
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.currency_exchange_rounded),
        ),
        if (meta.otherId != null)
          IconButton(
            tooltip: 'Propose trade',
            onPressed: () => showProposeTradeDialog(
              context: context,
              ref: ref,
              conversationId: id,
              sellerUserId: meta.otherId!,
              sellerName: meta.title,
              onProposed: () {
                if (!_socketSvc.connected) _loadMessages(silent: true);
              },
            ),
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: AppTheme.accent,
              minimumSize: const Size.square(40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.handshake_rounded),
          ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.only(left: 16, right: 4),
            decoration: BoxDecoration(
              color: AppTheme.elevated,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Message',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Share image',
                  onPressed: sending ? null : pickAndSendImage,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    foregroundColor: AppTheme.muted,
                    minimumSize: const Size.square(40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.image_rounded),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: text,
          builder: (context, value, _) {
            final hasText = value.text.trim().isNotEmpty;
            return IconButton(
              tooltip: hasText ? 'Send message' : 'Record voice note',
              onPressed: sending ? null : (hasText ? send : startVoiceNote),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.32),
                minimumSize: const Size.square(48),
                shape: const CircleBorder(),
              ),
              icon: sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(hasText ? Icons.send_rounded : Icons.mic_rounded),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.muted)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _loadMessages, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return const EmptyState(
        icon: Icons.waving_hand_outlined,
        title: 'Say hello',
        message: 'Send the first message in this conversation.',
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final mine = message['sender_id'] == ref.read(authControllerProvider).user?['id'];
        final time = messageTime(message['created_at']);
        final readReceipt = mine
            ? (message['_pending'] == true
                ? 'Pending'
                : readReceiptLabel(message, ref.read(authControllerProvider).user?['id'] as String?))
            : null;

        if (message['kind'] == 'trade_update') {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.elevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TradeUpdateCard(
                  body: '${message['body'] ?? ''}',
                  trade: message['trade'] as Map?,
                ),
              ),
            ),
          );
        }

        if (message['kind'] == 'image') {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  ImageMessageBubble(
                    imageDataUrl: '${message['image_data_url'] ?? ''}',
                    mine: mine,
                  ),
                  const SizedBox(height: 3),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(time, style: const TextStyle(color: AppTheme.muted, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1)),
                        if (readReceipt != null) ...[
                          const SizedBox(width: 5),
                          if (readReceipt == 'Pending')
                            const Icon(Icons.access_time_rounded, size: 13, color: AppTheme.muted)
                          else ...[
                            Icon(
                              readReceipt == 'Read' ? Icons.done_all_rounded : Icons.done_rounded,
                              size: 14,
                              color: readReceipt == 'Read' ? AppTheme.accent : AppTheme.muted,
                            ),
                            const SizedBox(width: 2),
                            Text(readReceipt, style: TextStyle(color: readReceipt == 'Read' ? AppTheme.accent : AppTheme.muted, fontSize: 10.5, fontWeight: FontWeight.w700, height: 1)),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            decoration: BoxDecoration(
              color: mine ? AppTheme.primary.withValues(alpha: 0.9) : AppTheme.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(mine ? 20 : 5),
                bottomRight: Radius.circular(mine ? 5 : 20),
              ),
              border: mine ? null : Border.all(color: AppTheme.border),
            ),
            child: MessageBubbleBody(
              mine: mine,
              timestamp: time,
              readReceipt: readReceipt,
              child: message['kind'] == 'offer'
                  ? OfferMessageCard(offer: (message['offer'] as Map?) ?? const {})
                  : message['kind'] == 'trade_proposal'
                  ? TradeProposalCard(trade: (message['trade'] as Map?) ?? const {})
                  : message['kind'] == 'voice'
                  ? VoiceNoteBubble(
                      audioDataUrl: '${message['voice_data_url'] ?? ''}',
                      durationMs: message['voice_duration_ms'] as int? ?? 0,
                      mine: mine,
                    )
                  : message['kind'] == 'transfer'
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.north_east_rounded, size: 18),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${mine ? 'Sent' : 'Received'} ${message['transfer_amount']} ${message['transfer_asset']}\n${message['transfer_note'] ?? ''}',
                            style: const TextStyle(height: 1.35),
                          ),
                        ),
                      ],
                    )
                  : Text(
                      '${message['body'] ?? ''}',
                      style: TextStyle(color: mine ? Colors.white : AppTheme.text, height: 1.4),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class MessageBubbleBody extends StatelessWidget {
  const MessageBubbleBody({
    super.key,
    required this.child,
    required this.timestamp,
    required this.mine,
    this.readReceipt,
  });

  final Widget child;
  final String timestamp;
  final bool mine;
  final String? readReceipt;

  @override
  Widget build(BuildContext context) {
    final timeColor = mine ? Colors.white.withValues(alpha: 0.72) : AppTheme.muted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(alignment: Alignment.centerLeft, child: child),
        if (timestamp.isNotEmpty || readReceipt != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (timestamp.isNotEmpty)
                Text(
                  timestamp,
                  style: TextStyle(color: timeColor, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1),
                ),
              if (readReceipt != null) ...[
                if (timestamp.isNotEmpty) const SizedBox(width: 5),
                if (readReceipt == 'Pending')
                  Icon(Icons.access_time_rounded, size: 13, color: timeColor)
                else ...[
                  Icon(
                    readReceipt == 'Read' ? Icons.done_all_rounded : Icons.done_rounded,
                    size: 14,
                    color: readReceipt == 'Read' ? AppTheme.accent : Colors.white.withValues(alpha: 0.72),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    readReceipt!,
                    style: TextStyle(
                      color: readReceipt == 'Read' ? AppTheme.accent : timeColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

String readReceiptLabel(Map message, String? currentUserId) {
  final receipts = (message['read_by'] as List? ?? []).cast<Map>();
  final readByOther = receipts.any((receipt) => '${receipt['user_id']}' != currentUserId);
  return readByOther ? 'Read' : 'Sent';
}

class VoiceNoteBubble extends StatefulWidget {
  const VoiceNoteBubble({
    super.key,
    required this.audioDataUrl,
    required this.durationMs,
    required this.mine,
  });

  final String audioDataUrl;
  final int durationMs;
  final bool mine;

  @override
  State<VoiceNoteBubble> createState() => _VoiceNoteBubbleState();
}

class _VoiceNoteBubbleState extends State<VoiceNoteBubble> {
  final player = AudioPlayer();
  bool playing = false;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => playing = false);
    });
  }

  @override
  void dispose() {
    player.dispose();
    if (_tempPath != null) {
      try { File(_tempPath!).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  Future<void> toggle() async {
    if (playing) {
      await player.stop();
      if (mounted) setState(() => playing = false);
      return;
    }
    try {
      final comma = widget.audioDataUrl.indexOf(',');
      if (comma < 0) return;
      final bytes = base64Decode(widget.audioDataUrl.substring(comma + 1));
      if (_tempPath == null) {
        final dir = await getTemporaryDirectory();
        _tempPath = '${dir.path}/bondoo_vn_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await File(_tempPath!).writeAsBytes(bytes);
      }
      debugPrint('[VoiceNote] file size: ${bytes.length} bytes → $_tempPath');
      await player.play(DeviceFileSource(_tempPath!));
      if (mounted) setState(() => playing = true);
    } catch (e) {
      debugPrint('[VoiceNote] playback error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.mine ? Colors.white : AppTheme.text;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 170),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: playing ? 'Stop' : 'Play',
            onPressed: widget.audioDataUrl.isEmpty ? null : toggle,
            icon: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded, color: color),
          ),
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: playing ? 0.72 : 0.28,
                child: Container(
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(formatDuration(widget.durationMs), style: TextStyle(color: color.withValues(alpha: 0.86))),
        ],
      ),
    );
  }
}

class ImageMessageBubble extends StatelessWidget {
  const ImageMessageBubble({super.key, required this.imageDataUrl, required this.mine});

  final String imageDataUrl;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeDataUrl(imageDataUrl);
    if (bytes == null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_rounded, color: _foregroundColor),
          const SizedBox(width: 8),
          Text('Image unavailable', style: TextStyle(color: _foregroundColor)),
        ],
      );
    }
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.7,
                  maxScale: 4,
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: MediaQuery.paddingOf(context).top + 8,
                right: 8,
                child: IconButton.filled(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 320),
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Color get _foregroundColor => mine ? Colors.white : AppTheme.text;
}

String formatDuration(int milliseconds) {
  final totalSeconds = (milliseconds / 1000).ceil();
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _imageMimeType(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

Uint8List? _decodeDataUrl(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  if (comma < 0) return null;
  try {
    return base64Decode(dataUrl.substring(comma + 1));
  } catch (_) {
    return null;
  }
}
