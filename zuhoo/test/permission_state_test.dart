import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/core/auth/permission_controller.dart';

/// Permission checks decide what the app shows, so both ways of being wrong
/// matter: hiding a screen someone is entitled to, and offering one the
/// backend will refuse. Neither produces an error message that says so.
void main() {
  group('PermissionState', () {
    const held = PermissionState(
      codes: {'SERVICE_REQUEST_VIEW', 'LEAVE_VIEW'},
      catalog: {'SERVICE_REQUEST_VIEW', 'LEAVE_VIEW', 'PAYROLL_VIEW'},
      loaded: true,
    );

    test('answers a single code', () {
      expect(held.has('SERVICE_REQUEST_VIEW'), isTrue);
      expect(held.has('PAYROLL_VIEW'), isFalse);
    });

    test('no requirement means no gate', () {
      // Deliberate, and matches the Angular service: a screen that declares no
      // required permission is open to anyone signed in. Returning false here
      // would lock every ungated screen in the app.
      expect(held.has(null), isTrue);
      expect(held.has(''), isTrue);
      expect(held.hasAny(null), isTrue);
      expect(held.hasAny(const []), isTrue);
    });

    test('hasAny needs only one of them', () {
      expect(held.hasAny(const ['PAYROLL_VIEW', 'LEAVE_VIEW']), isTrue);
      expect(held.hasAny(const ['PAYROLL_VIEW', 'AUDIT_LOG_VIEW']), isFalse);
    });

    test('hasAll is false until the catalogue has arrived', () {
      // Without the catalogue there is nothing to compare against, and
      // answering "yes, you hold everything" on an empty comparison would hand
      // owner-level UI to whoever asked first.
      const noCatalog = PermissionState(codes: {'A'}, loaded: true);
      expect(noCatalog.hasAll, isFalse);

      const everything = PermissionState(
        codes: {'A', 'B'},
        catalog: {'A', 'B'},
        loaded: true,
      );
      expect(everything.hasAll, isTrue);
      expect(held.hasAll, isFalse);
    });

    test('an unloaded empty set is "unknown", not "denied"', () {
      // The distinction the gate keys on: a set restored from storage, or not
      // yet fetched, must not be read as a refusal.
      const fresh = PermissionState();
      expect(fresh.loaded, isFalse);
      expect(fresh.codes, isEmpty);

      const hydrated = PermissionState(codes: {'LEAVE_VIEW'});
      expect(hydrated.loaded, isFalse,
          reason: 'cached is a guess until the server confirms it');
      expect(hydrated.has('LEAVE_VIEW'), isTrue,
          reason: 'but it is good enough to render with');
    });

    test('copyWith keeps what it is not given', () {
      final confirmed = held.copyWith(loaded: true);
      expect(confirmed.codes, held.codes);
      expect(confirmed.catalog, held.catalog);

      final cleared = held.copyWith(codes: const {});
      expect(cleared.codes, isEmpty);
      expect(cleared.catalog, held.catalog);
    });
  });
}
