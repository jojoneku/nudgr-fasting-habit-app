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

  // ── Goals ────────────────────────────────────────────────────────────────
  static const goalsAddGoal = ValueKey('web.goals.addGoal');
  static const goalsHero = ValueKey('web.goals.hero');
  static const goalsGrid = ValueKey('web.goals.grid');
  static const goalsCardSetMonthly = ValueKey('web.goals.card.setMonthly');
  static const goalsCardMarkSpent = ValueKey('web.goals.card.markSpent');
  static const goalsCardStartAgain = ValueKey('web.goals.card.startAgain');
  static const goalsSavingsTable = ValueKey('web.goals.savingsTable');
  static const goalsFundingNote = ValueKey('web.goals.fundingNote');

  // ── More (narrow layout) ─────────────────────────────────────────────────
  static const moreOpenNudgy = ValueKey('web.more.openNudgy');
  static const moreThemeToggle = ValueKey('web.more.themeToggle');
  static const moreSetup = ValueKey('web.more.setup');
  static const moreSignOut = ValueKey('web.more.signOut');
}
