import '../../core/config/env.dart';

abstract final class DirectoryPermissions {
  /// What the web app requires to open the employee list. The API itself does
  /// **not** check it — `EmployeeServiceImpl.listAll` performs no permission
  /// check, only the controller's `hasAnyRole('COMPANY_OWNER', 'EMPLOYEE')`.
  ///
  /// Matched here anyway rather than left open: the same endpoint returns pay
  /// and bank details (see [Person]), the tenant configures this permission
  /// deliberately, and widening who can browse colleagues on a phone is not a
  /// decision a port should make on its own.
  static const employeeView = 'EMPLOYEE_VIEW';
}

/// A colleague, as the directory shows them.
///
/// `GET /api/employees` returns considerably more than this: `basicSalary`,
/// `houseRent`, `medicalAllowance`, `transportAllowance`, `billableRate`,
/// `bankAccountNumber`, `bankName`, `bankRoutingNumber`, `nationalId`,
/// `taxId` and `dateOfBirth` all arrive in the same payload, for every
/// employee, unmasked.
///
/// None of them are mapped here, and that is the point. A directory answers
/// "who is this, what do they do, how do I reach them" — it has no business
/// holding a colleague's salary in memory on a phone, and a field that is
/// never parsed cannot be rendered by a later edit that forgets why.
class Person {
  const Person({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.employeeNumber,
    this.jobTitle,
    this.designationName,
    this.departmentId,
    this.departmentName,
    this.email,
    this.officialEmail,
    this.phone,
    this.workPhone,
    this.reportingManagerId,
    this.reportingManagerName,
    this.shiftName,
    this.hireDate,
    this.employmentStatus,
    this.employmentType,
    this.officeLocation,
    this.imageUrl,
  });

  final int id;
  final String firstName;
  final String lastName;
  final String? employeeNumber;
  final String? jobTitle;
  final String? designationName;
  final int? departmentId;
  final String? departmentName;

  /// Personal address. [officialEmail] is the work one; the directory prefers
  /// the work address and falls back, because emailing a colleague's private
  /// account when a work one exists is the wrong default.
  final String? email;
  final String? officialEmail;

  final String? phone;
  final String? workPhone;
  final int? reportingManagerId;
  final String? reportingManagerName;
  final String? shiftName;
  final String? hireDate;
  final String? employmentStatus;
  final String? employmentType;
  final String? officeLocation;
  final String? imageUrl;

  String get fullName => '$firstName $lastName'.trim();

  /// What to put under the name. The job title is free text on the employee
  /// record and the designation is the structured one; either may be blank.
  String? get roleLabel {
    final title = jobTitle?.trim();
    if (title != null && title.isNotEmpty) return title;
    final designation = designationName?.trim();
    return designation == null || designation.isEmpty ? null : designation;
  }

  String? get bestEmail {
    final work = officialEmail?.trim();
    if (work != null && work.isNotEmpty) return work;
    final personal = email?.trim();
    return personal == null || personal.isEmpty ? null : personal;
  }

  String? get bestPhone {
    final work = workPhone?.trim();
    if (work != null && work.isNotEmpty) return work;
    final personal = phone?.trim();
    return personal == null || personal.isEmpty ? null : personal;
  }

  /// Someone who has left. The list still returns them, so the row says so
  /// rather than offering a phone number nobody answers.
  bool get isFormer =>
      employmentStatus == 'TERMINATED' ||
      employmentStatus == 'RESIGNED' ||
      employmentStatus == 'INACTIVE';

  String get initials {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return '?';
    if (l.isEmpty) return f[0].toUpperCase();
    if (f.isEmpty) return l[0].toUpperCase();
    return (f[0] + l[0]).toUpperCase();
  }

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: (json['id'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        employeeNumber: json['employeeNumber'] as String?,
        jobTitle: json['jobTitle'] as String?,
        designationName: json['designationName'] as String?,
        departmentId: (json['departmentId'] as num?)?.toInt(),
        departmentName: json['departmentName'] as String?,
        email: json['email'] as String?,
        officialEmail: json['officialEmail'] as String?,
        phone: json['phone'] as String?,
        workPhone: json['workPhone'] as String?,
        reportingManagerId: (json['reportingManagerId'] as num?)?.toInt(),
        reportingManagerName: json['reportingManagerName'] as String?,
        shiftName: json['shiftName'] as String?,
        hireDate: json['hireDate'] as String?,
        employmentStatus: json['employmentStatus'] as String?,
        employmentType: json['employmentType'] as String?,
        officeLocation:
            json['officeLocation'] as String? ?? json['location'] as String?,
        // The record carries the employee's own image and the linked user
        // account's; either can be the one that was set.
        imageUrl: Env.resolveImageUrl(
          json['profileImageUrl'] as String? ?? json['image'] as String?,
        ),
      );
}

/// A department, for the directory's filter.
class Department {
  const Department({
    required this.id,
    required this.name,
    this.code,
    this.employeeCount,
  });

  final int id;
  final String name;
  final String? code;
  final int? employeeCount;

  factory Department.fromJson(Map<String, dynamic> json) => Department(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: json['name'] as String? ?? '',
        code: json['code'] as String?,
        employeeCount: (json['employeeCount'] as num?)?.toInt(),
      );
}
