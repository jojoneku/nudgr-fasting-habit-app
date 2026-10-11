import 'package:flutter/foundation.dart';

/// Stable keys for every user-facing action on the Treasury web v2 UI
/// (Plan 063, ground rule 4).
///
/// One key per distinct action in `docs/web_parity_checklist.md`, named
/// `web.<page>.<action>`. The v2 pages attach these to the control that
/// provides the action; the parity test of each page asserts every key is
/// present with seeded data, so a button that disappears in a rewrite fails
/// CI instead of being noticed by a user. Lines the checklist marks DROPPED
/// and the Cart page have no key.
abstract final class WebKeys {
  // ── Shell ────────────────────────────────────────────────────────────────
  static const navDashboard = ValueKey('web.nav.dashboard');
  static const navLedger = ValueKey('web.nav.ledger');
  static const navBills = ValueKey('web.nav.bills');
  static const navBudget = ValueKey('web.nav.budget');
  static const navHistory = ValueKey('web.nav.history');
  static const navGoals = ValueKey('web.nav.goals');
  static const navSetup = ValueKey('web.nav.setup');
  static const navBillsDuePill = ValueKey('web.nav.billsDuePill');
  static const navSyncStatus = ValueKey('web.nav.syncStatus');
  static const navThemeToggle = ValueKey('web.nav.themeToggle');
  static const navAccountMenu = ValueKey('web.nav.accountMenu');
  static const navAccountEmail = ValueKey('web.nav.accountEmail');
  static const navSignOut = ValueKey('web.nav.signOut');

  // ── Login ────────────────────────────────────────────────────────────────
  static const loginGoogle = ValueKey('web.login.google');
  static const loginThemeToggle = ValueKey('web.login.themeToggle');
  static const loginBrandPanel = ValueKey('web.login.brandPanel');
  static const loginSignInPanel = ValueKey('web.login.signInPanel');

  // ── Nudgy ────────────────────────────────────────────────────────────────
  static const nudgyOpen = ValueKey('web.nudgy.open');
  static const nudgyClose = ValueKey('web.nudgy.close');
  static const nudgyResizeHandle = ValueKey('web.nudgy.resizeHandle');
  static const nudgyConversations = ValueKey('web.nudgy.conversations');
  static const nudgyMemory = ValueKey('web.nudgy.memory');
  static const nudgyThinkingToggle = ValueKey('web.nudgy.thinkingToggle');
  static const nudgyInput = ValueKey('web.nudgy.input');
  static const nudgySend = ValueKey('web.nudgy.send');
  static const nudgyAttachPhoto = ValueKey('web.nudgy.attachPhoto');
  static const nudgyChipScanReceipt = ValueKey('web.nudgy.chip.scanReceipt');
  static const nudgyChipPayCard = ValueKey('web.nudgy.chip.payCard');
  static const nudgyChipSpendToday = ValueKey('web.nudgy.chip.spendToday');

  // ── Dashboard ────────────────────────────────────────────────────────────
  static const dashboardAddFirstAccount =
      ValueKey('web.dashboard.addFirstAccount');
  static const dashboardMonthStepper = ValueKey('web.dashboard.monthStepper');
  static const dashboardAddTransaction =
      ValueKey('web.dashboard.addTransaction');
  static const dashboardNetWorthHero = ValueKey('web.dashboard.netWorthHero');
  static const dashboardOutlook = ValueKey('web.dashboard.outlook');
  static const dashboardAllAccounts = ValueKey('web.dashboard.allAccounts');
  static const dashboardTrendsSwitch = ValueKey('web.dashboard.trendsSwitch');
  static const dashboardTrendNetWorth =
      ValueKey('web.dashboard.trend.netWorth');
  static const dashboardTrendIncomeExpenses =
      ValueKey('web.dashboard.trend.incomeExpenses');
  static const dashboardTrendDailySpending =
      ValueKey('web.dashboard.trend.dailySpending');
  static const dashboardCashFlow = ValueKey('web.dashboard.cashFlow');
  static const dashboardBudgetHealth = ValueKey('web.dashboard.budgetHealth');
  static const dashboardOpenBudget = ValueKey('web.dashboard.openBudget');
  static const dashboardSpendingDonut = ValueKey('web.dashboard.spendingDonut');
  static const dashboardPayCard = ValueKey('web.dashboard.payCard');
  static const dashboardAllCards = ValueKey('web.dashboard.allCards');
  static const dashboardSavingsGoals = ValueKey('web.dashboard.savingsGoals');
  static const dashboardOpenGoals = ValueKey('web.dashboard.openGoals');
  static const dashboardComingUp = ValueKey('web.dashboard.comingUp');
  static const dashboardAccountInventoryClose =
      ValueKey('web.dashboard.accountInventory.close');

