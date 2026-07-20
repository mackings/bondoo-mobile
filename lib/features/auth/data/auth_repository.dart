import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) {
    final controller = AuthController();
    controller.restore();
    return controller;
  },
);

class AuthState {
  const AuthState({this.token, this.user, this.restoring = false});

  final String? token;
  final Map<String, dynamic>? user;
  final bool restoring;

  bool get isAuthenticated => token != null && user != null;

  AuthState copyWith({
    String? token,
    Map<String, dynamic>? user,
    bool? restoring,
    bool clear = false,
  }) {
    if (clear) return const AuthState();
    return AuthState(
      token: token ?? this.token,
      user: user ?? this.user,
      restoring: restoring ?? this.restoring,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  AuthController() : super(const AuthState(restoring: true));

  static const _tokenKey = 'bondoo.auth.token';
  static const _userKey = 'bondoo.auth.user';
  static const _timeout = Duration(seconds: 60);

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final userJson = prefs.getString(_userKey);
      if (token == null || userJson == null) {
        state = const AuthState();
        return;
      }
      // Load cache but keep restoring=true while we refresh from the server.
      // This ensures HomeShell always sees up-to-date wallet/profile data.
      state = AuthState(
        token: token,
        user: jsonDecode(userJson) as Map<String, dynamic>,
        restoring: true,
      );
      try {
        await refreshMe();
      } catch (_) {
        // Server unreachable — fall back to cached user and continue.
        state = state.copyWith(restoring: false);
      }
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userKey);
      state = const AuthState();
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await _auth('/auth/signin', {'email': email, 'password': password});
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) async {
    return await _auth('/auth/signup', {
      'email': email,
      'password': password,
      'display_name': displayName,
      'phone': phone,
    });
  }

  Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async {
    return await _publicPost('/auth/password/forgot', {'email': email});
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String password,
  }) async {
    return await _publicPost('/auth/password/reset', {
      'email': email,
      'code': code,
      'password': password,
    });
  }

  Future<void> refreshMe() async {
    final token = state.token;
    if (token == null) return;
    final uri = Uri.parse('${AppConfig.apiBaseUrl}/auth/me');
    _logAuthRequest('GET', uri);
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(_timeout);
    _logAuthResponse('GET', uri, response);
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400 || decoded is! Map) {
      throw const ApiException('Unable to refresh account.');
    }
    final user = decoded['user'] as Map<String, dynamic>;
    await _persist(token, user);
  }

  Future<Map<String, dynamic>> sendEmailOtp() async {
    return await _authenticatedPost('/me/otp/email/send');
  }

  Future<Map<String, dynamic>> verifyEmailOtp(String code) async {
    final decoded = await _authenticatedPost('/me/otp/email/verify', {
      'code': code,
    });
    await updateUser(decoded);
    return decoded;
  }

  Future<Map<String, dynamic>> _auth(
    String path,
    Map<String, dynamic> body, {
    bool persistSession = true,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    _logAuthRequest('POST', uri, body);
    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      _logAuthResponse('POST', uri, response);
    } on TimeoutException {
      _logAuthFailure('POST', uri, 'timeout after ${_timeout.inSeconds}s');
      throw const ApiException(
        'The request took too long. Check your connection and try again.',
      );
    } on http.ClientException {
      _logAuthFailure('POST', uri, 'client exception');
      throw const ApiException(
        'Unable to reach the server. Check that the API is running and try again.',
      );
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
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
      throw ApiException(
        decoded is Map
            ? '${decoded['error'] ?? 'Authentication failed.'}'
            : 'Authentication failed.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw const ApiException('The server returned an invalid response.');
    }
    final token = decoded['token'] as String;
    final user = decoded['user'] as Map<String, dynamic>;
    if (persistSession) await _persist(token, user);
    return decoded.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _publicPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    _logAuthRequest('POST', uri, body);
    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      _logAuthResponse('POST', uri, response);
    } on TimeoutException {
      _logAuthFailure('POST', uri, 'timeout after ${_timeout.inSeconds}s');
      throw const ApiException(
        'The request took too long. Check your connection and try again.',
      );
    } on http.ClientException {
      _logAuthFailure('POST', uri, 'client exception');
      throw const ApiException(
        'Unable to reach the server. Check that the API is running and try again.',
      );
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
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
      throw ApiException(
        decoded is Map
            ? '${decoded['error'] ?? 'Request failed.'}'
            : 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw const ApiException('The server returned an invalid response.');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> _authenticatedPost(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final token = state.token;
    if (token == null) throw const ApiException('Please sign in again.');

    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    _logAuthRequest('POST', uri, body ?? {});
    late final http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body ?? {}),
          )
          .timeout(_timeout);
      _logAuthResponse('POST', uri, response);
    } on TimeoutException {
      _logAuthFailure('POST', uri, 'timeout after ${_timeout.inSeconds}s');
      throw const ApiException(
        'The request took too long. Check your connection and try again.',
      );
    } on http.ClientException {
      _logAuthFailure('POST', uri, 'client exception');
      throw const ApiException(
        'Unable to reach the server. Check that the API is running and try again.',
      );
    }

    dynamic decoded;
    if (response.body.isNotEmpty) {
      try {
        decoded = jsonDecode(response.body);
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
      throw ApiException(
        decoded is Map
            ? '${decoded['error'] ?? 'Request failed.'}'
            : 'Request failed.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map) {
      throw const ApiException('The server returned an invalid response.');
    }
    return decoded.cast<String, dynamic>();
  }

  Future<void> _persist(String token, Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user));
    state = AuthState(token: token, user: user);
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    state = const AuthState();
  }

  Future<void> updateUser(Map<String, dynamic> user) async {
    final token = state.token;
    if (token == null) return;
    await _persist(token, user);
  }
}

void _logAuthRequest(String method, Uri uri, [Object? body]) {
  if (!kDebugMode) return;
  debugPrint('[API request] $method $uri');
  if (body != null) debugPrint('   request: ${_safeJson(body)}');
}

void _logAuthResponse(String method, Uri uri, http.Response response) {
  if (!kDebugMode) return;
  debugPrint('[API response] $method $uri -> ${response.statusCode}');
  debugPrint('   response: ${_trim(response.body)}');
}

void _logAuthFailure(String method, Uri uri, String message) {
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
      lower == 'authorization';
}

String _trim(String value) {
  const max = 2000;
  if (value.length <= max) return value;
  return '${value.substring(0, max)}... [trimmed ${value.length - max} chars]';
}
