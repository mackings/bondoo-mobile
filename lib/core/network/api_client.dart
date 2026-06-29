import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../features/auth/data/auth_repository.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref);
});

class ApiClient {
  ApiClient(this._ref);

  final Ref _ref;
  static const _timeout = Duration(seconds: 60);

  Future<Map<String, String>> _headers() async {
    final token = _ref.read(authControllerProvider).token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path) => Uri.parse('${AppConfig.apiBaseUrl}$path');

  Future<dynamic> get(String path) async {
    return _request(
      method: 'GET',
      uri: _uri(path),
      () async => http.get(_uri(path), headers: await _headers()),
    );
  }

  Future<dynamic> post(String path, [Object? body]) async {
    return _request(
      method: 'POST',
      uri: _uri(path),
      requestBody: body ?? {},
      () async => http.post(
        _uri(path),
        headers: await _headers(),
        body: jsonEncode(body ?? {}),
      ),
    );
  }

  Future<dynamic> postMultipart(
    String path,
    Map<String, String> fields, {
    String? filePath,
    String fileField = 'receipt',
  }) async {
    final uri = _uri(path);
    final headers = await _headers()
      ..remove('Content-Type');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(headers)
      ..fields.addAll(fields);
    if (filePath != null) {
      request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    }
    _logRequest('POST(multipart)', uri, fields);
    try {
      final streamed = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      _logResponse('POST(multipart)', uri, response);
      return _decode(response);
    } on TimeoutException {
      _logFailure('POST(multipart)', uri, 'timeout after ${_timeout.inSeconds}s');
      throw const ApiException('The request took too long. Check your connection.');
    } catch (e) {
      _logFailure('POST(multipart)', uri, '$e');
      if (e is ApiException) rethrow;
      throw ApiException('Upload failed: $e');
    }
  }

  Future<dynamic> patch(String path, Object body) async {
    return _request(
      method: 'PATCH',
      uri: _uri(path),
      requestBody: body,
      () async => http.patch(
        _uri(path),
        headers: await _headers(),
        body: jsonEncode(body),
      ),
    );
  }

  Future<dynamic> delete(String path) async {
    return _request(
      method: 'DELETE',
      uri: _uri(path),
      () async => http.delete(_uri(path), headers: await _headers()),
    );
  }

  Future<dynamic> _request(
    Future<http.Response> Function() send, {
    required String method,
    required Uri uri,
    Object? requestBody,
  }) async {
    _logRequest(method, uri, requestBody);
    try {
      final response = await send().timeout(_timeout);
      _logResponse(method, uri, response);
      if (response.statusCode == 401 &&
          _ref.read(authControllerProvider).token != null) {
        await _ref.read(authControllerProvider.notifier).signOut();
      }
      return _decode(response);
    } on TimeoutException {
      _logFailure(method, uri, 'timeout after ${_timeout.inSeconds}s');
      throw const ApiException(
        'The request took too long. Check your connection and try again.',
      );
    } on http.ClientException {
      _logFailure(method, uri, 'client exception');
      throw const ApiException(
        'Unable to reach the server. Check your connection and try again.',
      );
    }
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        throw ApiException(
          response.statusCode >= 400
              ? 'The server could not process this request.'
              : 'The server returned an invalid response.',
          statusCode: response.statusCode,
        );
      }
    }
    if (response.statusCode >= 400) {
      final message = body is Map
          ? body['error'] ?? response.body
          : response.body;
      throw ApiException(
        '$message'.isEmpty ? 'The request failed.' : '$message',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  void _logRequest(String method, Uri uri, Object? body) {
    if (!kDebugMode) return;
    debugPrint('[API request] $method $uri');
    if (body != null) {
      debugPrint('   request: ${_safeJson(body)}');
    }
  }

  void _logResponse(String method, Uri uri, http.Response response) {
    if (!kDebugMode) return;
    debugPrint('[API response] $method $uri -> ${response.statusCode}');
    debugPrint('   response: ${_trim(response.body)}');
  }

  void _logFailure(String method, Uri uri, String message) {
    if (!kDebugMode) return;
    debugPrint('[API failure] $method $uri -> $message');
  }

  String _safeJson(Object value) {
    try {
      return _trim(jsonEncode(_redact(value)));
    } catch (_) {
      return _trim('$value');
    }
  }

  Object? _redact(Object? value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          '${entry.key}': _sensitive('${entry.key}')
              ? '[REDACTED]'
              : _redact(entry.value),
      };
    }
    if (value is List) return value.map(_redact).toList();
    return value;
  }

  bool _sensitive(String key) {
    final lower = key.toLowerCase();
    return lower.contains('password') ||
        lower.contains('token') ||
        lower.contains('audio_data_url') ||
        lower.contains('image_data_url') ||
        lower.contains('voice_data_url') ||
        lower == 'authorization';
  }

  String _trim(String value) {
    const max = 2000;
    if (value.length <= max) return value;
    return '${value.substring(0, max)}... [trimmed ${value.length - max} chars]';
  }
}
