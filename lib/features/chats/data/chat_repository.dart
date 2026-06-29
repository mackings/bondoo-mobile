import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(apiClientProvider));
});

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;

  Future<List<dynamic>> conversations() async =>
      await _api.get('/chat/conversations') as List<dynamic>;

  Future<List<dynamic>> messages(String conversationId) async {
    return await _api.get('/chat/conversations/$conversationId/messages')
        as List<dynamic>;
  }

  Future<void> markRead(String conversationId) async {
    await _api.post('/chat/conversations/$conversationId/read');
  }

  Future<void> sendMessage(String conversationId, String body) async {
    await _api.post('/chat/conversations/$conversationId/messages', {
      'body': body,
    });
  }

  Future<void> sendVoiceNote({
    required String conversationId,
    required String audioDataUrl,
    required int durationMs,
  }) async {
    await _api.post('/chat/conversations/$conversationId/voice-notes', {
      'audio_data_url': audioDataUrl,
      'duration_ms': durationMs,
    });
  }

  Future<void> sendImage({
    required String conversationId,
    required String imageDataUrl,
  }) async {
    await _api.post('/chat/conversations/$conversationId/images', {
      'image_data_url': imageDataUrl,
    });
  }

  Future<void> sendTransfer({
    required String conversationId,
    required String recipientId,
    required String asset,
    required double amount,
    required String note,
  }) async {
    await _api.post('/chat/conversations/$conversationId/transfers', {
      'recipient_id': recipientId,
      'asset': asset,
      'amount': amount,
      'note': note,
    });
  }

  Future<Map<String, dynamic>> agoraToken(String conversationId) async {
    return await _api.post('/calls/agora-token', {
          'conversation_id': conversationId,
        })
        as Map<String, dynamic>;
  }

  Future<List<dynamic>> searchUsers(String query) async {
    return await _api.get(
          '/chat/users/search?q=${Uri.encodeQueryComponent(query)}',
        )
        as List<dynamic>;
  }

  Future<String> openDirect(String otherId) async {
    final response =
        await _api.post('/chat/users/open-direct', {'other_id': otherId})
            as Map;
    return response['conversation_id'] as String;
  }

  Future<Map<String, dynamic>> proposeTrade({
    required String conversationId,
    required String sellerUserId,
    required String coin,
    required String network,
    required double fiatAmount,
    required String fiatCurrency,
    required double rate,
    required String paymentMethod,
    required String buyerWalletAddress,
    required String buyerWalletNetwork,
  }) async =>
      await _api.post('/chat/conversations/$conversationId/propose-trade', {
        'seller_user_id': sellerUserId,
        'coin': coin,
        'network': network,
        'fiat_amount': fiatAmount,
        'fiat_currency': fiatCurrency,
        'rate': rate,
        'payment_method': paymentMethod,
        'buyer_wallet_address': buyerWalletAddress,
        'buyer_wallet_network': buyerWalletNetwork,
      }) as Map<String, dynamic>;
}
