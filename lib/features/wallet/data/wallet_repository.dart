import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return WalletRepository(ref.watch(apiClientProvider));
});

class WalletRepository {
  WalletRepository(this._api);

  final ApiClient _api;

  /// Returns { balances, addresses, derivation_paths, wallet_index }
  Future<Map<String, dynamic>> getWallet() async =>
      await _api.get('/wallet') as Map<String, dynamic>;

  /// Fetches the live on-chain balance at the user's address for a coin/network.
  /// Returns { coin, network, address, onchain_balance, inapp_balance }
  Future<Map<String, dynamic>> getOnchainBalance({
    required String coin,
    required String network,
  }) async =>
      await _api.get('/wallet/onchain-balance?coin=$coin&network=$network')
          as Map<String, dynamic>;

  /// Manually scans blockchain for a deposit and credits it if new.
  /// Returns { found, credited?, already_credited?, txid?, amount?, coin, network }
  Future<Map<String, dynamic>> checkDeposit({
    required String coin,
    required String network,
  }) async =>
      await _api.post('/wallet/check-deposit', {'coin': coin, 'network': network})
          as Map<String, dynamic>;

  /// Broadcasts an on-chain withdrawal from the user's HD wallet address.
  /// Returns { txid, coin, network, amount, to_address }
  Future<Map<String, dynamic>> withdraw({
    required String coin,
    required String network,
    required double amount,
    required String toAddress,
  }) async =>
      await _api.post('/wallet/withdraw', {
        'coin': coin,
        'network': network,
        'amount': amount,
        'to_address': toAddress,
      }) as Map<String, dynamic>;

  /// Returns the last 50 withdrawals for this user.
  Future<List<dynamic>> getWithdrawals() async =>
      await _api.get('/wallet/withdrawals') as List<dynamic>;

  /// Returns the last 50 credited deposits for this user.
  Future<List<dynamic>> getDeposits() async =>
      await _api.get('/wallet/deposits') as List<dynamic>;
}
