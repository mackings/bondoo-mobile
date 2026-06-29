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

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/api_feedback.dart';
import '../../../shared/widgets/async_state_view.dart';
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
  late Future<List<dynamic>> future = load();
  bool sending = false;
  bool transferring = false;
  bool recording = false;
  bool guidanceShown = false;
  bool startingCall = false;
  int recordingMs = 0;
  Timer? recordingTimer;

  String get id => widget.conversation['id'] as String;
  ConversationMeta get meta => conversationMeta(
    widget.conversation,
    currentUserId: ref.read(authControllerProvider).user?['id'] as String?,
  );

  Future<List<dynamic>> load() async {
    final repo = ref.read(chatRepositoryProvider);
    final messages = await repo.messages(id);
    unawaited(repo.markRead(id));
    return messages;
  }

  Future<void> send() async {
    final body = text.text.trim();
    if (body.isEmpty || sending) return;
    text.clear();
    setState(() => sending = true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(id, body);
      setState(() {
        future = load();
      });
    } catch (error) {
      text.text = body;
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> sendQuickMessage(String body) async {
    if (sending) return;
    setState(() => sending = true);
    try {
      await ref.read(chatRepositoryProvider).sendMessage(id, body);
      setState(() {
        future = load();
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
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
        if (mounted) {
          showApiError(
            context,
            'Allow microphone access to record voice notes.',
          );
        }
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/bondoo-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          numChannels: 1,
        ),
        path: path,
      );
      recordingTimer?.cancel();
      setState(() {
        recording = true;
        recordingMs = 0;
      });
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
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        recording = false;
        recordingMs = 0;
      });
    }
  }

  Future<void> stopAndSendVoiceNote() async {
    if (!recording || sending) return;
    recordingTimer?.cancel();
    setState(() => sending = true);
    try {
      final path = await recorder.stop();
      if (path == null) return;
      final file = File(path);
      final bytes = await file.readAsBytes();
      try {
        await file.delete();
      } catch (_) {}
      if (bytes.isEmpty || recordingMs < 500) {
        throw Exception('Voice note is too short.');
      }
      final audioDataUrl = 'data:audio/mp4;base64,${base64Encode(bytes)}';
      await ref
          .read(chatRepositoryProvider)
          .sendVoiceNote(
            conversationId: id,
            audioDataUrl: audioDataUrl,
            durationMs: recordingMs,
          );
      setState(() {
        future = load();
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
          recording = false;
          recordingMs = 0;
        });
      }
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
      if (bytes.isEmpty) {
        throw Exception('Selected image is empty.');
      }
      final mimeType = image.mimeType ?? _imageMimeType(image.name);
      final imageDataUrl = 'data:$mimeType;base64,${base64Encode(bytes)}';
      if (imageDataUrl.length > 4_000_000) {
        throw Exception('Image is too large. Please choose a smaller image.');
      }
      setState(() => sending = true);
      await ref
          .read(chatRepositoryProvider)
          .sendImage(conversationId: id, imageDataUrl: imageDataUrl);
      setState(() {
        future = load();
      });
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  void maybeShowTradeGuidance(List<dynamic> messages) {
    if (guidanceShown || messages.isEmpty) return;
    Map? offer;
    for (final message in messages.cast<Map>()) {
      if (message['kind'] == 'offer') {
        offer = message['offer'] as Map?;
        break;
      }
    }
    if (offer == null) return;
    guidanceShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: AppTheme.surface,
        builder: (_) => TradeGuidanceSheet(
          offer: offer!,
          currentUserId:
              ref.read(authControllerProvider).user?['id'] as String?,
          onSend: sendQuickMessage,
        ),
      );
    });
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
      await ref
          .read(chatRepositoryProvider)
          .sendTransfer(
            conversationId: id,
            recipientId: recipient,
            asset: payload.asset,
            amount: payload.amount,
            note: payload.note,
          );
      setState(() {
        future = load();
      });
      if (mounted) {
        await showApiSuccess(
          context,
          title: 'Transfer sent',
          message:
              '${payload.amount} ${payload.asset} was sent to ${meta.title}.',
        );
      }
    } catch (error) {
      if (mounted) showError(context, error);
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  @override
  void dispose() {
    recordingTimer?.cancel();
    recorder.dispose();
    text.dispose();
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
                    style: TextStyle(
                      color: AppTheme.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
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
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: future,
                builder: (context, snapshot) => AsyncStateView<List<dynamic>>(
                  snapshot: snapshot,
                  onRetry: () => setState(() {
                    future = load();
                  }),
                  builder: (messages) {
                    maybeShowTradeGuidance(messages);
                    return messages.isEmpty
                        ? const EmptyState(
                            icon: Icons.waving_hand_outlined,
                            title: 'Say hello',
                            message:
                                'Send the first message in this conversation.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index] as Map;
                              final mine =
                                  message['sender_id'] ==
                                  ref.read(authControllerProvider).user?['id'];
                              final time = messageTime(message['created_at']);
                              final readReceipt = mine
                                  ? readReceiptLabel(
                                      message,
                                      ref
                                              .read(authControllerProvider)
                                              .user?['id']
                                          as String?,
                                    )
                                  : null;

                              // Trade update — centered system message
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

                              return Align(
                                alignment: mine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.sizeOf(context).width * 0.76,
                                  ),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 11,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? AppTheme.primary.withValues(
                                            alpha: 0.9,
                                          )
                                        : AppTheme.surface,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(20),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: Radius.circular(
                                        mine ? 20 : 5,
                                      ),
                                      bottomRight: Radius.circular(
                                        mine ? 5 : 20,
                                      ),
                                    ),
                                    border: mine
                                        ? null
                                        : Border.all(color: AppTheme.border),
                                  ),
                                  child: MessageBubbleBody(
                                    mine: mine,
                                    timestamp: time,
                                    readReceipt: readReceipt,
                                    child: message['kind'] == 'offer'
                                        ? OfferMessageCard(
                                            offer:
                                                (message['offer'] as Map?) ??
                                                const {},
                                          )
                                        : message['kind'] == 'trade_proposal'
                                        ? TradeProposalCard(
                                            trade: (message['trade'] as Map?) ?? const {},
                                          )
                                        : message['kind'] == 'image'
                                        ? ImageMessageBubble(
                                            imageDataUrl:
                                                '${message['image_data_url'] ?? ''}',
                                            mine: mine,
                                          )
                                        : message['kind'] == 'voice'
                                        ? VoiceNoteBubble(
                                            audioDataUrl:
                                                '${message['voice_data_url'] ?? ''}',
                                            durationMs:
                                                message['voice_duration_ms']
                                                    as int? ??
                                                0,
                                            mine: mine,
                                          )
                                        : message['kind'] == 'transfer'
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.north_east_rounded,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Flexible(
                                                child: Text(
                                                  '${mine ? 'Sent' : 'Received'} ${message['transfer_amount']} ${message['transfer_asset']}\n${message['transfer_note'] ?? ''}',
                                                  style: const TextStyle(
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text('${message['body'] ?? ''}'),
                                  ),
                                ),
                              );
                            },
                          );
                  },
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withValues(alpha: 0.98),
                  border: const Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: recording
                    ? Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.only(left: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.elevated.withValues(
                                  alpha: 0.72,
                                ),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.fiber_manual_record_rounded,
                                    color: AppTheme.danger,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Recording ${formatDuration(recordingMs)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.text,
                                        fontWeight: FontWeight.w800,
                                      ),
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
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                          ),
                        ],
                      )
                    : Row(
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
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
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
                                onProposed: () => setState(() { future = load(); }),
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
                              constraints: const BoxConstraints(minHeight: 48),
                              padding: const EdgeInsets.only(
                                left: 16,
                                right: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.elevated.withValues(
                                  alpha: 0.72,
                                ),
                                borderRadius: BorderRadius.circular(24),
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
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Share image',
                                    onPressed: sending
                                        ? null
                                        : pickAndSendImage,
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      foregroundColor: AppTheme.muted,
                                      minimumSize: const Size.square(40),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
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
                                tooltip: hasText
                                    ? 'Send message'
                                    : 'Record voice note',
                                onPressed: sending
                                    ? null
                                    : hasText
                                    ? send
                                    : startVoiceNote,
                                style: IconButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: AppTheme.primary
                                      .withValues(alpha: 0.32),
                                  minimumSize: const Size.square(48),
                                  shape: const CircleBorder(),
                                ),
                                icon: sending
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Icon(
                                        hasText
                                            ? Icons.send_rounded
                                            : Icons.mic_rounded,
                                      ),
                              );
                            },
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
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
    final timeColor = mine
        ? Colors.white.withValues(alpha: 0.72)
        : AppTheme.muted;
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
                  style: TextStyle(
                    color: timeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
              if (readReceipt != null) ...[
                if (timestamp.isNotEmpty) const SizedBox(width: 5),
                Icon(
                  readReceipt == 'Read'
                      ? Icons.done_all_rounded
                      : Icons.done_rounded,
                  size: 14,
                  color: readReceipt == 'Read'
                      ? AppTheme.accent
                      : Colors.white.withValues(alpha: 0.72),
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
          ),
        ],
      ],
    );
  }
}

