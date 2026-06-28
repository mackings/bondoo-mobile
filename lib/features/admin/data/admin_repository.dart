import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(apiClientProvider));
});

class AdminRepository {
  AdminRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> overview() async =>
      await _api.get('/admin/overview') as Map<String, dynamic>;

  Future<List<dynamic>> deposits() async =>
      await _api.get('/admin/deposits') as List<dynamic>;

  Future<void> refreshDeposits() async {
    await _api.post('/admin/deposits/refresh');
  }

  Future<void> creditDeposit(String depositId, String userId) async {
    await _api.post('/admin/deposits/$depositId/credit', {'user_id': userId});
  }
}
