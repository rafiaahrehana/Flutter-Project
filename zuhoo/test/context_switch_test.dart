import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/platform/context_models.dart';

/// A context switch is a record that support staff looked inside a customer's
/// account. It grants nothing, so the value of the feature is entirely in the
/// record being accurate and readable — which is what these pin down.
void main() {
  SupportContextSwitch build({
    String? inTime,
    String? outTime,
    bool active = true,
    String? purpose,
    String? company,
    String? agent,
  }) =>
      SupportContextSwitch(
        id: 1,
        supportAgentId: 7,
        viewedCompanyId: 4,
        stillActive: active,
        switchedInTime: inTime,
        switchedOutTime: outTime,
        purpose: purpose,
        viewedCompanyName: company,
        supportAgentName: agent,
      );

  String ago(Duration span) =>
      DateTime.now().subtract(span).toIso8601String();

  group('role sets', () {
    test('reviewing is narrower than switching', () {
      // The screen leans on this: one role check gates the tab, because
      // everyone who may review may also switch.
      for (final role in contextSwitchReviewRoles) {
        expect(
          contextSwitchRoles,
          contains(role),
          reason: '$role can review but would be locked out of the tab',
        );
      }
    });

    test('a support agent may switch but never review', () {
      expect(contextSwitchRoles, contains('SUPPORT_AGENT'));
      expect(
        contextSwitchReviewRoles,
        isNot(contains('SUPPORT_AGENT')),
        reason: 'offering an agent the history would 403 for the role that '
            'uses this feature most',
      );
    });

    test('SYSTEM_ADMIN cannot context switch even though it may impersonate', () {
      // The two features look alike and their role lists differ; sharing one
      // list between them would silently grant or deny the wrong people.
      expect(contextSwitchRoles, isNot(contains('SYSTEM_ADMIN')));
    });
  });

  group('elapsed', () {
    test('an open switch measures against now', () {
      final open = build(inTime: ago(const Duration(hours: 2, minutes: 10)));

      expect(open.elapsedLabel, '2h 10m');
    });

    test('a closed switch measures between its own stamps', () {
      final closed = build(
        active: false,
        inTime: '2026-08-20T09:00:00',
        outTime: '2026-08-20T09:45:00',
      );

      expect(closed.elapsedLabel, '45m');
    });

    test('whole hours drop the minutes', () {
      final closed = build(
        active: false,
        inTime: '2026-08-20T09:00:00',
        outTime: '2026-08-20T12:00:00',
      );

      expect(closed.elapsedLabel, '3h');
    });

    test('under a minute reads as just now, not 0m', () {
      expect(build(inTime: ago(const Duration(seconds: 20))).elapsedLabel,
          'just now');
    });

    test('an unreadable stamp yields no duration rather than a wrong one', () {
      expect(build(inTime: null).elapsed, isNull);
      expect(build(inTime: 'not-a-date').elapsedLabel, isNull);
      expect(
        build(active: false, inTime: '2026-08-20T09:00:00', outTime: null)
            .elapsed,
        isNull,
        reason: 'a closed switch with no end stamp cannot be measured',
      );
    });

    test('clock skew never produces a negative duration', () {
      final skewed = build(inTime: DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String());

      expect(skewed.elapsed, Duration.zero);
    });
  });

  group('looksForgotten', () {
    test('flags an open switch left running past a shift', () {
      expect(build(inTime: ago(const Duration(hours: 9))).looksForgotten, isTrue);
    });

    test('leaves a normal working session alone', () {
      expect(build(inTime: ago(const Duration(hours: 3))).looksForgotten, isFalse);
    });

    test('never flags a switch that was properly ended', () {
      final closed = build(
        active: false,
        inTime: '2026-08-20T01:00:00',
        outTime: '2026-08-20T23:00:00',
      );

      expect(
        closed.looksForgotten,
        isFalse,
        reason: 'a long session that was ended is history, not a loose end',
      );
    });
  });

  group('labels', () {
    test('falls back to ids rather than showing a blank row', () {
      final bare = build();

      expect(bare.companyLabel, 'Company #4');
      expect(bare.agentLabel, 'Agent #7');
    });

    test('treats whitespace-only names as absent', () {
      final blank = build(company: '   ', agent: '  ');

      expect(blank.companyLabel, 'Company #4');
      expect(blank.agentLabel, 'Agent #7');
    });

    test('a whitespace-only purpose does not count as one', () {
      expect(build(purpose: '   ').hasPurpose, isFalse);
      expect(build(purpose: 'Ticket #482').hasPurpose, isTrue);
    });
  });

  group('fromJson', () {
    test('reads the response the controller actually sends', () {
      final parsed = SupportContextSwitch.fromJson(const {
        'id': 12,
        'supportAgentId': 7,
        'supportAgentName': 'Dana Ops',
        'viewedCompanyId': 4,
        'viewedCompanyName': 'Acme Ltd',
        'switchedInTime': '2026-08-20T09:00:00',
        'switchedOutTime': null,
        'purpose': 'Ticket #482',
        'ipAddress': '10.0.0.4',
        'userAgent': 'Dart/3.12',
        'stillActive': true,
      });

      expect(parsed.id, 12);
      expect(parsed.agentLabel, 'Dana Ops');
      expect(parsed.companyLabel, 'Acme Ltd');
      expect(parsed.stillActive, isTrue);
      expect(parsed.ipAddress, '10.0.0.4');
    });

    test('a missing stillActive is treated as closed, not open', () {
      // Erring the other way would invent an open session on the live board,
      // and a "currently viewing" row is believed by whoever reads it.
      expect(SupportContextSwitch.fromJson(const {'id': 1}).stillActive, isFalse);
    });
  });
}
