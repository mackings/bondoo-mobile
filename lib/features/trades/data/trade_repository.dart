import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final tradeRepositoryProvider = Provider<TradeRepository>((ref) {
  return TradeRepository(ref.watch(apiClientProvider));
});

class TradeRepository {
  TradeRepository(this._api);
  final ApiClient _api;

  Future<List<dynamic>> list() async =>
      await _api.get('/trades') as List<dynamic>;

  Future<Map<String, dynamic>> get(String id) async =>
      await _api.get('/trades/$id') as Map<String, dynamic>;

  Future<Map<String, dynamic>> create({
    required String offerId,
    required double fiatAmount,
    required String network,
    required String buyerWalletAddress,
    required String buyerWalletNetwork,
  }) async =>
      await _api.post('/trades', {
        'offer_id': offerId,
        'fiat_amount': fiatAmount,
        'network': network,
        'buyer_wallet_address': buyerWalletAddress,
        'buyer_wallet_network': buyerWalletNetwork,
      }) as Map<String, dynamic>;

  /// Seller calls after sending crypto — polls Bybit for deposit confirmation.
  /// Returns {found: bool, trade?: Map}
  Future<Map<String, dynamic>> checkDeposit(String id) async =>
      await _api.post('/trades/$id/check-deposit') as Map<String, dynamic>;

  /// Buyer marks payment sent and uploads receipt image.
  Future<Map<String, dynamic>> paymentSent(
    String id, {
    required String imagePath,
    String? note,
  }) async =>
      await _api.postMultipart(
        '/trades/$id/payment-sent',
        {if (note != null && note.isNotEmpty) 'note': note},
        filePath: imagePath,
        fileField: 'receipt',
      ) as Map<String, dynamic>;

  /// Seller releases coins to buyer wallet.
  Future<Map<String, dynamic>> release(String id) async =>
      await _api.post('/trades/$id/release') as Map<String, dynamic>;

  Future<Map<String, dynamic>> cancel(String id) async =>
      await _api.post('/trades/$id/cancel') as Map<String, dynamic>;

  Future<Map<String, dynamic>> dispute(String id, String reason) async =>
      await _api.post('/trades/$id/dispute', {'reason': reason})
          as Map<String, dynamic>;

  Future<List<dynamic>> getMarket({String? type, String? coin}) async {
    final params = <String>[];
    if (type != null) params.add('type=${Uri.encodeQueryComponent(type)}');
    if (coin != null) params.add('coin=${Uri.encodeQueryComponent(coin)}');
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    return await _api.get('/market$query') as List<dynamic>;
  }

  Future<Map<String, dynamic>> setTradeStatus({
    required String type,
    required String coin,
    required String network,
    required String paymentMethod,
    double? rate,
    bool active = true,
  }) async =>
      await _api.patch('/me/trade-status', {
        'type': type,
        'coin': coin,
        'network': network,
        'payment_method': paymentMethod,
        'rate': rate,
        'active': active,
      }) as Map<String, dynamic>;

  Future<Map<String, dynamic>> clearTradeStatus() async =>
      await _api.delete('/me/trade-status') as Map<String, dynamic>;
}
