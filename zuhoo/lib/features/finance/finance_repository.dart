import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/paged_response.dart';
import '../../core/providers.dart';
import '../../shared/paged_controller.dart';
import '../portal/portal_models.dart' show Invoice;
import 'finance_models.dart';

/// Which slice of expenses to show.
///
/// Server-side definitions, not a client-side filter: `mine` resolves the
/// caller's employee record, and the status lists are the backend's own.
enum ExpenseView { mine, pending, all }

class FinanceRepository {
  FinanceRepository(this._api);

  final ApiClient _api;

  static const _base = '/company/finance';

  Future<FinanceOverview> overview({int? month, int? year}) async {
    final json = await _api.get<Map<String, dynamic>>(
      '/finance/dashboard',
      query: {'month': month, 'year': year},
    );
    return FinanceOverview.fromJson(json);
  }

  // ── Invoices ────────────────────────────────────────────────
  // The Invoice model is shared with the client portal deliberately: it is the
  // same record, and a second copy would be somewhere for the two to drift.

  Future<PagedResponse<Invoice>> invoices({
    String? status,
    int page = 0,
    int size = 20,
  }) {
    // The backend splits these: a status filter has its own path rather than
    // a query parameter on the list.
    final path = status == null
        ? '$_base/invoices'
        : '$_base/invoices/status/$status';
    return _api.getPaged(path, Invoice.fromJson, page: page, size: size);
  }

  Future<Invoice> invoice(int id) async {
    final json = await _api.get<Map<String, dynamic>>('$_base/invoices/$id');
    return Invoice.fromJson(json);
  }

  Future<String> invoicePdf(Invoice invoice) async {
    final bytes = await _api.getBytes('$_base/invoices/${invoice.id}/pdf');
    final dir = await getTemporaryDirectory();
    final safe = invoice.invoiceNumber.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
    final file = File('${dir.path}${Platform.pathSeparator}invoice-$safe.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  // ── Expenses ────────────────────────────────────────────────

  Future<PagedResponse<Expense>> expenses(
    ExpenseView view, {
    int page = 0,
    int size = 20,
  }) async {
    final path = switch (view) {
      ExpenseView.mine => '$_base/expenses/my-expenses',
      ExpenseView.pending => '$_base/expenses/status/${ExpenseStatus.pending}',
      ExpenseView.all => '$_base/expenses',
    };
    try {
      return await _api.getPaged(path, Expense.fromJson, page: page, size: size);
    } on ApiException catch (e) {
      // `my-expenses` resolves an employee record and fails for an account
      // without one — an owner, typically. Same shape as `/employees/me`, and
      // the same answer: not applicable, rather than broken.
      if (view == ExpenseView.mine &&
          (e.statusCode == 400 || e.isNotFound || e.isForbidden)) {
        return const PagedResponse<Expense>.empty();
      }
      rethrow;
    }
  }

  Future<Expense> submit(CreateExpenseRequest request) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/expenses',
      request.toJson(),
    );
    return Expense.fromJson(json);
  }

  /// Approves a claim.
  ///
  /// Notes go as a query parameter, not a body — the controller declares
  /// `@RequestParam`, so a JSON body is silently ignored. The response can
  /// carry a `budgetWarning` when the approval pushes a category over budget,
  /// which is worth showing rather than swallowing.
  Future<String?> approve(int id, String notes) async {
    final json = await _api.post<Map<String, dynamic>>(
      '$_base/expenses/$id/approve?notes=${Uri.encodeQueryComponent(notes.trim())}',
    );
    final warning = json['budgetWarning'];
    return warning is String && warning.trim().isNotEmpty ? warning : null;
  }

  Future<void> reject(int id, String reason) => _api.post<dynamic>(
        '$_base/expenses/$id/reject?reason=${Uri.encodeQueryComponent(reason.trim())}',
      );

  // ── Wallet ──────────────────────────────────────────────────

