import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;

class SocketService {
  static final _instance = SocketService._();
  factory SocketService() => _instance;
  SocketService._();

  sio.Socket? _socket;
  String? _currentToken;
  final _newMessageCtrl = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewMessage => _newMessageCtrl.stream;
  bool get connected => _socket?.connected == true;

  void connect(String token, String baseUrl) {
    if (_socket?.connected == true && _currentToken == token) return;
    _socket?.dispose();
    _currentToken = token;
    // Dart's Uri.port returns 0 for default ports (443/80), which breaks the
    // socket.io Dart client's WebSocket URL. Normalise to an explicit port.
    final uri = Uri.parse(baseUrl);
    final port = uri.hasPort && uri.port != 0
        ? uri.port
        : (uri.scheme == 'https' ? 443 : 80);
    final wsUrl = uri.replace(port: port).toString();
    _socket = sio.io(
      wsUrl,
      sio.OptionBuilder()
          .setTransports(['polling', 'websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );
    _socket!
      ..onConnect((_) => debugPrint('[WS] connected'))
      ..onDisconnect((_) => debugPrint('[WS] disconnected'))
      ..onConnectError((e) => debugPrint('[WS] connect error: $e'))
      ..on('new_message', (raw) {
        final data = (raw is List && raw.isNotEmpty) ? raw.first : raw;
        if (data is Map) {
          _newMessageCtrl.add(Map<String, dynamic>.from(data));
        }
      });
    _socket!.connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _currentToken = null;
  }

  void join(String conversationId) =>
      _socket?.emit('join_conversation', conversationId);

  void leave(String conversationId) =>
      _socket?.emit('leave_conversation', conversationId);

  Future<void> sendText(String conversationId, String body) {
    final completer = Completer<void>();
    if (_socket == null || !connected) {
      completer.completeError('Socket not connected');
      return completer.future;
    }
    _socket!.emitWithAck(
      'send_message',
      {'conversation_id': conversationId, 'body': body},
      ack: (response) {
        final data = (response is List) ? response.first : response;
        if (data is Map && data['ok'] == true) {
          completer.complete();
        } else {
          final err = (data is Map ? data['error'] : null) ?? 'Send failed';
          completer.completeError(err);
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw Exception('Message send timed out'),
    );
  }
}