  // ── Ledger ───────────────────────────────────────────────────────────────
  static const ledgerMonthStepper = ValueKey('web.ledger.monthStepper');
  static const ledgerSearch = ValueKey('web.ledger.search');
  static const ledgerFiltersButton = ValueKey('web.ledger.filtersButton');
  static const ledgerFilterAccounts = ValueKey('web.ledger.filter.accounts');
  static const ledgerFilterCategories =
      ValueKey('web.ledger.filter.categories');
  static const ledgerFilterType = ValueKey('web.ledger.filter.type');
  static const ledgerFilterSort = ValueKey('web.ledger.filter.sort');
  static const ledgerFilterFrom = ValueKey('web.ledger.filter.from');
  static const ledgerFilterUntil = ValueKey('web.ledger.filter.until');
  static const ledgerFilterClearAll = ValueKey('web.ledger.filter.clearAll');
  static const ledgerFilterDone = ValueKey('web.ledger.filter.done');
  static const ledgerActiveChips = ValueKey('web.ledger.activeChips');
  static const ledgerScanReceipt = ValueKey('web.ledger.scanReceipt');
  static const ledgerAddTransaction = ValueKey('web.ledger.addTransaction');
  static const ledgerSelectAll = ValueKey('web.ledger.selectAll');
  static const ledgerDraftRow = ValueKey('web.ledger.draftRow');
  static const ledgerDraftAdd = ValueKey('web.ledger.draft.add');
  static const ledgerRowMenu = ValueKey('web.ledger.row.menu');
  static const ledgerRowEdit = ValueKey('web.ledger.row.edit');
  static const ledgerRowDuplicate = ValueKey('web.ledger.row.duplicate');
  static const ledgerRowSplitInstallments =
      ValueKey('web.ledger.row.splitInstallments');
  static const ledgerRowReimbursable = ValueKey('web.ledger.row.reimbursable');
  static const ledgerRowDelete = ValueKey('web.ledger.row.delete');
  static const ledgerSelectionBar = ValueKey('web.ledger.selectionBar');
  static const ledgerSelectionClear = ValueKey('web.ledger.selection.clear');
  static const ledgerSelectionDelete = ValueKey('web.ledger.selection.delete');
  static const ledgerFooterTotals = ValueKey('web.ledger.footerTotals');
  static const ledgerEmptyClearFilters =
      ValueKey('web.ledger.empty.clearFilters');
  static const ledgerReceiptDropZone = ValueKey('web.ledger.receipt.dropZone');
  static const ledgerReceiptScan = ValueKey('web.ledger.receipt.scan');
  static const ledgerReceiptCancel = ValueKey('web.ledger.receipt.cancel');
  static const ledgerDialogType = ValueKey('web.ledger.dialog.type');
  static const ledgerDialogAmount = ValueKey('web.ledger.dialog.amount');
  static const ledgerDialogDate = ValueKey('web.ledger.dialog.date');
  static const ledgerDialogAccount = ValueKey('web.ledger.dialog.account');
  static const ledgerDialogToAccount = ValueKey('web.ledger.dialog.toAccount');
  static const ledgerDialogCategory = ValueKey('web.ledger.dialog.category');
  static const ledgerDialogDescription =
      ValueKey('web.ledger.dialog.description');
  static const ledgerDialogMoreOptions =
      ValueKey('web.ledger.dialog.moreOptions');
  static const ledgerDialogNotes = ValueKey('web.ledger.dialog.notes');
  static const ledgerDialogInstallments =
      ValueKey('web.ledger.dialog.installments');
  static const ledgerDialogReimbursable =
      ValueKey('web.ledger.dialog.reimbursable');
  static const ledgerDialogCancel = ValueKey('web.ledger.dialog.cancel');
  static const ledgerDialogSubmit = ValueKey('web.ledger.dialog.submit');
  static const ledgerClearAll = ValueKey('web.ledger.clearAll');
  static const ledgerSortSummary = ValueKey('web.ledger.sortSummary');
  static const ledgerScopePill = ValueKey('web.ledger.scopePill');
  static const ledgerSelectionChangeCategory =
      ValueKey('web.ledger.selection.changeCategory');
  static const ledgerChangeCategoryPicker =
      ValueKey('web.ledger.changeCategory.picker');
  static const ledgerChangeCategoryApply =
      ValueKey('web.ledger.changeCategory.apply');
  static const ledgerDraftDate = ValueKey('web.ledger.draft.date');
  static const ledgerDraftAccount = ValueKey('web.ledger.draft.account');
  static const ledgerDraftDescription =
      ValueKey('web.ledger.draft.description');
  static const ledgerDraftCategory = ValueKey('web.ledger.draft.category');
  static const ledgerDraftInflow = ValueKey('web.ledger.draft.inflow');
  static const ledgerDraftOutflow = ValueKey('web.ledger.draft.outflow');
  static const ledgerDraftError = ValueKey('web.ledger.draft.error');
  static const ledgerEmptyOpenSetup = ValueKey('web.ledger.empty.openSetup');
  static const ledgerDialogDelete = ValueKey('web.ledger.dialog.delete');
  static const ledgerDialogOwedBy = ValueKey('web.ledger.dialog.owedBy');
  static const ledgerDialogExpectedBack =
      ValueKey('web.ledger.dialog.expectedBack');
  static const ledgerDialogInstallmentMonths =
      ValueKey('web.ledger.dialog.installments.months');
  static const ledgerDialogInstallmentRate =
      ValueKey('web.ledger.dialog.installments.rate');

