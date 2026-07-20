import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository(ref.watch(apiClientProvider));
});

class ProductRepository {
  ProductRepository(this._api);

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> getProducts() async {
    final list = await _api.get('/products') as List;
    return list.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMyProducts() async {
    final list = await _api.get('/products/mine') as List;
    return list.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getProduct(String id) async {
    return await _api.get('/products/$id') as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createProduct({
    required String title,
    String? description,
    required double price,
    required List<String> images,
  }) async {
    return await _api.post('/products', {
          'title': title,
          if (description != null && description.isNotEmpty) 'description': description,
          'price': price,
          'images': images,
        }) as Map<String, dynamic>;
  }

  Future<void> deleteProduct(String id) async {
    await _api.delete('/products/$id');
  }
}
