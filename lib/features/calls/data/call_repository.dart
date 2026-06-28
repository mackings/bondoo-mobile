import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final callRepositoryProvider = Provider<CallRepository>((ref) {
  return CallRepository(ref.watch(apiClientProvider));
});

class CallRepository {
  CallRepository(this._api);

  final ApiClient _api;

  Future<Map<String, dynamic>> invite({
    required String conversationId,
    required bool video,
  }) async {
    return await _api.post('/calls/invite', {
          'conversation_id': conversationId,
          'kind': video ? 'video' : 'voice',
        })
        as Map<String, dynamic>;
  }

  Future<List<dynamic>> pending() async {
    return await _api.get('/calls/pending') as List<dynamic>;
  }

  Future<Map<String, dynamic>> getCall(String callId) async {
    return await _api.get('/calls/$callId') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> accept(String callId) async {
    return await _api.post('/calls/$callId/accept') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> decline(String callId) async {
    return await _api.post('/calls/$callId/decline') as Map<String, dynamic>;
  }

  Future<void> end(String callId) async {
    await _api.post('/calls/$callId/end');
  }

  Future<List<dynamic>> history() async {
    return await _api.get('/calls/history') as List<dynamic>;
  }
}