  // ── Bills ────────────────────────────────────────────────────────────────
  static const billsMonthStepper = ValueKey('web.bills.monthStepper');
  static const billsAddMenu = ValueKey('web.bills.addMenu');
  static const billsAddBill = ValueKey('web.bills.add.bill');
  static const billsAddReceivable = ValueKey('web.bills.add.receivable');
  static const billsAddSetAside = ValueKey('web.bills.add.setAside');
  static const billsAddInstallment = ValueKey('web.bills.add.installment');
  static const billsHero = ValueKey('web.bills.hero');
  static const billsHeroMarkPaid = ValueKey('web.bills.hero.markPaid');
  static const billsHeroEdit = ValueKey('web.bills.hero.edit');
  static const billsTabUpcoming = ValueKey('web.bills.tab.upcoming');
  static const billsTabSetAsides = ValueKey('web.bills.tab.setAsides');
  static const billsTabReceivables = ValueKey('web.bills.tab.receivables');
  static const billsTabInstallments = ValueKey('web.bills.tab.installments');
  static const billsTabPaid = ValueKey('web.bills.tab.paid');
  static const billsBatchSelect = ValueKey('web.bills.batch.select');
  static const billsBatchSettle = ValueKey('web.bills.batch.settle');
  static const billsBatchUndo = ValueKey('web.bills.batch.undo');
  static const billsBatchDelete = ValueKey('web.bills.batch.delete');
  static const billsRowCheckbox = ValueKey('web.bills.row.checkbox');
  static const billsRowMenu = ValueKey('web.bills.row.menu');
  static const billsRowMarkUnpaid = ValueKey('web.bills.row.markUnpaid');
  static const billsRowEdit = ValueKey('web.bills.row.edit');
  static const billsRowDelete = ValueKey('web.bills.row.delete');
  static const billsRowStatementItems =
      ValueKey('web.bills.row.statementItems');
  static const billsThisMonth = ValueKey('web.bills.thisMonth');
  static const billsByAccount = ValueKey('web.bills.byAccount');
  static const billsComingUp = ValueKey('web.bills.comingUp');
  static const billsCreditCards = ValueKey('web.bills.creditCards');
  static const billsPayCard = ValueKey('web.bills.payCard');
  static const billsSettleAmount = ValueKey('web.bills.settle.amount');
  static const billsSettleAccount = ValueKey('web.bills.settle.account');
  static const billsSettleDestination =
      ValueKey('web.bills.settle.destination');
  static const billsSettleDate = ValueKey('web.bills.settle.date');
  static const billsSettleAlreadyLogged =
      ValueKey('web.bills.settle.alreadyLogged');
  static const billsSettleCancel = ValueKey('web.bills.settle.cancel');
  static const billsSettleConfirm = ValueKey('web.bills.settle.confirm');
  static const billsDialogCancel = ValueKey('web.bills.dialog.cancel');
  static const billsDialogSubmit = ValueKey('web.bills.dialog.submit');
  static const billsDialogMoreOptions =
      ValueKey('web.bills.dialog.moreOptions');
  static const billsStatementClose = ValueKey('web.bills.statement.close');
  static const billsStatementPayNow = ValueKey('web.bills.statement.payNow');
  static const billsListCard = ValueKey('web.bills.list');
  static const billsTabSummary = ValueKey('web.bills.list.summary');
  static const billsBatchBar = ValueKey('web.bills.batch.bar');
  static const billsRowSettle = ValueKey('web.bills.row.settle');
  static const billsHeroReminder = ValueKey('web.bills.hero.reminder');
  static const billsCreditCardsEmpty = ValueKey('web.bills.creditCards.empty');
  static const billsFormName = ValueKey('web.bills.form.name');
  static const billsFormType = ValueKey('web.bills.form.type');
  static const billsFormAmount = ValueKey('web.bills.form.amount');
  static const billsFormDueDay = ValueKey('web.bills.form.dueDay');
  static const billsFormDate = ValueKey('web.bills.form.date');
  static const billsFormAccount = ValueKey('web.bills.form.account');
  static const billsFormDestination = ValueKey('web.bills.form.destination');
  static const billsFormCategory = ValueKey('web.bills.form.category');
  static const billsFormRepeats = ValueKey('web.bills.form.repeats');
  static const billsFormRecurrence = ValueKey('web.bills.form.recurrence');
  static const billsFormScope = ValueKey('web.bills.form.scope');
  static const billsFormReminder = ValueKey('web.bills.form.reminder');
  static const billsFormReminderDays = ValueKey('web.bills.form.reminderDays');
  static const billsFormNote = ValueKey('web.bills.form.note');
  static const billsFormCard = ValueKey('web.bills.form.card');
  static const billsFormTotal = ValueKey('web.bills.form.total');
  static const billsFormStartMonth = ValueKey('web.bills.form.startMonth');
  static const billsFormMonths = ValueKey('web.bills.form.months');
  static const billsFormInterest = ValueKey('web.bills.form.interest');
  static const billsFormMonthly = ValueKey('web.bills.form.monthly');
  static const billsFormPurchaseDate = ValueKey('web.bills.form.purchaseDate');
  static const billsFormDeferral = ValueKey('web.bills.form.deferral');
  static const billsScopeOnlyThisMonth =
      ValueKey('web.bills.scope.onlyThisMonth');
  static const billsScopeThisAndFuture =
      ValueKey('web.bills.scope.thisAndFuture');
  static const billsScopeConfirm = ValueKey('web.bills.scope.confirm');
  static const billsUndoRemoveTransaction =
      ValueKey('web.bills.undo.removeTransaction');
  static const billsUndoConfirm = ValueKey('web.bills.undo.confirm');

