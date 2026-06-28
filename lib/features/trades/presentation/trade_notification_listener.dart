import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trade_events.dart';
import '../data/trade_repository.dart';
import 'trade_detail_screen.dart';

class TradeNotificationListener extends ConsumerStatefulWidget {
  const TradeNotificationListener({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<TradeNotificationListener> createState() =>
      _TradeNotificationListenerState();
}

class _TradeNotificationListenerState
    extends ConsumerState<TradeNotificationListener> {
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  @override
  void initState() {
    super.initState();
    // Background tap: user tapped notification while app was in background
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    // Terminated tap: user tapped notification that launched the app
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _handleTap(m);
    });
    // Foreground: notify event bus (refreshes any open TradeDetailScreen)
    // and show a snack banner so the user can tap to open
    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForeground);
  }

  @override
  void dispose() {
    _openedSub?.cancel();
    _foregroundSub?.cancel();
    super.dispose();
  }

  void _handleForeground(RemoteMessage message) {
    if (message.data['type'] != 'trade') return;
    final tradeId = message.data['trade_id'] as String?;
    if (tradeId == null) return;

    // Signal any open TradeDetailScreen for this trade to refresh immediately
    TradeEvents.instance.notifyTradeUpdated(tradeId);

    if (!mounted) return;
    final title = message.notification?.title ?? 'Trade update';
    final body = message.notification?.body ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (body.isNotEmpty)
              Text(body, style: const TextStyle(fontSize: 12)),
          ],
        ),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _openTrade(tradeId),
        ),
      ),
    );
  }

  void _handleTap(RemoteMessage message) {
    if (message.data['type'] != 'trade') return;
    final tradeId = message.data['trade_id'] as String?;
    if (tradeId == null || !mounted) return;
    // Signal event bus before navigation so the screen opens fresh
    TradeEvents.instance.notifyTradeUpdated(tradeId);
    _openTrade(tradeId);
  }

  Future<void> _openTrade(String tradeId) async {
    if (!mounted) return;
    try {
      final trade = await ref.read(tradeRepositoryProvider).get(tradeId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TradeDetailScreen(trade: trade)),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
