/// One month's payroll record for one employee.
///
/// The figures are frozen onto the record when the payroll run executes — the
/// billable and overtime rates included — so a payslip stays a faithful record
/// of what was paid even after someone's salary structure changes.
class Payslip {
  const Payslip({
    required this.id,
    required this.payMonth,
    required this.payYear,
    required this.basicSalary,
    required this.netSalary,
    required this.status,
    required this.employeeId,
    required this.employeeName,
    this.houseRent,
    this.medicalAllowance,
    this.transportAllowance,
    this.foodAllowance,
    this.specialAllowance,
    this.bonus,
    this.billableHours,
    this.billablePay,
    this.overtimeHours,
    this.overtimePay,
    this.otherEarnings,
    this.taxDeduction,
    this.insuranceDeduction,
    this.providentFundDeduction,
    this.attendanceDeduction,
    this.deductions,
    this.otherDeductions,
    this.absentDays,
    this.paymentReference,
    this.paymentMethod,
    this.paidAt,
    this.notes,
    this.createdAt,
  });

  final int id;
  final int payMonth;
  final int payYear;
  final double basicSalary;
  final double netSalary;
  final String status;
  final int employeeId;
  final String employeeName;

  final double? houseRent;
  final double? medicalAllowance;
  final double? transportAllowance;
  final double? foodAllowance;
  final double? specialAllowance;
  final double? bonus;
  final double? billableHours;
  final double? billablePay;
  final double? overtimeHours;
  final double? overtimePay;
  final double? otherEarnings;

  final double? taxDeduction;
  final double? insuranceDeduction;
  final double? providentFundDeduction;
  final double? attendanceDeduction;
  final double? deductions;
  final double? otherDeductions;
  final int? absentDays;

  final String? paymentReference;
  final String? paymentMethod;
  final String? paidAt;
  final String? notes;
  final String? createdAt;

  /// Every earning on the slip, in the order the PDF totals its left column.
  double get gross =>
      basicSalary +
      (houseRent ?? 0) +
      (medicalAllowance ?? 0) +
      (transportAllowance ?? 0) +
      (foodAllowance ?? 0) +
      (specialAllowance ?? 0) +
      (bonus ?? 0) +
      (billablePay ?? 0) +
      (overtimePay ?? 0) +
      (otherEarnings ?? 0);

  /// Every deduction, mirroring the PDF's right column.
  double get totalDeductions =>
      (taxDeduction ?? 0) +
      (providentFundDeduction ?? 0) +
      (insuranceDeduction ?? 0) +
      (attendanceDeduction ?? 0) +
      (deductions ?? 0) +
      (otherDeductions ?? 0);

  /// A DRAFT has not been approved, so its figures can still change. Offering
  /// a downloadable document for one would put a payslip in someone's hands
  /// that does not match what they are eventually paid.
  bool get canDownload => status != 'DRAFT';

  List<({String label, double amount})> get earnings => [
        (label: 'Basic salary', amount: basicSalary),
        if ((houseRent ?? 0) != 0) (label: 'House rent', amount: houseRent!),
        if ((medicalAllowance ?? 0) != 0)
          (label: 'Medical allowance', amount: medicalAllowance!),
        if ((transportAllowance ?? 0) != 0)
          (label: 'Transport allowance', amount: transportAllowance!),
        if ((foodAllowance ?? 0) != 0)
          (label: 'Food allowance', amount: foodAllowance!),
        if ((specialAllowance ?? 0) != 0)
          (label: 'Special allowance', amount: specialAllowance!),
        if ((bonus ?? 0) != 0) (label: 'Bonus', amount: bonus!),
        if ((billablePay ?? 0) != 0)
          (label: 'Billable pay', amount: billablePay!),
        if ((overtimePay ?? 0) != 0) (label: 'Overtime', amount: overtimePay!),
        if ((otherEarnings ?? 0) != 0)
          (label: 'Other earnings', amount: otherEarnings!),
      ];

  List<({String label, double amount})> get deductionLines => [
        if ((taxDeduction ?? 0) != 0) (label: 'Tax', amount: taxDeduction!),
        if ((providentFundDeduction ?? 0) != 0)
          (label: 'Provident fund', amount: providentFundDeduction!),
        if ((insuranceDeduction ?? 0) != 0)
          (label: 'Insurance', amount: insuranceDeduction!),
        if ((attendanceDeduction ?? 0) != 0)
          (label: 'Attendance', amount: attendanceDeduction!),
        if ((deductions ?? 0) != 0) (label: 'Deductions', amount: deductions!),
        if ((otherDeductions ?? 0) != 0)
          (label: 'Other deductions', amount: otherDeductions!),
      ];

  factory Payslip.fromJson(Map<String, dynamic> json) {
    double? d(String key) => (json[key] as num?)?.toDouble();
    return Payslip(
      id: (json['id'] as num?)?.toInt() ?? 0,
      payMonth: (json['payMonth'] as num?)?.toInt() ?? 1,
      payYear: (json['payYear'] as num?)?.toInt() ?? DateTime.now().year,
      basicSalary: d('basicSalary') ?? 0,
      netSalary: d('netSalary') ?? 0,
      status: json['status'] as String? ?? 'DRAFT',
      employeeId: (json['employeeId'] as num?)?.toInt() ?? 0,
      employeeName: json['employeeName'] as String? ?? '',
      houseRent: d('houseRent'),
      medicalAllowance: d('medicalAllowance'),
      transportAllowance: d('transportAllowance'),
      foodAllowance: d('foodAllowance'),
      specialAllowance: d('specialAllowance'),
      bonus: d('bonus'),
      billableHours: d('billableHours'),
      billablePay: d('billablePay'),
      overtimeHours: d('overtimeHours'),
      overtimePay: d('overtimePay'),
      otherEarnings: d('otherEarnings'),
      taxDeduction: d('taxDeduction'),
      insuranceDeduction: d('insuranceDeduction'),
      providentFundDeduction: d('providentFundDeduction'),
      attendanceDeduction: d('attendanceDeduction'),
      deductions: d('deductions'),
      otherDeductions: d('otherDeductions'),
      absentDays: (json['absentDays'] as num?)?.toInt(),
      paymentReference: json['paymentReference'] as String?,
      paymentMethod: json['paymentMethod'] as String?,
      paidAt: json['paidAt'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['createdAt'] as String?,
    );
  }
}
