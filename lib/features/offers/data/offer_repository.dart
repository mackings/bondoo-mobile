import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';

final offerRepositoryProvider = Provider<OfferRepository>((ref) {
  return OfferRepository(ref.watch(apiClientProvider));
});

class OfferRepository {
  OfferRepository(this._api);

  final ApiClient _api;

  Future<List<dynamic>> list({
    String? coin,
    String? side,
    bool mine = false,
  }) async {
    final params = <String, String>{
      if (coin != null && coin != 'All') 'coin': coin,
      if (side != null && side != 'all') 'side': side,
      if (mine) 'mine': 'true',
    };
    final query = params.entries
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    return await _api.get('/offers${query.isEmpty ? '' : '?$query'}')
        as List<dynamic>;
  }

  Future<Map<String, dynamic>> rates({String localCurrency = 'NGN'}) async {
    try {
      return await _api.get(
            '/rates?local_currency=${Uri.encodeQueryComponent(localCurrency)}',
          )
          as Map<String, dynamic>;
    } catch (_) {
      return _directRates(localCurrency: localCurrency);
    }
  }

  Future<Map<String, dynamic>> _directRates({
    required String localCurrency,
  }) async {
    final local = localCurrency.toLowerCase();
    final uri = Uri.https('api.coingecko.com', '/api/v3/simple/price', {
      'ids': 'bitcoin,ethereum,usd-coin,tether',
      'vs_currencies': 'usd,$local',
      'include_24hr_change': 'true',
    });
    if (kDebugMode) {
      debugPrint('[API request] GET $uri');
    }
    final response = await http
        .get(
          uri,
          headers: const {
            'accept': 'application/json',
            'user-agent': 'bondoo-mobile/1.0',
          },
        )
        .timeout(const Duration(seconds: 20));
    if (kDebugMode) {
      debugPrint('[API response] GET $uri -> ${response.statusCode}');
      debugPrint('   response: ${_trimLog(response.body)}');
    }
    if (response.statusCode >= 400) {
      throw Exception('Unable to load global market rates');
    }
    final raw = jsonDecode(response.body) as Map<String, dynamic>;
    final ids = {
      'BTC': 'bitcoin',
      'ETH': 'ethereum',
      'USDC': 'usd-coin',
      'USDT': 'tether',
    };
    return {
      'source': 'coingecko-direct',
      'local_currency': localCurrency.toUpperCase(),
      'updated_at': DateTime.now().toIso8601String(),
      'coins': [
        for (final entry in ids.entries)
          {
            'coin': entry.key,
            'usd': raw[entry.value]?['usd'],
            'local_currency': localCurrency.toUpperCase(),
            'local': raw[entry.value]?[local],
            'usd_24h_change': raw[entry.value]?['usd_24h_change'],
            'local_24h_change': raw[entry.value]?['${local}_24h_change'],
          },
      ],
    };
  }

  Future<Map<String, dynamic>> create({
    required String side,
    required String coin,
    required String fiatCurrency,
    required double cryptoAmount,
    required double rate,
    required double minFiatAmount,
    required double maxFiatAmount,
    required String paymentMethod,
    required String terms,
  }) async {
    return await _api.post('/offers', {
          'side': side,
          'coin': coin,
          'fiat_currency': fiatCurrency,
          'crypto_amount': cryptoAmount,
          'rate': rate,
          'min_fiat_amount': minFiatAmount,
          'max_fiat_amount': maxFiatAmount,
          'payment_method': paymentMethod,
          'terms': terms,
        })
        as Map<String, dynamic>;
  }

  Future<String> openChat(String offerId) async {
    final response = await _api.post('/chat/offers/$offerId/open') as Map;
    return response['conversation_id'] as String;
  }
}

String _trimLog(String value) {
  const max = 2000;
  if (value.length <= max) return value;
  return '${value.substring(0, max)}... [trimmed ${value.length - max} chars]';
}
