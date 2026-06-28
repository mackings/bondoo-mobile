import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(apiClientProvider));
});

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> load() async {
    final profile = await _api.get('/me/profile') as Map<String, dynamic>;
    return {
      'profile': profile,
      'roles': [
        {'role': profile['role'] ?? 'user'},
      ],
    };
  }

  Future<void> saveProfile({
    required String displayName,
    required String username,
  }) async {
    await _api.patch('/me/profile', {
      'display_name': displayName,
      'username': username,
    });
  }

  Future<Map<String, dynamic>> uploadAvatar(String imageDataUrl) async {
    return await _api.post('/me/profile/avatar', {
          'image_data_url': imageDataUrl,
        })
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> linkWallet(
    String chain,
    String provider,
    String address,
  ) async {
    return await _api.post('/me/linked-wallet', {
          'chain': chain,
          'provider': provider,
          'address': address,
        })
        as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveBankAccount({
    required String bankName,
    required String accountName,
    required String accountNumber,
    required String currency,
  }) async {
    return await _api.post('/me/bank-account', {
          'bank_name': bankName,
          'account_name': accountName,
          'account_number': accountNumber,
          'currency': currency,
        })
        as Map<String, dynamic>;
  }
}
