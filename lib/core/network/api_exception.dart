import 'dart:async';
import 'dart:io';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

String apiErrorMessage(Object error) {
  if (error is ApiException) return error.message;
  if (error is TimeoutException) {
    return 'The request took too long. Check your connection and try again.';
  }
  if (error is SocketException) {
    return 'Unable to reach the server. Check your internet connection.';
  }
  return error.toString().replaceFirst('Exception: ', '');
}
