import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';
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
// import '../../offers/presentation/offer_widgets.dart'; // crypto — hidden
import '../data/chat_repository.dart';
import 'chat_helpers.dart';
import 'new_chat_screen.dart';
// import 'propose_trade_dialog.dart'; // crypto — hidden
// import 'trade_chat_card.dart'; // crypto — hidden
// import 'transfer_dialog.dart'; // crypto — hidden

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversation,
    this.storyReply,
    this.productInquiry,
  });

  final Map<String, dynamic> conversation;
  final Map<String, dynamic>? storyReply;
  final Map<String, dynamic>? productInquiry;

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
  // bool transferring = false; // crypto — hidden
  bool recording = false;
  bool startingCall = false;
  int recordingMs = 0;
  Timer? recordingTimer;
  Map<String, dynamic>? _storyReply;
  Map<String, dynamic>? _productInquiry;

  String get id => widget.conversation['id'] as String;
  ConversationMeta get meta => conversationMeta(
    widget.conversation,
    currentUserId: ref.read(authControllerProvider).user?['id'] as String?,
  );

  @override
  void initState() {
    super.initState();
    _storyReply = widget.storyReply;
    _productInquiry = widget.productInquiry;
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
    final reply = _storyReply;
    final inquiry = _productInquiry;
    if (body.isEmpty && reply == null && inquiry == null) return;

    final myId = ref.read(authControllerProvider).user?['id'] as String?;
    final tempId = 'pending_${DateTime.now().millisecondsSinceEpoch}';
    text.clear();
    setState(() {
      _storyReply = null;
      _productInquiry = null;
      _messages.add({
        'id': tempId,
        'conversation_id': id,
        'sender_id': myId,
        'kind': reply != null ? 'story_reply' : (inquiry != null ? 'product_inquiry' : 'text'),
        'body': body,
        if (reply != null) ...{
          'story_reply_image_data_url': reply['image_data_url'],
          'story_reply_caption': reply['text'],
          'story_reply_poster_name': _posterName(reply),
        },
        if (inquiry != null) ...{
          'product_id': inquiry['id'],
          'product_title': inquiry['title'],
          'product_price': inquiry['price'],
          'product_image_data_url': inquiry['image_data_url'],
        },
        'read_by': <dynamic>[],
        'created_at': DateTime.now().toUtc().toIso8601String(),
        '_pending': true,
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());

    try {
      if (reply != null) {
        await ref.read(chatRepositoryProvider).sendStoryReply(
          conversationId: id,
          body: body.isEmpty ? null : body,
          storyReplyImageDataUrl: reply['image_data_url'] as String?,
          storyReplyCaption: reply['text'] as String?,
          storyReplyPosterName: _posterName(reply),
        );
        if (mounted) await _loadMessages(silent: true);
      } else if (inquiry != null) {
        await ref.read(chatRepositoryProvider).sendProductInquiry(
          conversationId: id,
          body: body.isEmpty ? null : body,
          productId: inquiry['id'] as String?,
          productTitle: inquiry['title'] as String?,
          productPrice: (inquiry['price'] as num?)?.toDouble(),
          productImageDataUrl: inquiry['image_data_url'] as String?,
        );
        if (mounted) await _loadMessages(silent: true);
      } else if (_socketSvc.connected) {
        await _socketSvc.sendText(id, body);
      } else {
        await ref.read(chatRepositoryProvider).sendMessage(id, body);
        await _loadMessages(silent: true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
          _storyReply = reply;
          _productInquiry = inquiry;
          text.text = body;
        });
        showError(context, error);
      }
      return;
    }
    if (mounted) setState(() => _messages.removeWhere((m) => m['id'] == tempId));
  }

  String _posterName(Map<String, dynamic> story) {
    final user = story['user'] as Map<String, dynamic>?;
    return '${user?['display_name'] ?? user?['username'] ?? 'Story'}';
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

  // crypto — hidden
  // Future<void> transfer() async {
  //   final recipient = meta.otherId;
  //   if (recipient == null || transferring) return;
  //   final payload = await showDialog<TransferPayload>(
  //     context: context,
  //     builder: (_) => TransferDialog(recipientName: meta.title),
  //   );
  //   if (payload == null) return;
  //   setState(() => transferring = true);
  //   try {
  //     await ref.read(chatRepositoryProvider).sendTransfer(
  //       conversationId: id,
  //       recipientId: recipient,
  //       asset: payload.asset,
  //       amount: payload.amount,
  //       note: payload.note,
  //     );
  //     if (!_socketSvc.connected) await _loadMessages(silent: true);
  //     if (mounted) {
  //       await showApiSuccess(
  //         context,
  //         title: 'Transfer sent',
  //         message: '${payload.amount} ${payload.asset} was sent to ${meta.title}.',
  //       );
  //     }
  //   } catch (error) {
  //     if (mounted) showError(context, error);
  //   } finally {
  //     if (mounted) setState(() => transferring = false);
  //   }
  // }

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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_storyReply != null)
                      _StoryReplyBanner(
                        story: _storyReply!,
                        onDismiss: () => setState(() => _storyReply = null),
                      ),
                    if (_productInquiry != null)
                      _ProductInquiryBanner(
                        inquiry: _productInquiry!,
                        onDismiss: () => setState(() => _productInquiry = null),
                      ),
                    recording ? _buildRecordingBar() : _buildInputBar(),
                  ],
                ),
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
        // crypto — hidden
        // IconButton(
        //   tooltip: 'Send crypto',
        //   onPressed: transferring ? null : transfer,
        //   ...
        // ),
        // if (meta.otherId != null)
        //   IconButton(
        //     tooltip: 'Propose trade',
        //     onPressed: () => showProposeTradeDialog(...),
        //     icon: const Icon(Icons.handshake_rounded),
        //   ),
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
            final canSend = hasText || _storyReply != null || _productInquiry != null;
            return IconButton(
              tooltip: canSend ? 'Send message' : 'Record voice note',
              onPressed: sending ? null : (canSend ? send : startVoiceNote),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.32),
                minimumSize: const Size.square(48),
                shape: const CircleBorder(),
              ),
              icon: sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(canSend ? Icons.send_rounded : Icons.mic_rounded),
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

        // crypto — hidden
        // if (message['kind'] == 'trade_update') { ... TradeUpdateCard ... }

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
              child: /* crypto kinds hidden:
                  message['kind'] == 'offer' ? OfferMessageCard(...) :
                  message['kind'] == 'trade_proposal' ? TradeProposalCard(...) :
                  message['kind'] == 'transfer' ? Row(transfer UI) : */
                  message['kind'] == 'product_inquiry'
                  ? _ProductInquiryContent(
                      imageDataUrl: message['product_image_data_url'] as String?,
                      title: message['product_title'] as String?,
                      price: (message['product_price'] as num?)?.toDouble(),
                      body: message['body'] as String?,
                      mine: mine,
                    )
                  : message['kind'] == 'story_reply'
                  ? _StoryReplyContent(
                      imageDataUrl: message['story_reply_image_data_url'] as String?,
                      caption: message['story_reply_caption'] as String?,
                      posterName: message['story_reply_poster_name'] as String? ?? 'Story',
                      body: message['body'] as String?,
                      mine: mine,
                    )
                  : message['kind'] == 'voice'
                  ? VoiceNoteBubble(
                      audioDataUrl: '${message['voice_data_url'] ?? ''}',
                      durationMs: message['voice_duration_ms'] as int? ?? 0,
                      mine: mine,
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
  final _player = AudioPlayer();
  bool playing = false;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    // just_audio / ExoPlayer (Android) + AVPlayer (iOS) — far more reliable
    // codec support than audioplayers / MediaPlayer for AAC-LC M4A files.
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && mounted) {
        setState(() => playing = false);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    if (_tempPath != null) {
      try { File(_tempPath!).deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  Future<void> toggle() async {
    if (playing) {
      await _player.stop();
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
      await _player.setFilePath(_tempPath!);
      await _player.play();
      if (mounted) setState(() => playing = true);
    } catch (e) {
      debugPrint('[VoiceNote] playback error: $e');
      if (mounted) setState(() => playing = false);
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

// ── Product inquiry banner shown above the chat input ─────────────────────

class _ProductInquiryBanner extends StatelessWidget {
  const _ProductInquiryBanner({required this.inquiry, required this.onDismiss});
  final Map<String, dynamic> inquiry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final imageDataUrl = inquiry['image_data_url'] as String?;
    final title = '${inquiry['title'] ?? 'Product'}';
    final price = (inquiry['price'] as num?)?.toDouble();
    final thumb = imageDataUrl != null ? _decodeDataUrl(imageDataUrl) : null;
    final priceStr = price != null
        ? '₦${price.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.elevated,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: AppTheme.accent, width: 3)),
      ),
      child: Row(
        children: [
          if (thumb != null)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                bottomLeft: Radius.circular(9),
              ),
              child: Image.memory(thumb, width: 48, height: 48, fit: BoxFit.cover),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  if (priceStr.isNotEmpty)
                    Text(priceStr, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, size: 16, color: AppTheme.muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ── Product inquiry content inside a chat bubble ───────────────────────────

class _ProductInquiryContent extends StatelessWidget {
  const _ProductInquiryContent({
    required this.imageDataUrl,
    required this.title,
    required this.price,
    required this.body,
    required this.mine,
  });

  final String? imageDataUrl;
  final String? title;
  final double? price;
  final String? body;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final thumb = imageDataUrl != null ? _decodeDataUrl(imageDataUrl!) : null;
    final quoteAccent = mine ? Colors.white.withValues(alpha: 0.72) : AppTheme.accent;
    final quoteBg = mine ? Colors.white.withValues(alpha: 0.15) : AppTheme.elevated;
    final subtleText = mine ? Colors.white.withValues(alpha: 0.72) : AppTheme.muted;
    final priceStr = price != null
        ? '₦${price!.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}'
        : '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: quoteBg,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: quoteAccent, width: 3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title ?? 'Product',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: quoteAccent, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      if (priceStr.isNotEmpty)
                        Text(priceStr, style: TextStyle(color: subtleText, fontSize: 12, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              if (thumb != null)
                Image.memory(thumb, width: 52, height: 52, fit: BoxFit.cover),
            ],
          ),
        ),
        if (body != null && body!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(body!, style: TextStyle(color: mine ? Colors.white : AppTheme.text, height: 1.4)),
        ],
      ],
    );
  }
}

// ── Story reply banner shown above the chat input ──────────────────────────

class _StoryReplyBanner extends StatelessWidget {
  const _StoryReplyBanner({required this.story, required this.onDismiss});
  final Map<String, dynamic> story;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final imageDataUrl = story['image_data_url'] as String?;
    final caption = story['text'] as String?;
    final poster = story['user'] as Map<String, dynamic>?;
    final posterName =
        '${poster?['display_name'] ?? poster?['username'] ?? 'their'}';
    final thumb = imageDataUrl != null ? _decodeDataUrl(imageDataUrl) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppTheme.elevated,
        borderRadius: BorderRadius.circular(12),
        border: const Border(left: BorderSide(color: AppTheme.primary, width: 3)),
      ),
      child: Row(
        children: [
          if (thumb != null)
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                bottomLeft: Radius.circular(9),
              ),
              child: Image.memory(thumb,
                  width: 48, height: 48, fit: BoxFit.cover),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Story by $posterName',
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (caption != null && caption.isNotEmpty)
                    Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.muted, fontSize: 12),
                    )
                  else if (thumb != null)
                    const Text('Photo',
                        style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded,
                size: 16, color: AppTheme.muted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ── Story reply content inside a chat bubble ───────────────────────────────

class _StoryReplyContent extends StatelessWidget {
  const _StoryReplyContent({
    required this.imageDataUrl,
    required this.caption,
    required this.posterName,
    required this.body,
    required this.mine,
  });

  final String? imageDataUrl;
  final String? caption;
  final String posterName;
  final String? body;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final thumb = imageDataUrl != null ? _decodeDataUrl(imageDataUrl!) : null;
    final quoteAccent = mine ? Colors.white.withValues(alpha: 0.72) : AppTheme.primary;
    final quoteBg = mine ? Colors.white.withValues(alpha: 0.15) : AppTheme.elevated;
    final subtleText = mine ? Colors.white.withValues(alpha: 0.72) : AppTheme.muted;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: quoteBg,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: quoteAccent, width: 3)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        posterName,
                        style: TextStyle(
                          color: quoteAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (caption != null && caption!.isNotEmpty)
                        Text(
                          caption!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtleText, fontSize: 12),
                        )
                      else if (thumb != null)
                        Text(
                          'Photo',
                          style: TextStyle(color: subtleText, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ),
              if (thumb != null)
                Image.memory(thumb, width: 52, height: 52, fit: BoxFit.cover),
            ],
          ),
        ),
        if (body != null && body!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            body!,
            style: TextStyle(
              color: mine ? Colors.white : AppTheme.text,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