  // ── Budget ───────────────────────────────────────────────────────────────
  static const budgetMonthStepper = ValueKey('web.budget.monthStepper');
  static const budgetManageGroups = ValueKey('web.budget.manageGroups');
  static const budgetPaceRing = ValueKey('web.budget.paceRing');
  static const budgetGroupDonut = ValueKey('web.budget.groupDonut');
  static const budgetTable = ValueKey('web.budget.table');
  static const budgetRowGroup = ValueKey('web.budget.row.group');
  static const budgetRowAllocated = ValueKey('web.budget.row.allocated');
  static const budgetRowRemove = ValueKey('web.budget.row.remove');
  static const budgetAddRowMode = ValueKey('web.budget.addRow.mode');
  static const budgetAddRowPicker = ValueKey('web.budget.addRow.picker');
  static const budgetAddRowNewCategory =
      ValueKey('web.budget.addRow.newCategory');
  static const budgetAddRowGroup = ValueKey('web.budget.addRow.group');
  static const budgetAddRowAmount = ValueKey('web.budget.addRow.amount');
  static const budgetAddRowAdd = ValueKey('web.budget.addRow.add');
  static const budgetGroupsAdd = ValueKey('web.budget.groups.add');
  static const budgetGroupsRename = ValueKey('web.budget.groups.rename');
  static const budgetGroupsDelete = ValueKey('web.budget.groups.delete');
  static const budgetGroupsClose = ValueKey('web.budget.groups.close');
  static const budgetHeroPacePill = ValueKey('web.budget.hero.pacePill');
  static const budgetEmptyState = ValueKey('web.budget.emptyState');
  static const budgetTableHeader = ValueKey('web.budget.table.header');
  static const budgetDraftRow = ValueKey('web.budget.draftRow');
  static const budgetNewCategoryName = ValueKey('web.budget.newCategory.name');
  static const budgetNewCategoryType = ValueKey('web.budget.newCategory.type');
  static const budgetNewCategoryColor =
      ValueKey('web.budget.newCategory.color');
  static const budgetNewCategoryIcon = ValueKey('web.budget.newCategory.icon');
  static const budgetNewCategoryIconMore =
      ValueKey('web.budget.newCategory.icon.more');
  static const budgetNewCategoryExclude =
      ValueKey('web.budget.newCategory.exclude');
  static const budgetNewCategoryCreate =
      ValueKey('web.budget.newCategory.create');
  static const budgetNewCategoryCancel =
      ValueKey('web.budget.newCategory.cancel');
  static const budgetGroupsRenameField =
      ValueKey('web.budget.groups.rename.field');
  static const budgetGroupsRenameSave =
      ValueKey('web.budget.groups.rename.save');
  static const budgetGroupsRenameCancel =
      ValueKey('web.budget.groups.rename.cancel');

