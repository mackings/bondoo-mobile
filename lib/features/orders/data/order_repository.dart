import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(ref.watch(apiClientProvider));
});

class OrderRepository {
  OrderRepository(this._api);

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> getMyOrders() async {
    return (await _api.get('/orders') as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMySales() async {
    return (await _api.get('/orders/selling') as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getOrder(String id) async {
    return await _api.get('/orders/$id') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateStatus({
    required String orderId,
    required String status,
    String? note,
    String? trackingCode,
    String? trackingUrl,
  }) async {
    final body = <String, dynamic>{'status': status};
    if (note != null) body['note'] = note;
    if (trackingCode != null) body['tracking_code'] = trackingCode;
    if (trackingUrl != null) body['tracking_url'] = trackingUrl;
    return await _api.patch('/orders/$orderId/status', body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> confirmDelivery(String orderId) async {
    return await _api.post('/orders/$orderId/confirm') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitReview({
    required String orderId,
    required int rating,
    String? comment,
  }) async {
    final body = <String, dynamic>{'rating': rating};
    if (comment != null && comment.isNotEmpty) body['comment'] = comment;
    return await _api.post('/orders/$orderId/review', body) as Map<String, dynamic>;
  }
}
