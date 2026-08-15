import 'package:intermittent_fasting/presenters/bills_receivables_presenter.dart';
import 'package:intermittent_fasting/presenters/budget_presenter.dart';
import 'package:intermittent_fasting/presenters/grocery_cart_presenter.dart';
import 'package:intermittent_fasting/presenters/installment_presenter.dart';
import 'package:intermittent_fasting/presenters/ledger_presenter.dart';
import 'package:intermittent_fasting/presenters/stats_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_dashboard_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_history_presenter.dart';
import 'package:intermittent_fasting/presenters/treasury_month_scope.dart';
import 'package:intermittent_fasting/services/ai_coach_service.dart';
import 'package:intermittent_fasting/services/finance_personal_dictionary.dart';
import 'package:intermittent_fasting/services/notification_service.dart';
import 'package:intermittent_fasting/services/storage_service.dart';

/// The Treasury presenter graph, assembled and wired in one place.
///
/// The mobile shell (`home_screen.dart`) and the web shell
/// (`treasury_web_app.dart`) both need the same seven presenters connected the
/// same way. They used to hand-assemble that graph independently, and it drifted
/// — which is how the module accumulated its cross-page staleness bugs: one root
/// would wire a dependency the other didn't, and a newly-added dependency had to
/// be remembered twice.
///
/// The rule this class exists to enforce: **cross-presenter wiring lives here,
/// nowhere else.** A root asks for the graph and gets one that is correct by
/// construction; it cannot forget a hook it never had to write. When a new
/// dependency appears, it is added once, and both platforms get it.
///
/// The presenters themselves stay independently constructible — tests and
/// single-screen mounts build exactly what they need — so this is a convenience
/// for composition roots, not a service locator.
class TreasuryPresenters {
  /// Shared "month being read" across Ledger, Bills, Budget and Installments,
  /// so paging one tab to June doesn't leave the others in the current month.
  final TreasuryMonthScope monthScope;

  /// Owns accounts, transactions and categories — the other presenters mirror
  /// their copies off this one.
  final LedgerPresenter ledger;

  /// Owns budgets and budget groups.
  final BudgetPresenter budget;

  /// Owns bills, receivables and budgeted expenses.
  final BillsReceivablesPresenter bills;

  /// Reports on everything and owns nothing: it mirrors accounts, transactions
  /// and categories from [ledger], budgets and groups from [budget], and bills,
  /// receivables and set-asides from [bills] — subscribing to each owner rather
  /// than keeping copies only its own `load()` refreshes.
  final TreasuryDashboardPresenter dashboard;

  final TreasuryHistoryPresenter history;
  final InstallmentPresenter installments;
  final GroceryCartPresenter groceryCart;

  TreasuryPresenters._({
    required this.monthScope,
    required this.ledger,
    required this.budget,
    required this.dashboard,
    required this.bills,
    required this.history,
    required this.installments,
    required this.groceryCart,
  });

  /// Builds the graph.
  ///
  /// Construction order is load-bearing and is the reason this lives in one
  /// place: budget and bills need the ledger, and the dashboard subscribes to
  /// all three, so it is built last.
  ///
  /// [ai] and [cloudAi] are the ledger's natural-language tiers — mobile passes
  /// both, web passes the cloud tier only (there is no on-device model in a
  /// browser). Everything else is platform-agnostic.
  factory TreasuryPresenters({
    required StorageService storage,
    required StatsPresenter stats,
    AiCoachService? ai,
    AiCoachService? cloudAi,
    FinancePersonalDictionary? financeDict,
    NotificationService? notifications,
    TreasuryMonthScope? monthScope,
  }) {
    final scope = monthScope ?? TreasuryMonthScope();

    final ledger = LedgerPresenter(
      storage,
      stats,
      ai: ai,
      cloudAi: cloudAi,
      financeDict: financeDict,
      monthScope: scope,
    );

    // Owners first, reporters last: the dashboard subscribes to all three, so
    // each has to exist before it does.
    final budget = BudgetPresenter(
      storage,
      stats,
      ledger,
      notifications,
      scope,
    );

    final bills = BillsReceivablesPresenter(
      storage,
      ledger,
      stats,
      notifications: notifications,
      monthScope: scope,
    );

    final dashboard =
        TreasuryDashboardPresenter(storage, ledger, budget, bills);

    return TreasuryPresenters._(
      monthScope: scope,
      ledger: ledger,
      budget: budget,
      dashboard: dashboard,
      bills: bills,
      history: TreasuryHistoryPresenter(storage),
      installments: InstallmentPresenter(
        storage,
        ledger,
        stats,
        monthScope: scope,
      ),
      groceryCart: GroceryCartPresenter(storage, ledger: ledger),
    );
  }

  /// Loads every presenter concurrently. A failure in one is logged by the
  /// caller's error handling rather than aborting the rest.
  List<Future<void>> loadAll() => [
        ledger.load(),
        dashboard.load(),
        budget.load(),
        bills.load(),
        history.load(),
        installments.load(),
        groceryCart.load(),
      ];

  void dispose() {
    // Dependants first, so nothing notifies into a disposed listener.
    groceryCart.dispose();
    installments.dispose();
    history.dispose();
    bills.dispose();
    dashboard.dispose();
    budget.dispose();
    ledger.dispose();
    monthScope.dispose();
  }
}
