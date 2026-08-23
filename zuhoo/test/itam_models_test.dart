import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/itam/itam_models.dart';

/// The three ITAM concerns each have a rule that decides what the screen
/// offers: whether a machine can be acted on, whether a licence has room, and
/// whether an offboarding is actually late.
void main() {
  group('Asset actionability', () {
    Asset withStatus(String status) => Asset.fromJson({
          'id': 1,
          'name': 'ThinkPad X1',
          'status': status,
        });

    test('a disposed asset offers nothing', () {
      final disposed = withStatus(AssetStatus.disposed);

      expect(disposed.isActionable, isFalse);
      expect(
        disposed.isAvailable,
        isFalse,
        reason: 'disposed is not a kind of available — offering Assign here '
            'would put a scrapped machine back into circulation',
      );
    });

    test('every other status can still be acted on', () {
      for (final status in [
        AssetStatus.available,
        AssetStatus.assigned,
        AssetStatus.underMaintenance,
      ]) {
        expect(withStatus(status).isActionable, isTrue, reason: status);
      }
    });

    test('an unknown status defaults to available rather than blocking', () {
      // A status this build has not heard of should not lock the screen; the
      // backend rejects an invalid transition anyway.
      expect(withStatus('SOMETHING_NEW').isActionable, isTrue);
    });
  });

  group('Asset labels', () {
    test('joins whichever of brand and model exist', () {
      Asset make({String? brand, String? model}) => Asset.fromJson({
            'id': 1,
            'name': 'Laptop',
            'status': 'AVAILABLE',
            'brand': brand,
            'model': model,
          });

      expect(make(brand: 'Dell', model: 'Latitude').makeModel, 'Dell · Latitude');
      expect(make(brand: 'Dell').makeModel, 'Dell');
      expect(make(model: 'Latitude').makeModel, 'Latitude');
      expect(make().makeModel, isNull);
    });

    test('prefers the asset tag over the serial number', () {
      // The tag is what is stencilled on the case; the serial usually needs
      // the machine turned over.
      final tagged = Asset.fromJson({
        'id': 1,
        'name': 'Laptop',
        'status': 'AVAILABLE',
        'assetTag': 'IT-0042',
        'serialNumber': 'SN99887766',
      });
      final untagged = Asset.fromJson({
        'id': 1,
        'name': 'Laptop',
        'status': 'AVAILABLE',
        'serialNumber': 'SN99887766',
      });

      expect(tagged.identifier, 'IT-0042');
      expect(untagged.identifier, 'SN99887766');
    });
  });

  group('SoftwareLicense seats', () {
    SoftwareLicense seats({required int total, required int used}) =>
        SoftwareLicense.fromJson({
          'id': 1,
          'softwareName': 'Figma',
          'totalSeatsLicensed': total,
          'seatsUsed': used,
          'seatsAvailable': total - used,
        });

    test('reports room while seats remain', () {
      final license = seats(total: 10, used: 4);

      expect(license.hasSeatsFree, isTrue);
      expect(license.isFull, isFalse);
      expect(license.seatsLabel, '4 of 10 seats');
    });

    test('full is not the same as over-allocated', () {
      expect(seats(total: 10, used: 10).isFull, isTrue);
      expect(seats(total: 10, used: 10).isOverAllocated, isFalse);
      expect(seats(total: 10, used: 12).isOverAllocated, isTrue);
    });

    test('the seat bar never overflows when over-allocated', () {
      // The bar is clamped; the count beside it tells the real story.
      expect(seats(total: 10, used: 12).seatFraction, 1.0);
      expect(seats(total: 10, used: 5).seatFraction, 0.5);
    });

    test('an unlimited or unset licence does not divide by zero', () {
      final unset = seats(total: 0, used: 0);

      expect(unset.seatFraction, 0);
      expect(unset.isFull, isFalse);
      expect(unset.isOverAllocated, isFalse);
    });

    test('expiry flags come from the server, not re-derived here', () {
      final license = SoftwareLicense.fromJson({
        'id': 1,
        'softwareName': 'Figma',
        'expiringSoon': true,
        'expired': false,
        'daysUntilExpiry': 12,
      });

      expect(license.expiringSoon, isTrue);
      expect(license.expired, isFalse);
      expect(license.daysUntilExpiry, 12);
    });
  });

  group('OffboardingChecklist', () {
    Map<String, dynamic> checklist({
      bool hardware = false,
      bool licenses = false,
      bool access = false,
      bool data = false,
      bool interview = false,
      bool completed = false,
      String? target,
    }) =>
        {
          'id': 1,
          'employeeId': 7,
          'employeeName': 'Dana Rahman',
          'completed': completed,
          'completionPercentage': 0,
          'hardwareCollected': hardware,
          'licensesRevoked': licenses,
          'accessRevoked': access,
          'dataHandedOver': data,
          'exitInterviewCompleted': interview,
          'targetCompletionDate': target,
        };

    test('exposes the five boolean columns as one ordered list', () {
      final list = OffboardingChecklist.fromJson(checklist());

      expect(list.steps, hasLength(5));
      expect(
        list.steps.map((s) => s.path).toList(),
        [
          'hardware-collected',
          'licenses-revoked',
          'access-revoked',
          'data-handed-over',
          'exit-interview',
        ],
        reason: 'each step PATCHes its own path; a wrong one silently ticks '
            'off the wrong task',
      );
    });

    test('counts the steps that are done', () {
      expect(OffboardingChecklist.fromJson(checklist()).stepsDone, 0);
      expect(
        OffboardingChecklist.fromJson(
          checklist(hardware: true, access: true),
        ).stepsDone,
        2,
      );
    });

    test('is overdue only when late and unfinished', () {
      final past = DateTime.now()
          .subtract(const Duration(days: 3))
          .toIso8601String()
          .split('T')
          .first;
      final future = DateTime.now()
          .add(const Duration(days: 3))
          .toIso8601String()
          .split('T')
          .first;

      expect(
        OffboardingChecklist.fromJson(checklist(target: past)).isOverdue,
        isTrue,
      );
      expect(
        OffboardingChecklist.fromJson(checklist(target: future)).isOverdue,
        isFalse,
      );
      expect(
        OffboardingChecklist.fromJson(
          checklist(target: past, completed: true),
        ).isOverdue,
        isFalse,
        reason: 'a finished checklist cannot be late',
      );
      expect(
        OffboardingChecklist.fromJson(checklist()).isOverdue,
        isFalse,
        reason: 'no target date means nothing to be late against',
      );
    });

    test('falls back to an id when the name is missing', () {
      final anonymous = OffboardingChecklist.fromJson({
        'id': 1,
        'employeeId': 7,
      });

      expect(anonymous.personLabel, 'Employee #7');
    });
  });
}
