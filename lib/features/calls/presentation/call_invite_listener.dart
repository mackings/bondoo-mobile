import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/push_notifications.dart';
import '../data/call_repository.dart';
import 'incoming_call_screen.dart';

class CallInviteListener extends ConsumerStatefulWidget {
  const CallInviteListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CallInviteListener> createState() => _CallInviteListenerState();
}

class _CallInviteListenerState extends ConsumerState<CallInviteListener> {
  StreamSubscription<RemoteMessage>? foregroundSub;
  StreamSubscription<RemoteMessage>? openedSub;
  Timer? pollTimer;
  final Set<String> shownCallIds = {};
  bool showing = false;

  @override
  void initState() {
    super.initState();
    unawaited(initMessaging());
    pollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => checkPendingCalls(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => checkPendingCalls());
  }

  Future<void> initMessaging() async {
    try {
      await PushNotifications.initialize();
    } catch (_) {
      return;
    }
    foregroundSub = FirebaseMessaging.onMessage.listen(handleMessage);
    openedSub = FirebaseMessaging.onMessageOpenedApp.listen(handleMessage);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) handleMessage(message);
    });
    await checkPendingCalls();
  }

  @override
  void dispose() {
    foregroundSub?.cancel();
    openedSub?.cancel();
    pollTimer?.cancel();
    super.dispose();
  }

  void handleMessage(RemoteMessage message) {
    if (message.data['type'] != 'incoming_call') return;
    final callId = message.data['call_id'];
    if (callId is String && callId.isNotEmpty) {
      unawaited(openIncomingCall(callId));
    }
  }

  Future<void> checkPendingCalls() async {
    if (showing || !mounted) return;
    try {
      final calls = await ref.read(callRepositoryProvider).pending();
      if (calls.isEmpty) return;
      final call = calls.first as Map<String, dynamic>;
      final callId = '${call['id']}';
      if (shownCallIds.contains(callId)) return;
      await showIncomingCall(call);
    } catch (_) {}
  }

  Future<void> openIncomingCall(String callId) async {
    if (shownCallIds.contains(callId) || showing || !mounted) return;
    try {
      final call = await ref.read(callRepositoryProvider).getCall(callId);
      if (call['status'] != 'ringing') return;
      await showIncomingCall(call);
    } catch (_) {}
  }

  Future<void> showIncomingCall(Map<String, dynamic> call) async {
    final callId = '${call['id']}';
    if (shownCallIds.contains(callId) || showing || !mounted) return;
    shownCallIds.add(callId);
    showing = true;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => IncomingCallScreen(call: call)));
    showing = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
