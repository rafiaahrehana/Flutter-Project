import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/requests/request_models.dart';

/// The derived getters on [ServiceRequest] decide what the UI offers: whether a
/// Withdraw button appears, whether a progress bar is drawn, whether a
/// quotation banner shows. Each is a small rule that is easy to get backwards
/// and produces no error when it is — just a button that should not be there,
/// or one that should be and is not.
void main() {
  ServiceRequest build({
    String status = RequestStatus.pending,
    int taskCount = 0,
    int completedTaskCount = 0,
    bool permanentlyClosed = false,
    double? quotationAmount,
    String? quotationStatus,
  }) =>
      ServiceRequest(
        id: 1,
        title: 'Trade licence renewal',
        status: status,
        priority: 'NORMAL',
        createdAt: '2026-08-01T10:00:00',
        taskCount: taskCount,
        completedTaskCount: completedTaskCount,
        permanentlyClosed: permanentlyClosed,
        quotationAmount: quotationAmount,
        quotationStatus: quotationStatus,
      );

  group('ServiceRequest', () {
    test('open means anything not completed, rejected or cancelled', () {
      expect(build(status: RequestStatus.inProgress).isOpen, isTrue);
      expect(build(status: RequestStatus.waitingClient).isOpen, isTrue);
      expect(build(status: RequestStatus.completed).isOpen, isFalse);
      expect(build(status: RequestStatus.rejected).isOpen, isFalse);
      expect(build(status: RequestStatus.cancelled).isOpen, isFalse);
    });

    test('an unknown status counts as open rather than silently closed', () {
      // New statuses get added server-side. Treating one we do not recognise as
      // closed would hide a live request from the person who raised it.
      expect(build(status: 'SOME_NEW_STATUS').isOpen, isTrue);
    });

    test('only an open, not-permanently-closed request can be withdrawn', () {
      expect(build(status: RequestStatus.pending).canCancel, isTrue);
      expect(build(status: RequestStatus.completed).canCancel, isFalse);
      expect(
        build(status: RequestStatus.pending, permanentlyClosed: true).canCancel,
        isFalse,
      );
    });

    test('task progress is null with no tasks, not zero', () {
      // A bar at 0% reads as "nothing done yet"; no bar at all reads as "this
      // was never broken into tasks". They are different facts.
      expect(build().taskProgress, isNull);
      expect(build(taskCount: 4).taskProgress, 0.0);
      expect(build(taskCount: 4, completedTaskCount: 1).taskProgress, 0.25);
      expect(build(taskCount: 4, completedTaskCount: 4).taskProgress, 1.0);
    });

    test('task progress cannot exceed one', () {
      // Defensive: a stale completed count must not overflow the bar.
      expect(build(taskCount: 2, completedTaskCount: 5).taskProgress, 1.0);
    });

    test('a quotation awaits a decision only while it is pending', () {
      expect(build().hasQuotation, isFalse);
      expect(build().quotationAwaitsDecision, isFalse);

      expect(build(quotationAmount: 5000).quotationAwaitsDecision, isTrue);
      expect(
        build(quotationAmount: 5000, quotationStatus: 'PENDING')
            .quotationAwaitsDecision,
        isTrue,
      );
      expect(
        build(quotationAmount: 5000, quotationStatus: 'ACCEPTED')
            .quotationAwaitsDecision,
        isFalse,
      );
      expect(
        build(quotationAmount: 5000, quotationStatus: 'EXPIRED')
            .quotationAwaitsDecision,
        isFalse,
      );
    });

    test('parses the fields the screens actually read', () {
      final request = ServiceRequest.fromJson(const {
        'id': 42,
        'title': 'Company registration',
        'status': 'IN_PROGRESS',
        'priority': 'HIGH',
        'createdAt': '2026-08-01T10:00:00',
        'slaBreach': true,
        'taskCount': 3,
        'completedTaskCount': 2,
        'assignedEmployeeName': 'Tanvir',
        'quotationAmount': 12500.5,
        'agreedPrice': 12000,
      });

      expect(request.id, 42);
      expect(request.slaBreach, isTrue);
      expect(request.taskProgress, closeTo(0.666, 0.01));
      expect(request.assignedEmployeeName, 'Tanvir');
      expect(request.quotationAmount, 12500.5);
      // Sent as an int by the backend; must still land as a double.
      expect(request.agreedPrice, 12000.0);
    });

    test('survives a response missing everything optional', () {
      final request = ServiceRequest.fromJson(const {});

      expect(request.id, 0);
      expect(request.title, '');
      expect(request.status, RequestStatus.pending);
      expect(request.slaBreach, isFalse);
      expect(request.taskProgress, isNull);
    });
  });

  group('CreateServiceRequest', () {
    test('always sends the payment choice the backend requires', () {
      final json = const CreateServiceRequest(
        title: '  Renew licence  ',
        hubServiceId: 7,
      ).toJson();

      expect(json['paymentChoice'], 'PAY_LATER');
      expect(json['title'], 'Renew licence', reason: 'trimmed before sending');
      expect(json['hubServiceId'], 7);
    });

    test('omits empty optional fields rather than sending blanks', () {
      final json = const CreateServiceRequest(
        title: 'Renew licence',
        hubServiceId: 7,
        description: '   ',
      ).toJson();

      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('priority'), isFalse);
    });
  });

  group('StageApproval', () {
    test('is pending until it has been decided', () {
      final approval = StageApproval.fromJson(const {
        'id': 3,
        'status': 'PENDING',
        'serviceRequestId': 42,
        'createdAt': '2026-08-01T10:00:00',
      });
      expect(approval.isPending, isTrue);
      expect(approval.serviceRequestId, 42);
    });
  });

  group('RequestComment', () {
    test('an internal note is identified so it can be labelled', () {
      // Mislabelling this is how a staff-only note gets read out to a client.
      expect(
        RequestComment.fromJson(const {'id': 1, 'visibility': 'INTERNAL'})
            .isInternal,
        isTrue,
      );
      expect(
        RequestComment.fromJson(const {'id': 1, 'visibility': 'PUBLIC'})
            .isInternal,
        isFalse,
      );
      expect(RequestComment.fromJson(const {'id': 1}).isInternal, isFalse);
    });
  });
}
