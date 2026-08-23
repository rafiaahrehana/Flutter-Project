import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../profile/employee_repository.dart';
import 'payslip_models.dart';

class PayslipRepository {
  PayslipRepository(this._api);

  final ApiClient _api;

  static const _base = '/hr/payroll';

  Future<PagedResponse<Payslip>> forEmployee(
    int employeeId, {
    int page = 0,
    int size = 24,
  }) =>
      _api.getPaged(
        '$_base/employee/$employeeId',
        Payslip.fromJson,
        page: page,
        size: size,
      );

  /// Downloads the payslip PDF to a temp file and returns its path.
  ///
  /// The backend scopes this endpoint itself — PAYROLL_VIEW downloads anyone's,
  /// everyone else only their own — so calling it from an employee's own screen
  /// needs no extra guard here.
  ///
  /// The file goes to the temp directory rather than anywhere permanent: it is
  /// handed straight to the platform viewer, and a payslip is not something to
  /// leave lying in app storage indefinitely.
  Future<String> downloadPdf(Payslip payslip) async {
    final bytes = await _api.getBytes('$_base/${payslip.id}/payslip');
    final dir = await getTemporaryDirectory();
    final name =
        'payslip-${payslip.payYear}-${payslip.payMonth.toString().padLeft(2, '0')}.pdf';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}

final payslipRepositoryProvider = Provider<PayslipRepository>(
  (ref) => PayslipRepository(ref.watch(apiClientProvider)),
);

/// This employee's payslips, newest first.
///
/// Depends on the employee record because the endpoint is keyed on the
/// employee id, not the user id — the two are different numbers, and the JWT
/// carries the user's.
final myPayslipsProvider = FutureProvider<List<Payslip>>((ref) async {
  final employee = await ref.watch(myEmployeeProvider.future);
  if (employee == null) {
    // Distinct from "no payslips yet", which is what an empty list would say.
    // Payroll runs against employee records, so an account without one can
    // never have a payslip and should be told why rather than shown an empty
    // list it will keep coming back to check.
    throw const ApiException(
      'Your account does not have an employee record, so there are no '
      'payslips to show.',
    );
  }
  final page =
      await ref.watch(payslipRepositoryProvider).forEmployee(employee.id);
  final payslips = [...page.content]..sort((a, b) {
      final byYear = b.payYear.compareTo(a.payYear);
      return byYear != 0 ? byYear : b.payMonth.compareTo(a.payMonth);
    });
  return payslips;
});
