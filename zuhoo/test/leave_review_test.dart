import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/leave/leave_models.dart';

/// Approving leave moves real entitlement around, and the backend refuses a
/// malformed review outright. These pin the two rules that produce a 400 if
/// broken, and the one that decides whether the buttons appear at all.
void main() {
  group('ReviewLeaveRequest', () {
    test('an approval carries no reason', () {
      final json = const ReviewLeaveRequest.approve().toJson();
      expect(json['status'], LeaveStatus.approved);
      expect(json.containsKey('rejectionReason'), isFalse);
    });

    test('a rejection carries its reason, trimmed', () {
      // The backend rejects a blank reason with a 400, so this is not merely
      // good manners — an unexplained refusal will not even be recorded.
      final json =
          const ReviewLeaveRequest.reject('  Cover is already thin  ').toJson();
      expect(json['status'], LeaveStatus.rejected);
      expect(json['rejectionReason'], 'Cover is already thin');
    });

    test('a whitespace-only reason is omitted rather than sent', () {
      // Sent as a blank string it would fail server-side anyway; omitting it
      // means the same 400, but the form catches it before the round trip.
      final json = const ReviewLeaveRequest.reject('   ').toJson();
      expect(json.containsKey('rejectionReason'), isFalse);
    });
  });

  group('LeaveRequest', () {
    LeaveRequest request({String status = LeaveStatus.pending}) => LeaveRequest(
          id: 1,
          leaveType: 'ANNUAL',
          startDate: '2026-09-01',
          endDate: '2026-09-03',
          totalDays: 3,
          status: status,
          employeeId: 12,
          employeeName: 'Rehana Akter',
        );

    test('only a pending request can be acted on', () {
      // The backend throws "Only PENDING leave requests can be reviewed", so
      // offering the buttons on anything else guarantees an error.
      expect(request().canCancel, isTrue);
      expect(request(status: LeaveStatus.approved).canCancel, isFalse);
      expect(request(status: LeaveStatus.rejected).canCancel, isFalse);
      expect(request(status: LeaveStatus.cancelled).canCancel, isFalse);
    });

    test('the reviewer queue needs a name, not an id', () {
      final parsed = LeaveRequest.fromJson(const {
        'id': 4,
        'leaveType': 'SICK',
        'startDate': '2026-09-01',
        'endDate': '2026-09-01',
        'totalDays': 1,
        'status': 'PENDING',
        'employeeId': 12,
        'employeeName': 'Rehana Akter',
      });
      expect(parsed.employeeName, 'Rehana Akter');
      expect(parsed.totalDays, 1.0);
    });

    test('a personal-list row without a name still parses', () {
      // `/hr/leaves/my` omits the name — you know who you are.
      final parsed = LeaveRequest.fromJson(const {'id': 4, 'employeeId': 12});
      expect(parsed.employeeName, isNull);
      expect(parsed.status, LeaveStatus.pending);
    });
  });

  group('LeavePermissions', () {
    test('seeing the queue and acting on it are different codes', () {
      // The review endpoint checks LEAVE_APPROVE for *both* decisions, so a
      // LEAVE_REJECT-only reviewer can open the queue and nothing more. The
      // screen gates the list and the buttons separately for that reason.
      expect(LeavePermissions.approve, 'LEAVE_APPROVE');
      expect(LeavePermissions.reject, 'LEAVE_REJECT');
      expect(LeavePermissions.approve, isNot(LeavePermissions.reject));
    });
  });
}
