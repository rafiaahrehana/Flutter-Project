import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/providers.dart';
import 'employee_models.dart';

class EmployeeRepository {
  EmployeeRepository(this._api);

  final ApiClient _api;

  Future<Employee> me() async {
    final json = await _api.get<Map<String, dynamic>>('/employees/me');
    return Employee.fromJson(json);
  }

  Future<Employee> updateMe(SelfUpdateEmployeeRequest request) async {
    final json =
        await _api.patch<Map<String, dynamic>>('/employees/me', request.toJson());
    return Employee.fromJson(json);
  }
}

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => EmployeeRepository(ref.watch(apiClientProvider)),
);

/// The signed-in user's employee record, or null if they do not have one.
///
/// Several screens need it — the dashboard for the greeting, payslips for the
/// employee id to query by — so it is fetched once here and shared. It rebuilds
/// when the signed-in user changes, which is what makes signing in as someone
/// else on the same device show their record rather than the previous one's.
///
/// **Null is a real, common answer, not a failure.** `GET /employees/me` throws
/// `ResourceNotFoundException` for any user with no row in the employees table,
/// and a COMPANY_OWNER typically has exactly that: an account, a company, and
/// no employee record of their own. Letting the 404 through would greet the
/// person who owns the company with "Not found." on their own profile. Screens
/// that genuinely need the record say so in their own words instead.
final myEmployeeProvider = FutureProvider<Employee?>((ref) async {
  ref.watch(currentUserProvider);
  try {
    return await ref.watch(employeeRepositoryProvider).me();
  } on ApiException catch (e) {
    if (e.isNotFound) return null;
    rethrow;
  }
});
