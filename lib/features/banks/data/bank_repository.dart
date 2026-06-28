import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final bankRepositoryProvider = Provider<BankRepository>((ref) {
  return BankRepository(ref.watch(apiClientProvider));
});

class BankInfo {
  final String name;
  final String code;

  const BankInfo({required this.name, required this.code});

  factory BankInfo.fromJson(Map<String, dynamic> json) =>
      BankInfo(name: '${json['name']}', code: '${json['code']}');
}

class VerifiedAccount {
  final String accountName;
  final String accountNumber;
  final String bankCode;

  const VerifiedAccount({
    required this.accountName,
    required this.accountNumber,
    required this.bankCode,
  });
}

class BankRepository {
  BankRepository(this._api);

  final ApiClient _api;

  // Cache per currency so we don't re-fetch on every keystroke
  final _cache = <String, List<BankInfo>>{};

  Future<List<BankInfo>> fetchBanks(String currency) async {
    final key = currency.toUpperCase();
    if (_cache.containsKey(key)) return _cache[key]!;

    final data = await _api.get('/banks?currency=$key') as Map<String, dynamic>;
    final list = (data['banks'] as List)
        .map((b) => BankInfo.fromJson(b as Map<String, dynamic>))
        .toList();
    _cache[key] = list;
    return list;
  }

  Future<VerifiedAccount> verifyAccount({
    required String accountNumber,
    required String bankCode,
  }) async {
    final data = await _api.get(
      '/banks/verify?account_number=${Uri.encodeComponent(accountNumber)}&bank_code=${Uri.encodeComponent(bankCode)}',
    ) as Map<String, dynamic>;
    return VerifiedAccount(
      accountName: '${data['account_name']}',
      accountNumber: '${data['account_number']}',
      bankCode: bankCode,
    );
  }
}
