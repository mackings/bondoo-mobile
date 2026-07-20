import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final paystackRepositoryProvider = Provider<PaystackRepository>((ref) {
  return PaystackRepository(ref.watch(apiClientProvider));
});

class PaystackRepository {
  PaystackRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> initializePayment(String productId, {double? amount}) async {
    final body = <String, dynamic>{'product_id': productId};
    if (amount != null) body['amount'] = amount;
    return await _api.post('/paystack/initialize', body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> verifyPayment(String reference) async {
    return await _api.get('/paystack/verify/$reference') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWallet() async {
    return await _api.get('/paystack/wallet') as Map<String, dynamic>;
  }

  Future<List<dynamic>> getBanks() async {
    return await _api.get('/paystack/banks') as List<dynamic>;
  }

  Future<Map<String, dynamic>> resolveAccount(
    String accountNumber,
    String bankCode,
  ) async {
    return await _api.get(
          '/paystack/resolve-account?account_number=${Uri.encodeQueryComponent(accountNumber)}&bank_code=${Uri.encodeQueryComponent(bankCode)}',
        ) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> getVirtualAccount() async {
    final result = await _api.get('/paystack/virtual-account');
    if (result == null) return null;
    return result as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createVirtualAccount() async {
    return await _api.post('/paystack/virtual-account') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> withdraw({
    required double amount,
    required String accountNumber,
    required String bankCode,
    required String accountName,
  }) async {
    return await _api.post('/paystack/withdraw', {
          'amount': amount,
          'account_number': accountNumber,
          'bank_code': bankCode,
          'account_name': accountName,
        }) as Map<String, dynamic>;
  }
}
