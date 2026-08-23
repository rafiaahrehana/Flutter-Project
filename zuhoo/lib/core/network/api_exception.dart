import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// A backend or transport failure, already reduced to something showable.
///
/// Screens catch this rather than [DioException] so no widget has to know how
/// the API reports errors.
class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.cause,
    this.fromServer = false,
  });

  final String message;
  final int? statusCode;
  final Object? cause;

  /// True when [message] is the backend's own words rather than one this
  /// class invented from the status code.
  ///
  /// The difference matters where a status is ambiguous: a 401 is an expired
  /// session almost everywhere and refused credentials on the login screen, so
  /// the login flow substitutes its own wording — but only over a message that
  /// was invented here. A real message from the server ("Your account has not
  /// been verified") is always more useful and must survive.
  final bool fromServer;

  /// 401/403 mean "not you / not allowed" rather than "broken", and several
  /// screens treat them as an empty state instead of an error.
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  /// No response at all — DNS, refused connection, timeout, airplane mode.
  bool get isNetwork => statusCode == null;

  @override
  String toString() => 'ApiException($statusCode): $message';

  static ApiException from(Object error, [StackTrace? _]) {
    if (error is ApiException) return error;
    if (error is! DioException) {
      return ApiException('Something went wrong. Please try again.', cause: error);
    }

    final status = error.response?.statusCode;
    final fromBody = _messageFromBody(error.response?.data);
    if (fromBody != null) {
      return ApiException(
        fromBody,
        statusCode: status,
        cause: error,
        fromServer: true,
      );
    }

    return ApiException(_fallbackFor(error, status), statusCode: status, cause: error);
  }

  /// Port of Angular's `extractErrorMessage`.
  ///
  /// Several endpoints declare `ResponseEntity<String>` and are requested with
  /// a plain response type, which means their *error* bodies arrive as a raw
  /// string holding JSON rather than a decoded map. Reading `['message']` off
  /// that returns nothing, so try decoding first.
  static String? _messageFromBody(Object? data) {
    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('{')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) return _pick(decoded);
        } catch (_) {
          // Not actually JSON — fall through and show the raw string.
        }
      }
      return trimmed;
    }
    if (data is Map) return _pick(data);
    return null;
  }

  static String? _pick(Map<dynamic, dynamic> map) {
    for (final key in const ['message', 'error', 'detail']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static String _fallbackFor(DioException error, int? status) {
    switch (status) {
      case 400:
        return 'That request was not valid. Please check the details and try again.';
      case 401:
        return 'Your session has expired. Please sign in again.';
      case 403:
        return 'You do not have permission to do that.';
      case 404:
        return 'Not found.';
      case 409:
        return 'That conflicts with something that already exists.';
      case 500:
      case 502:
      case 503:
        return 'The server had a problem. Please try again in a moment.';
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The server took too long to respond.';
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.connectionError:
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return 'Could not reach the server. Check your connection and that the '
              'backend is running.';
        }
        return 'Could not reach the server. Check your connection.';
      case DioExceptionType.badCertificate:
        return 'The server\'s security certificate was rejected.';
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
        return 'Something went wrong. Please try again.';
    }
  }
}
