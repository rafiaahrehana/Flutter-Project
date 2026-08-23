import 'package:flutter_test/flutter_test.dart';
import 'package:zuhoo/features/directory/directory_models.dart';

/// The employee endpoint returns far more than a directory needs — pay,
/// allowances, bank details, national and tax ids — for every colleague, in
/// the same payload. The model's job is to be the place that stops.
void main() {
  /// A realistic row, taken from the live response shape.
  Map<String, dynamic> payload({
    String? jobTitle = 'Support Engineer',
    String? designation,
    String? status = 'ACTIVE',
    String? official = 'sumaiya@dhrubotara.example.com',
    String? personal = 'sumaiya.islam@dhrubotara.example.com',
    String? workPhone = '+880 1710-123456',
    String? phone,
  }) =>
      {
        'id': 28,
        'firstName': 'Sumaiya',
        'lastName': 'Islam',
        'employeeNumber': 'DEMO-0010',
        'jobTitle': jobTitle,
        'designationName': designation,
        'departmentId': 26,
        'departmentName': 'Support',
        'email': personal,
        'officialEmail': official,
        'phone': phone,
        'workPhone': workPhone,
        'employmentStatus': status,
        'employmentType': 'FULL_TIME',
        'hireDate': '2024-06-02',
        // Everything below is in the real payload and must not survive parsing.
        'basicSalary': 38000.00,
        'houseRent': 15200.00,
        'medicalAllowance': 3800.00,
        'transportAllowance': 3800.00,
        'billableRate': 900.00,
        'bankAccountNumber': '1234567890',
        'bankName': 'Demo Bank',
        'bankRoutingNumber': '00110',
        'nationalId': 'NID-99887766',
        'taxId': 'TIN-5544',
        'dateOfBirth': '1994-03-11',
      };

  group('what the directory carries', () {
    // The guarantee that pay and bank details stay off the phone is structural,
    // not assertable: [Person] declares no field for them, so the compiler is
    // what enforces it and a test can only restate the obvious. Asserting on
    // toString() looks like a check and is not one — the default returns
    // "Instance of 'Person'" and would pass just as happily if salary were
    // mapped. What is worth testing is the half that can actually break: that
    // the extra keys do not disturb parsing, and that the mapped subset is
    // right.
    test('ignores the fields it does not want and parses the rest', () {
      final rich = Person.fromJson(payload());
      final lean = Person.fromJson(
        Map.of(payload())
          ..removeWhere(
            (key, _) => const {
              'basicSalary',
              'houseRent',
              'medicalAllowance',
              'transportAllowance',
              'billableRate',
              'bankAccountNumber',
              'bankName',
              'bankRoutingNumber',
              'nationalId',
              'taxId',
              'dateOfBirth',
            }.contains(key),
          ),
      );

      // Same record either way: nothing the directory shows is derived from
      // the sensitive half of the payload.
      expect(rich.fullName, lean.fullName);
      expect(rich.roleLabel, lean.roleLabel);
      expect(rich.bestEmail, lean.bestEmail);
      expect(rich.bestPhone, lean.bestPhone);
      expect(rich.departmentName, lean.departmentName);
      expect(rich.hireDate, lean.hireDate);
    });

    test('the fields it does keep survive', () {
      final person = Person.fromJson(payload());

      expect(person.id, 28);
      expect(person.fullName, 'Sumaiya Islam');
      expect(person.departmentName, 'Support');
      expect(person.employeeNumber, 'DEMO-0010');
      expect(person.hireDate, '2024-06-02');
    });
  });

  group('contact preference', () {
    test('work address wins over personal', () {
      expect(
        Person.fromJson(payload()).bestEmail,
        'sumaiya@dhrubotara.example.com',
      );
    });

    test('falls back to personal only when there is no work address', () {
      final person = Person.fromJson(payload(official: null));

      expect(person.bestEmail, 'sumaiya.islam@dhrubotara.example.com');
    });

    test('a blank work address does not count as one', () {
      final person = Person.fromJson(payload(official: '   '));

      expect(
        person.bestEmail,
        'sumaiya.islam@dhrubotara.example.com',
        reason: 'whitespace would otherwise open a mail draft to nobody',
      );
    });

    test('the same preference applies to phone numbers', () {
      expect(Person.fromJson(payload()).bestPhone, '+880 1710-123456');
      expect(
        Person.fromJson(payload(workPhone: null, phone: '+880 1999')).bestPhone,
        '+880 1999',
      );
      expect(
        Person.fromJson(payload(workPhone: null)).bestPhone,
        isNull,
        reason: 'no number at all must be null, not an empty string, so the '
            'Call button is not offered',
      );
    });
  });

  group('role label', () {
    test('prefers the free-text job title', () {
      expect(Person.fromJson(payload()).roleLabel, 'Support Engineer');
    });

    test('falls back to the structured designation', () {
      final person =
          Person.fromJson(payload(jobTitle: null, designation: 'Engineer II'));

      expect(person.roleLabel, 'Engineer II');
    });

    test('is null when neither is set, rather than an empty line', () {
      expect(Person.fromJson(payload(jobTitle: '  ')).roleLabel, isNull);
    });
  });

  group('isFormer', () {
    test('flags people who have left', () {
      for (final status in ['TERMINATED', 'RESIGNED', 'INACTIVE']) {
        expect(
          Person.fromJson(payload(status: status)).isFormer,
          isTrue,
          reason: '$status should not read as a current colleague',
        );
      }
    });

    test('leaves current staff alone', () {
      expect(Person.fromJson(payload()).isFormer, isFalse);
      expect(Person.fromJson(payload(status: 'PROBATION')).isFormer, isFalse);
      expect(Person.fromJson(payload(status: null)).isFormer, isFalse);
    });
  });

  group('initials', () {
    Person named(String first, String last) => Person.fromJson({
          'id': 1,
          'firstName': first,
          'lastName': last,
        });

    test('uses both names', () {
      expect(named('Sumaiya', 'Islam').initials, 'SI');
    });

    test('copes with a missing half', () {
      expect(named('Sumaiya', '').initials, 'S');
      expect(named('', 'Islam').initials, 'I');
    });

    test('never throws on an empty record', () {
      expect(named('', '').initials, '?');
    });
  });

  group('Department', () {
    test('reads the filter payload', () {
      final department = Department.fromJson(const {
        'id': 22,
        'name': 'Engineering',
        'code': 'ENG',
        'employeeCount': 4,
      });

      expect(department.id, 22);
      expect(department.name, 'Engineering');
      expect(department.employeeCount, 4);
    });
  });
}