  /// One table group header (the subtotal row) by group id.
  static ValueKey<String> budgetGroup(String groupId) =>
      ValueKey('web.budget.group.$groupId');

  /// One category / savings row by its budget key (category or account id).
  static ValueKey<String> budgetRow(String id) =>
      ValueKey('web.budget.row.$id');

  /// The status pill of one budget row.
  static ValueKey<String> budgetStatus(String id) =>
      ValueKey('web.budget.status.$id');

  /// One legend line of the allocation donut.
  static ValueKey<String> budgetLegend(String groupId) =>
      ValueKey('web.budget.legend.$groupId');

  /// One row of the Manage groups dialog.
  static ValueKey<String> budgetGroupRow(String groupId) =>
      ValueKey('web.budget.groups.row.$groupId');

  // ── History ──────────────────────────────────────────────────────────────
  static const historyLiveCard = ValueKey('web.history.liveCard');
  static const historyStatStrip = ValueKey('web.history.statStrip');
  static const historyCashFlowTrend = ValueKey('web.history.cashFlowTrend');
  static const historyCumulativeSavings =
      ValueKey('web.history.cumulativeSavings');
  static const historyEndingCash = ValueKey('web.history.endingCash');
  static const historyMonthlyTable = ValueKey('web.history.monthlyTable');
  static const historySpendingByCategory =
      ValueKey('web.history.spendingByCategory');
  static const historyMonthDetail = ValueKey('web.history.monthDetail');
  static const historyMonthDetailOpenLedger =
      ValueKey('web.history.monthDetail.openLedger');
  static const historyMonthDetailClose =
      ValueKey('web.history.monthDetail.close');
  static const historyRange = ValueKey('web.history.range');
  static const historyLiveCardOpen = ValueKey('web.history.liveCard.open');

  /// The Month cell of one summary row in the monthly table.
  static ValueKey<String> historyMonthRow(String monthKey) =>
      ValueKey('web.history.monthRow.$monthKey');

