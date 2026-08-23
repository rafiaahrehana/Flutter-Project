import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/network/api_exception.dart';

/// The backend reports the same failure in several encodings depending on
/// whether the endpoint returns JSON or `ResponseEntity<String>`. Getting this
/// wrong does not crash anything — it just replaces every real explanation
/// ("This leave overlaps an approved request") with a generic apology, which
/// is a far harder bug to notice.
void main() {
  DioException error({int? status, Object? data}) {
    final options = RequestOptions(path: '/hr/leaves');
    return DioException(
      requestOptions: options,
      type: status == null
          ? DioExceptionType.connectionError
          : DioExceptionType.badResponse,
      response: status == null
          ? null
          : Response<dynamic>(
              requestOptions: options,
              statusCode: status,
              data: data,
            ),
    );
  }

  group('ApiException.from', () {
    test('prefers the message from a JSON body', () {
      final e = ApiException.from(
        error(status: 400, data: {'message': 'Leave dates overlap.'}),
      );
      expect(e.message, 'Leave dates overlap.');
      expect(e.statusCode, 400);
    });

    test('parses a JSON body that arrived as a plain string', () {
      // text/plain endpoints deliver their *error* body undecoded. Reading
      // ['message'] off this without decoding first returns nothing.
      final e = ApiException.from(
        error(status: 409, data: '{"message":"Already checked in today."}'),
      );
      expect(e.message, 'Already checked in today.');
    });

    test('uses a genuine plain-text body as-is', () {
      final e = ApiException.from(
        error(status: 400, data: 'Reset code has expired'),
      );
      expect(e.message, 'Reset code has expired');
    });

    test('falls back to the "error" key when there is no message', () {
      final e = ApiException.from(error(status: 403, data: {'error': 'Forbidden'}));
      expect(e.message, 'Forbidden');
    });

    test('maps a bare status to something a person can act on', () {
      expect(ApiException.from(error(status: 401)).message, contains('session'));
      expect(
        ApiException.from(error(status: 403)).message,
        contains('permission'),
      );
      expect(ApiException.from(error(status: 404)).message, 'Not found.');
    });

    test('explains an unreachable server rather than a Dio type name', () {
      final e = ApiException.from(error());
      expect(e.isNetwork, isTrue);
      expect(e.message, contains('reach the server'));
      expect(e.message, isNot(contains('DioException')));
    });

    test('classifies statuses for callers that branch on them', () {
      expect(ApiException.from(error(status: 401)).isUnauthorized, isTrue);
      expect(ApiException.from(error(status: 403)).isForbidden, isTrue);
      expect(ApiException.from(error(status: 404)).isNotFound, isTrue);
    });

    test('passes an ApiException straight through', () {
      const original = ApiException('Already reduced', statusCode: 418);
      expect(identical(ApiException.from(original), original), isTrue);
    });

    test('flags whether the message came from the server', () {
      // The login flow substitutes its own wording for a bare 401 but must not
      // overwrite a real explanation from the backend.
      expect(
        ApiException.from(error(status: 401, data: {'message': 'Account not verified.'})).fromServer,
        isTrue,
      );
      expect(ApiException.from(error(status: 401)).fromServer, isFalse);
      expect(ApiException.from(error()).fromServer, isFalse);
    });

    test('handles a non-Dio error without leaking the type', () {
      final e = ApiException.from(FormatException('bad json'));
      expect(e.message, 'Something went wrong. Please try again.');
      expect(e.isNetwork, isTrue);
    });
  });
}