String readReceiptLabel(Map message, String? currentUserId) {
  final receipts = (message['read_by'] as List? ?? []).cast<Map>();
  final readByOther = receipts.any(
    (receipt) => '${receipt['user_id']}' != currentUserId,
  );
  return readByOther ? 'Read' : 'Sent';
}

class TradeGuidanceSheet extends StatelessWidget {
  const TradeGuidanceSheet({
    super.key,
    required this.offer,
    required this.currentUserId,
    required this.onSend,
  });

  final Map offer;
  final String? currentUserId;
  final Future<void> Function(String body) onSend;

  bool get currentUserIsSeller {
    final makerIsSeller = '${offer['side']}' == 'sell';
    final currentUserIsMaker = '${offer['user_id']}' == currentUserId;
    return makerIsSeller ? currentUserIsMaker : !currentUserIsMaker;
  }

  @override
  Widget build(BuildContext context) {
    final sellerTitle = currentUserIsSeller
        ? 'You are the seller'
        : 'Seller step';
    final buyerTitle = currentUserIsSeller ? 'Buyer step' : 'You are the buyer';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Trade checklist',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _GuidanceStep(
                  icon: Icons.payments_rounded,
                  title: sellerTitle,
                  message:
                      'Seller should ask the buyer to pay first using the agreed payment method. Do not release crypto before confirming payment.',
                ),
                _GuidanceStep(
                  icon: Icons.receipt_long_rounded,
                  title: buyerTitle,
                  message:
                      'Buyer should send payment proof or receipt in this chat, then attach the wallet address for the crypto payout.',
                ),
                _GuidanceStep(
                  icon: Icons.wallet_rounded,
                  title: 'Payout',
                  message:
                      'After payment is confirmed, seller should request and verify the buyer wallet address before sending crypto.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.payments_rounded, size: 18),
                      label: const Text('Ask buyer to pay'),
                      onPressed: () {
                        Navigator.pop(context);
                        onSend(
                          'Please make payment first using the agreed payment method, then send the receipt here.',
                        );
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.receipt_rounded, size: 18),
                      label: const Text('Request receipt'),
                      onPressed: () {
                        Navigator.pop(context);
                        onSend(
                          'Please attach your payment proof/receipt in this chat for confirmation.',
                        );
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.wallet_rounded, size: 18),
                      label: const Text('Request wallet'),
                      onPressed: () {
                        Navigator.pop(context);
                        onSend(
                          'Payment confirmed. Please send your ${offer['coin']} wallet address and provider.',
                        );
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.info_outline_rounded, size: 18),
                      label: const Text('Send wallet reminder'),
                      onPressed: () {
                        Navigator.pop(context);
                        onSend(
                          'After sending payment proof, please also send your wallet address for the crypto payout.',
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    super.dispose();
  }

  Future<void> toggle() async {
    if (playing) {
      await player.stop();
      if (mounted) setState(() => playing = false);
      return;
    }

    final comma = widget.audioDataUrl.indexOf(',');
    if (comma < 0) return;
    final meta = widget.audioDataUrl.substring(0, comma);
    final bytes = base64Decode(widget.audioDataUrl.substring(comma + 1));
    final mimeType = meta.contains('audio/mp4') ? 'audio/mp4' : null;
    await player.play(BytesSource(bytes, mimeType: mimeType));
    if (mounted) setState(() => playing = true);
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
            icon: Icon(
              playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: color,
            ),
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
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatDuration(widget.durationMs),
            style: TextStyle(color: color.withValues(alpha: 0.86)),
          ),
        ],
      ),
    );
  }
}

class ImageMessageBubble extends StatelessWidget {
  const ImageMessageBubble({
    super.key,
    required this.imageDataUrl,
    required this.mine,
  });

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
          constraints: const BoxConstraints(
            minWidth: 180,
            maxWidth: 280,
            maxHeight: 320,
          ),
          child: Image.memory(bytes, fit: BoxFit.cover),
        ),
      ),
    );
  }

  Color get _foregroundColor => mine ? Colors.white : AppTheme.text;
}

class _GuidanceStep extends StatelessWidget {
  const _GuidanceStep({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryBright, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(color: AppTheme.muted, height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
