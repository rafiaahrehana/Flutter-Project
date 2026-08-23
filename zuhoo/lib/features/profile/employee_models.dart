import '../../core/config/env.dart';

/// The signed-in user's employee record — GET /api/employees/me.
///
/// The backend's `EmployeeResponse` is wide (payroll figures, bank details,
/// emergency contacts, the full location tree). Only the fields the mobile app
/// actually shows are modelled; a phone is not where anyone edits a salary
/// structure, and parsing fields nothing reads would just be surface area that
/// can break when the DTO grows.
class Employee {
  const Employee({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.workPhone,
    this.image,
    this.employeeNumber,
    this.officialEmail,
    this.jobTitle,
    this.employmentType,
    this.employmentStatus,
    this.gender,
    this.dateOfBirth,
    this.hireDate,
    this.departmentName,
    this.designationName,
    this.reportingManagerName,
    this.shiftName,
    this.officeLocation,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactRelation,
    this.customRoleName,
    this.active = true,
  });

  final int id;
  final int userId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String? workPhone;
  final String? image;
  final String? employeeNumber;
  final String? officialEmail;
  final String? jobTitle;
  final String? employmentType;
  final String? employmentStatus;
  final String? gender;
  final String? dateOfBirth;
  final String? hireDate;
  final String? departmentName;
  final String? designationName;
  final String? reportingManagerName;
  final String? shiftName;
  final String? officeLocation;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactRelation;
  final String? customRoleName;
  final bool active;

  String get fullName => '$firstName $lastName'.trim();

  /// What to call this person's job. The employee dashboard falls back to the
  /// plain word "Employee" rather than showing nothing, since everyone with a
  /// record here is one.
  String get roleLabel =>
      customRoleName ?? designationName ?? jobTitle ?? 'Employee';

  String? get imageUrl => Env.resolveImageUrl(image);

  String get initials {
    final f = firstName.trim();
    final l = lastName.trim();
    if (f.isEmpty && l.isEmpty) return email.isEmpty ? '?' : email[0].toUpperCase();
    if (l.isEmpty) return f[0].toUpperCase();
    if (f.isEmpty) return l[0].toUpperCase();
    return (f[0] + l[0]).toUpperCase();
  }

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: (json['id'] as num?)?.toInt() ?? 0,
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        workPhone: json['workPhone'] as String?,
        image: json['image'] as String? ?? json['profileImageUrl'] as String?,
        employeeNumber: json['employeeNumber'] as String?,
        officialEmail: json['officialEmail'] as String?,
        jobTitle: json['jobTitle'] as String?,
        employmentType: json['employmentType'] as String?,
        employmentStatus: json['employmentStatus'] as String?,
        gender: json['gender'] as String?,
        dateOfBirth: json['dateOfBirth'] as String?,
        hireDate: json['hireDate'] as String?,
        departmentName: json['departmentName'] as String?,
        designationName: json['designationName'] as String?,
        reportingManagerName: json['reportingManagerName'] as String?,
        shiftName: json['shiftName'] as String?,
        officeLocation: json['officeLocation'] as String?,
        emergencyContactName: json['emergencyContactName'] as String?,
        emergencyContactPhone: json['emergencyContactPhone'] as String?,
        emergencyContactRelation: json['emergencyContactRelation'] as String?,
        customRoleName: json['customRoleName'] as String?,
        active: json['active'] as bool? ?? true,
      );
}

/// PATCH /api/employees/me. Only the fields an employee is allowed to change
/// about themselves — everything else on the record is HR's to set.
class SelfUpdateEmployeeRequest {
  const SelfUpdateEmployeeRequest({
    this.phone,
    this.workPhone,
    this.gender,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactRelation,
  });

  /// Personal mobile. Lives on the User account, unlike [workPhone] which
  /// lives on the Employee record — the backend routes them to different rows.
  final String? phone;
  final String? workPhone;
  final String? gender;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactRelation;

  /// Omits absent keys rather than sending nulls: a PATCH with an explicit
  /// null would clear the stored value, which is not what leaving a field
  /// untouched means.
  Map<String, dynamic> toJson() => {
        if (phone != null) 'phone': phone,
        if (workPhone != null) 'workPhone': workPhone,
        if (gender != null) 'gender': gender,
        if (emergencyContactName != null)
          'emergencyContactName': emergencyContactName,
        if (emergencyContactPhone != null)
          'emergencyContactPhone': emergencyContactPhone,
        if (emergencyContactRelation != null)
          'emergencyContactRelation': emergencyContactRelation,
      };
}

const genderOptions = <String>['MALE', 'FEMALE', 'OTHER'];
