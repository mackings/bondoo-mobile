import 'dart:async';

/// Singleton event bus for trade refresh signals.
/// The notification listener emits a trade_id here; any open
/// TradeDetailScreen for that trade listens and refreshes immediately.
class TradeEvents {
  TradeEvents._();
  static final TradeEvents instance = TradeEvents._();

  final _controller = StreamController<String>.broadcast();

  Stream<String> get onTradeUpdated => _controller.stream;

  void notifyTradeUpdated(String tradeId) => _controller.add(tradeId);
}
