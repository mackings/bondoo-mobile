import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(apiClientProvider));
});

class WalletRepository {
  WalletRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> summary() async {
    final wallets = await _api.get('/me/wallets') as List;
    final config = await _api.get('/config') as Map;
    return {'wallets': wallets, 'config': config};
  }
}