  // ── Setup & Accounts ─────────────────────────────────────────────────────
  static const setupAddAccount = ValueKey('web.setup.addAccount');
  static const setupTabAccounts = ValueKey('web.setup.tab.accounts');
  static const setupTabCategories = ValueKey('web.setup.tab.categories');
  static const setupStatStrip = ValueKey('web.setup.statStrip');
  static const setupAccountsTable = ValueKey('web.setup.accountsTable');
  static const setupRowType = ValueKey('web.setup.row.type');
  static const setupRowAddPocket = ValueKey('web.setup.row.addPocket');
  static const setupRowEdit = ValueKey('web.setup.row.edit');
  static const setupRowDelete = ValueKey('web.setup.row.delete');
  static const setupCategoriesTable = ValueKey('web.setup.categoriesTable');
  static const setupCategoryName = ValueKey('web.setup.category.name');
  static const setupCategoryIcon = ValueKey('web.setup.category.icon');
  static const setupCategoryType = ValueKey('web.setup.category.type');
  static const setupCategoryColor = ValueKey('web.setup.category.color');
  static const setupCategoryExclude = ValueKey('web.setup.category.exclude');
  static const setupCategoryDelete = ValueKey('web.setup.category.delete');
  static const setupCategoryAddRow = ValueKey('web.setup.category.addRow');
  static const setupCategoryAdd = ValueKey('web.setup.category.add');
  static const setupFormName = ValueKey('web.setup.form.name');
  static const setupFormCategory = ValueKey('web.setup.form.category');
  static const setupFormBalance = ValueKey('web.setup.form.balance');
  static const setupFormIcon = ValueKey('web.setup.form.icon');
  static const setupFormColor = ValueKey('web.setup.form.color');
  static const setupFormGoalTarget = ValueKey('web.setup.form.goalTarget');
  static const setupFormMaturity = ValueKey('web.setup.form.maturity');
  static const setupFormCustodianLink =
      ValueKey('web.setup.form.custodianLink');
  static const setupFormCreditFold = ValueKey('web.setup.form.creditFold');
  static const setupFormDelete = ValueKey('web.setup.form.delete');
  static const setupFormCancel = ValueKey('web.setup.form.cancel');
  static const setupFormSave = ValueKey('web.setup.form.save');
  static const setupRowMenu = ValueKey('web.setup.row.menu');
  static const setupRowArchive = ValueKey('web.setup.row.archive');
  static const setupEmptyAddAccount = ValueKey('web.setup.empty.addAccount');
  static const setupStatLiquid = ValueKey('web.setup.stat.liquid');
  static const setupStatSavings = ValueKey('web.setup.stat.savings');
  static const setupStatCreditOwed = ValueKey('web.setup.stat.creditOwed');
  static const setupStatCreditAvailable =
      ValueKey('web.setup.stat.creditAvailable');
  static const setupRowNeedsFix = ValueKey('web.setup.row.needsFix');
  static const setupRowMeter = ValueKey('web.setup.row.meter');
  static const setupFormCreditLimit = ValueKey('web.setup.form.creditLimit');
  static const setupFormCardPreset = ValueKey('web.setup.form.cardPreset');
  static const setupFormStatementDay = ValueKey('web.setup.form.statementDay');
  static const setupFormMinimumFixed = ValueKey('web.setup.form.minimumFixed');
  static const setupFormFinanceRate = ValueKey('web.setup.form.financeRate');

  // ── Goals ────────────────────────────────────────────────────────────────
  static const goalsAddGoal = ValueKey('web.goals.addGoal');
  static const goalsHero = ValueKey('web.goals.hero');
  static const goalsGrid = ValueKey('web.goals.grid');
  static const goalsCardSetMonthly = ValueKey('web.goals.card.setMonthly');
  static const goalsCardMarkSpent = ValueKey('web.goals.card.markSpent');
  static const goalsCardStartAgain = ValueKey('web.goals.card.startAgain');
  static const goalsSavingsTable = ValueKey('web.goals.savingsTable');
  static const goalsFundingNote = ValueKey('web.goals.fundingNote');
  static const goalsOpenBudget = ValueKey('web.goals.openBudget');
  static const goalsManageSetup = ValueKey('web.goals.manageSetup');
  static const goalsEmptyAddGoal = ValueKey('web.goals.empty.addGoal');
  static const goalsCardMenu = ValueKey('web.goals.card.menu');
  static const goalsCardEdit = ValueKey('web.goals.card.edit');
  static const goalsCardArchive = ValueKey('web.goals.card.archive');
  static const goalsNoteStartAgain = ValueKey('web.goals.note.startAgain');
  static const goalsAddGoalDialog = ValueKey('web.goals.addGoal.dialog');
  static const goalsAddGoalName = ValueKey('web.goals.addGoal.name');
  static const goalsAddGoalTarget = ValueKey('web.goals.addGoal.target');
  static const goalsAddGoalStoredIn = ValueKey('web.goals.addGoal.storedIn');
  static const goalsAddGoalSubmit = ValueKey('web.goals.addGoal.submit');
  static const goalsStartAgainDialog = ValueKey('web.goals.startAgain.dialog');
  static const goalsStartAgainGoal = ValueKey('web.goals.startAgain.goal');
  static const goalsStartAgainTarget = ValueKey('web.goals.startAgain.target');
  static const goalsStartAgainSubmit = ValueKey('web.goals.startAgain.submit');

  // ── More (narrow layout) ─────────────────────────────────────────────────
  static const moreOpenNudgy = ValueKey('web.more.openNudgy');
  static const moreThemeToggle = ValueKey('web.more.themeToggle');
  static const moreSetup = ValueKey('web.more.setup');
  static const moreSignOut = ValueKey('web.more.signOut');
}