  Future<Wallet> wallet() async {
    final json = await _api.get<Map<String, dynamic>>('/wallet');
    return Wallet.fromJson(json);
  }

  Future<PagedResponse<WalletTransaction>> walletTransactions({
    int page = 0,
    int size = 20,
  }) =>
      _api.getPaged(
        '/wallet/transactions',
        WalletTransaction.fromJson,
        page: page,
        size: size,
      );
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => FinanceRepository(ref.watch(apiClientProvider)),
);

final financeOverviewProvider = FutureProvider<FinanceOverview>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(financeRepositoryProvider).overview();
});

final walletProvider = FutureProvider<Wallet>((ref) {
  ref.watch(currentUserProvider);
  return ref.watch(financeRepositoryProvider).wallet();
});

/// Which invoice status the list is filtered to. Null means all of them.
class InvoiceFilterController extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? status) {
    if (state == status) return;
    state = status;
  }
}

final invoiceFilterProvider =
    NotifierProvider<InvoiceFilterController, String?>(
  InvoiceFilterController.new,
);

class InvoicesController extends AsyncNotifier<PagedState<Invoice>>
    with PagedLoader<Invoice> {
  @override
  Future<PagedState<Invoice>> build() {
    ref.watch(currentUserProvider);
    ref.watch(invoiceFilterProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Invoice>> fetchPage(int page) => ref
      .read(financeRepositoryProvider)
      .invoices(status: ref.read(invoiceFilterProvider), page: page);
}

final invoicesProvider =
    AsyncNotifierProvider<InvoicesController, PagedState<Invoice>>(
  InvoicesController.new,
);

class ExpenseViewController extends Notifier<ExpenseView> {
  @override
  ExpenseView build() => ExpenseView.mine;

  void set(ExpenseView view) {
    if (state == view) return;
    state = view;
  }
}

final expenseViewProvider =
    NotifierProvider<ExpenseViewController, ExpenseView>(
  ExpenseViewController.new,
);

class ExpensesController extends AsyncNotifier<PagedState<Expense>>
    with PagedLoader<Expense> {
  @override
  Future<PagedState<Expense>> build() {
    ref.watch(currentUserProvider);
    ref.watch(expenseViewProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<Expense>> fetchPage(int page) => ref
      .read(financeRepositoryProvider)
      .expenses(ref.read(expenseViewProvider), page: page);

  Future<Expense> submit(CreateExpenseRequest request) async {
    final created = await ref.read(financeRepositoryProvider).submit(request);
    await refresh();
    return created;
  }

  /// Decides a claim and drops it from the list when the list is the pending
  /// queue — a decided claim no longer belongs there.
  Future<String?> decide(
    int id, {
    required bool approved,
    required String notes,
  }) async {
    final repo = ref.read(financeRepositoryProvider);
    String? warning;
    if (approved) {
      warning = await repo.approve(id, notes);
    } else {
      await repo.reject(id, notes);
    }
    if (ref.read(expenseViewProvider) == ExpenseView.pending) {
      removeItem((expense) => expense.id == id);
    } else {
      await refresh();
    }
    // The approval may have pushed a category over budget; the caller shows it.
    return warning;
  }
}

final expensesProvider =
    AsyncNotifierProvider<ExpensesController, PagedState<Expense>>(
  ExpensesController.new,
);

class WalletTransactionsController
    extends AsyncNotifier<PagedState<WalletTransaction>>
    with PagedLoader<WalletTransaction> {
  @override
  Future<PagedState<WalletTransaction>> build() {
    ref.watch(currentUserProvider);
    return loadFirstPage();
  }

  @override
  Future<PagedResponse<WalletTransaction>> fetchPage(int page) =>
      ref.read(financeRepositoryProvider).walletTransactions(page: page);
}

final walletTransactionsProvider = AsyncNotifierProvider<
    WalletTransactionsController, PagedState<WalletTransaction>>(
  WalletTransactionsController.new,
);
