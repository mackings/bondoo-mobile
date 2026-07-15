import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final storyRepositoryProvider = Provider<StoryRepository>(
  (ref) => StoryRepository(ref.watch(apiClientProvider)),
);

class StoryRepository {
  StoryRepository(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> getStories() async {
    final list = await _api.get('/stories') as List<dynamic>;
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> getMyStory() async {
    final data = await _api.get('/stories/mine');
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> createStory({
    String? text,
    String? imageDataUrl,
  }) async {
    final data = await _api.post('/stories', {
      if (text case final t? when t.isNotEmpty) 'text': t,
      if (imageDataUrl case final url?) 'image_data_url': url,
    });
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> deleteMyStory() async {
    await _api.delete('/stories/mine');
  }

  Future<void> markViewed(String storyId) async {
    await _api.post('/stories/$storyId/view');
  }
}
