import 'package:intermittent_fasting/models/finance/finance_category.dart';
import 'package:intermittent_fasting/models/finance/financial_account.dart';
import 'package:intermittent_fasting/models/finance/transaction_record.dart';
import 'package:intermittent_fasting/utils/finance_flows.dart';
import 'package:intermittent_fasting/utils/finance_format.dart';

/// Nudgy's `queryFinance`: a sum or group-by over the ledger that no screen
/// shows (Plan 065 phase 3).
///
/// Pure and stateless. Every figure comes from the predicates in
/// `finance_flows.dart`, the same ones the screens use, so a month's `spend`
/// here is the ledger's month spend and a month's `setAside` is the History
/// grid's. This file holds no rule of its own about what counts.

enum FinanceMetric { spend, income, net, count, setAside }

enum FinanceGroupBy { none, category, account, month, description }

/// One line of a [FinanceQueryResult].
class FinanceQueryGroup {
  const FinanceQueryGroup(this.label, this.value, this.entries);

  final String label;
  final double value;

  /// Ledger entries behind [value]. A transfer counts once.
  final int entries;
}

/// The filters and shape of one query. Text filters match names, never ids.
class FinanceQuery {
  const FinanceQuery({
    required this.metric,
    this.groupBy = FinanceGroupBy.none,
    this.category = '',
    this.account = '',
    this.query = '',
    this.type = '',
    this.from,
    this.to,
    this.month = '',
    this.top = 10,
    this.average = false,
  });

  final FinanceMetric metric;
  final FinanceGroupBy groupBy;

  /// Category name or part of it.
  final String category;

  /// Account name or part of it. Matches the account the entry is on.
  final String account;

  /// Words matched in any order against description, note, category,
  /// account and who owes it.
  final String query;

  /// `outflow`, `inflow` or `transfer`; empty for all.
  final String type;

  /// Inclusive day range. Either side may be open; both override [month].
  final DateTime? from;
  final DateTime? to;

  /// `YYYY-MM`. Used when [from] and [to] are both null.
  final String month;

  /// Most groups to list. Month groups are never cut.
  final int top;

  /// Divide by the months covered, counting a month with no activity as 0.
  final bool average;
}

class FinanceQueryResult {
  const FinanceQueryResult({
    required this.query,
    required this.groups,
    required this.otherGroups,
    required this.otherValue,
    required this.total,
    required this.entries,
    required this.from,
    required this.to,
    required this.months,
    required this.firstLedgerMonth,
    required this.clampedStart,
    required this.clampedEnd,
    this.error,
  });

  const FinanceQueryResult.error(this.query, String this.error)
      : groups = const [],
        otherGroups = 0,
        otherValue = 0,
        total = 0,
        entries = 0,
        from = null,
        to = null,
        months = const [],
        firstLedgerMonth = null,
        clampedStart = false,
        clampedEnd = false;

  final FinanceQuery query;

  /// The listed groups, biggest first (months in calendar order).
  final List<FinanceQueryGroup> groups;

  /// Groups left out by [FinanceQuery.top], and their combined value.
  final int otherGroups;
  final double otherValue;

  /// The figure over every matching entry, listed or not.
  final double total;
  final int entries;

  /// The exact day range searched; null when the ledger is empty.
  final DateTime? from;
  final DateTime? to;

  /// Every month key the range covers, oldest first.
  final List<String> months;

  /// Month of the oldest ledger entry; null when the ledger is empty.
  final String? firstLedgerMonth;

  /// The asked start was before [firstLedgerMonth] and was moved to it.
  final bool clampedStart;

  /// The asked end was after today and was moved to today.
  final bool clampedEnd;

  /// Set when the query cannot run; every other field is empty.
  final String? error;

  /// [total] per month covered, when [FinanceQuery.average] is set.
  double? get monthlyAverage =>
      query.average && months.isNotEmpty ? total / months.length : null;

  /// [value] per month covered, when [FinanceQuery.average] is set.
  double? averageOf(double value) =>
      query.average && months.isNotEmpty ? value / months.length : null;
}

/// One-line definition of [metric], said with every result so the model
/// cannot read one figure as another.
String financeMetricDefinition(FinanceMetric metric) => switch (metric) {
      FinanceMetric.spend => 'spend = outflows the app counts as spending: '
          'excludes transfers, reimbursables, installment purchase records '
          '(the monthly payments count) and "exclude from totals" categories',
      FinanceMetric.income => 'income = inflows the app counts as income: '
          'excludes transfers, repayments of reimbursables and loans, and '
          '"exclude from totals" categories',
      FinanceMetric.net => 'net = income minus spend, by the same rules as '
          'each (transfers, reimbursables and installment purchase records '
          'are in neither)',
      FinanceMetric.count => 'count = ledger entries that match the filters; '
          'a transfer counts once',
      FinanceMetric.setAside => 'setAside = money moved into savings pockets '
          '(savings, goals, sinking funds) by transfer, less money moved back '
          'out; a move between two pockets nets to zero',
    };

/// Runs [q] over the ledger. [today] bounds an open or future range.
FinanceQueryResult runFinanceQuery(
  FinanceQuery q, {
  required List<TransactionRecord> transactions,
  required List<FinancialAccount> accounts,
  required List<FinanceCategory> categories,
  required DateTime today,
}) {
  if (q.metric == FinanceMetric.setAside &&
      q.groupBy == FinanceGroupBy.category) {
    return FinanceQueryResult.error(
        q,
        'setAside has no category: it is made of transfers. Group it by '
        'account, month or description instead.');
  }
  if (q.month.isNotEmpty &&
      !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(q.month)) {
    return FinanceQueryResult.error(q, 'month must be YYYY-MM.');
  }
  if (q.from != null && q.to != null && q.from!.isAfter(q.to!)) {
    return FinanceQueryResult.error(q, 'from is after to.');
  }
  final day0 = DateTime(today.year, today.month, today.day);
  final accountNames = {for (final a in accounts) a.id: a.name};
  final categoryNames = {for (final c in categories) c.id: c.name};

  if (transactions.isEmpty) {
    return FinanceQueryResult(
      query: q,
      groups: const [],
      otherGroups: 0,
      otherValue: 0,
      total: 0,
      entries: 0,
      from: null,
      to: null,
      months: const [],
      firstLedgerMonth: null,
      clampedStart: false,
      clampedEnd: false,
    );
  }

  // ── Range ────────────────────────────────────────────────────────────────
  // From the dates, not the stored month keys: one malformed key must not
  // break every query.
  final oldest =
      transactions.map((t) => t.date).reduce((a, b) => a.isBefore(b) ? a : b);
  final ledgerStart = DateTime(oldest.year, oldest.month);
  final firstMonth = toMonthKey(ledgerStart);
  final useDates = q.from != null || q.to != null;
  final monthOnly = !useDates && q.month.isNotEmpty;

  DateTime askedFrom;
  DateTime askedTo;
  if (useDates) {
    askedFrom = q.from == null ? ledgerStart : _day(q.from!);
    askedTo = q.to == null ? day0 : _day(q.to!);
  } else if (monthOnly) {
    askedFrom = _monthStart(q.month);
    askedTo = _monthEnd(q.month);
  } else {
    askedFrom = ledgerStart;
    askedTo = day0;
  }
  final clampedStart = askedFrom.isBefore(ledgerStart) && !monthOnly;
  final clampedEnd = askedTo.isAfter(day0) && !monthOnly;
  final from = clampedStart ? ledgerStart : askedFrom;
  final to = clampedEnd ? day0 : askedTo;
  // Empty when the whole range is before the ledger's first month.
  final months = from.isAfter(to) ? const <String>[] : _monthsBetween(from, to);

  // ── Filters ──────────────────────────────────────────────────────────────
  final words = _words(q.query);
  final categoryQuery = q.category.trim().toLowerCase();
  final accountQuery = q.account.trim().toLowerCase();

  bool isTransfer(TransactionRecord t) =>
      t.transferGroupId != null || t.type == TransactionType.transfer;

  final matched = transactions.where((t) {
    if (monthOnly) {
      if (t.month != q.month) return false;
    } else {
      final d = _day(t.date);
      if (d.isBefore(from) || d.isAfter(to)) return false;
    }
    final kind = isTransfer(t) ? 'transfer' : t.type.name;
    if (q.type.isNotEmpty && kind != q.type) return false;
    final account = accountNames[t.accountId] ?? '';
    final category = categoryNames[t.categoryId] ?? '';
    if (accountQuery.isNotEmpty &&
        !account.toLowerCase().contains(accountQuery)) {
      return false;
    }
    if (categoryQuery.isNotEmpty &&
        !category.toLowerCase().contains(categoryQuery)) {
      return false;
    }
    if (words.isNotEmpty) {
      final haystack = [
        t.description,
        t.note ?? '',
        category,
        account,
        accountNames[t.transferToAccountId] ?? '',
        t.owedBy ?? '',
      ].join(' ').toLowerCase();
      if (!words.every(haystack.contains)) return false;
    }
    return true;
  }).toList();

  // ── Metric ───────────────────────────────────────────────────────────────
  // Built from the FULL ledger: a repayment is matched to its reimbursable
  // even when the outflow is outside the range or the filters.
  final reimb = reimbursementReceivableIds(transactions);
  final excluded = excludedCashFlowCategoryIds(categories);
  final pockets = savingsPocketIds(accounts);

  bool spends(TransactionRecord t) => isSpendingOutflow(t, excluded);
  bool earns(TransactionRecord t) => isIncomeInflow(t, reimb, excluded);

  final bool Function(TransactionRecord) counts = switch (q.metric) {
    FinanceMetric.spend => spends,
    FinanceMetric.income => earns,
    FinanceMetric.net => (t) => spends(t) || earns(t),
    // A transfer is one movement: its inflow leg is not a second entry.
    FinanceMetric.count => (t) =>
        !(isTransfer(t) && t.type == TransactionType.inflow),
    FinanceMetric.setAside => (t) => savingsContribution([t], pockets) != 0,
  };

  double valueOf(List<TransactionRecord> rows) => switch (q.metric) {
        FinanceMetric.spend ||
        FinanceMetric.income =>
          rows.fold(0.0, (s, t) => s + t.amount),
        FinanceMetric.net =>
          rows.fold(0.0, (s, t) => s + (earns(t) ? t.amount : -t.amount)),
        FinanceMetric.count => rows.length.toDouble(),
        FinanceMetric.setAside => savingsContribution(rows, pockets),
      };

  final counted = matched.where(counts).toList();

  // ── Groups ───────────────────────────────────────────────────────────────
  final byKey = <String, List<TransactionRecord>>{};
  final labels = <String, String>{};
  for (final t in counted) {
    final (key, label) = switch (q.groupBy) {
      FinanceGroupBy.none => ('', 'All'),
      FinanceGroupBy.category => (
          t.categoryId,
          categoryNames[t.categoryId] ?? 'Uncategorised'
        ),
      FinanceGroupBy.account => (
          t.accountId,
          accountNames[t.accountId] ?? 'Unknown account'
        ),
      FinanceGroupBy.month => (t.month, t.month),
      FinanceGroupBy.description => (
          t.description.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '),
          t.description.trim()
        ),
    };
    (byKey[key] ??= []).add(t);
    labels.putIfAbsent(key, () => label.isEmpty ? '(no description)' : label);
  }

  var groups = [
    for (final e in byKey.entries)
      FinanceQueryGroup(labels[e.key]!, valueOf(e.value), e.value.length),
  ];
  var otherGroups = 0;
  var otherValue = 0.0;
  if (q.groupBy == FinanceGroupBy.month) {
    // Every month in the range, in order: an empty month is a real 0, and
    // the average already counts it.
    final have = {for (final g in groups) g.label: g};
    final keys = monthOnly ? [q.month] : months;
    groups = [
      for (final m in keys) have[m] ?? FinanceQueryGroup(m, 0, 0),
    ];
  } else if (q.groupBy != FinanceGroupBy.none) {
    groups.removeWhere((g) => g.value == 0);
    groups.sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final top = q.top <= 0 ? 10 : q.top;
    if (groups.length > top) {
      final rest = groups.sublist(top);
      otherGroups = rest.length;
      otherValue = rest.fold(0.0, (s, g) => s + g.value);
      groups = groups.sublist(0, top);
    }
  }

  return FinanceQueryResult(
    query: q,
    groups: groups,
    otherGroups: otherGroups,
    otherValue: otherValue,
    total: valueOf(counted),
    entries: counted.length,
    from: from,
    to: to,
    months: monthOnly ? [q.month] : months,
    firstLedgerMonth: firstMonth,
    clampedStart: clampedStart,
    clampedEnd: clampedEnd,
  );
}

/// The tool result for [r]: one line per group, the total, the exact range
/// and months covered, and the metric's definition. [today] marks a month
/// still in progress.
String describeFinanceQuery(FinanceQueryResult r, DateTime today) {
  final q = r.query;
  final isCount = q.metric == FinanceMetric.count;
  String fig(double v) => isCount
      ? '${v.round()}'
      : v < 0
          ? '−${formatPeso(-v)}'
          : formatPeso(v);
  String avg(double v) {
    final a = r.averageOf(v);
    return a == null ? '' : ' · avg ${fig(a)}/month';
  }

  final shape = q.groupBy == FinanceGroupBy.none
      ? q.metric.name
      : '${q.metric.name} by ${q.groupBy.name}';
  final filters = [
    if (q.category.isNotEmpty) 'category "${q.category}"',
    if (q.account.isNotEmpty) 'account "${q.account}"',
    if (q.query.isNotEmpty) 'text "${q.query}"',
    if (q.type.isNotEmpty) 'type ${q.type}',
  ];
  final lines = <String>[];

  final from = r.from;
  final to = r.to;
  if (from == null || to == null) {
    return '$shape: the ledger is empty, so there is nothing to count.\n'
        'Definition: ${financeMetricDefinition(q.metric)}.';
  }
  final first = r.firstLedgerMonth!;
  if (r.months.isEmpty ||
      (q.from == null &&
          q.to == null &&
          q.month.isNotEmpty &&
          q.month.compareTo(first) < 0)) {
    return '$shape: the range ends before the ledger begins (first entry '
        'in $first), so there is nothing to count. Check the year.\n'
        'Definition: ${financeMetricDefinition(q.metric)}.';
  }

  final current = toMonthKey(today);
  final inProgress = r.months.last == current && !to.isBefore(_day(today))
      ? ', $current in progress'
      : '';
  final monthSpan = r.months.length == 1
      ? '1 month: ${r.months.first}'
      : '${r.months.length} months: ${r.months.first} to ${r.months.last}';
  lines.add('$shape, ${_iso(from)} to ${_iso(to)} ($monthSpan$inProgress)'
      '${filters.isEmpty ? '' : '; filters: ${filters.join(', ')}'}.');
  if (r.clampedStart) {
    lines.add('The range was clamped to start at the ledger\'s first month, '
        '$first: nothing was logged before it.');
  }
  if (r.clampedEnd) {
    lines.add('The range was cut to end today: nothing is logged after it.');
  }

  if (q.groupBy != FinanceGroupBy.none) {
    if (r.groups.isEmpty) lines.add('No entries matched.');
    for (final g in r.groups) {
      final n = isCount ? '' : ' (${_entries(g.entries)})';
      lines.add('${g.label}: ${fig(g.value)}$n${avg(g.value)}');
    }
    if (r.otherGroups > 0) {
      lines.add('${r.otherGroups} more groups, not listed: '
          '${fig(r.otherValue)} together.');
    }
  }

  final entries = isCount ? '' : ' over ${_entries(r.entries)}';
  final average = r.monthlyAverage;
  lines.add('Total: ${fig(r.total)}$entries.'
      '${average == null ? '' : ' Average: ${fig(average)} a month over '
          '${r.months.length} months; a month with no activity counts as 0.'}');
  lines.add('Definition: ${financeMetricDefinition(q.metric)}.');
  return lines.join('\n');
}

String _entries(int n) => n == 1 ? '1 entry' : '$n entries';

String _iso(DateTime d) =>
    '${toMonthKey(d)}-${d.day.toString().padLeft(2, '0')}';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _monthStart(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]));
}

DateTime _monthEnd(String key) {
  final start = _monthStart(key);
  return DateTime(start.year, start.month + 1, 0);
}

List<String> _monthsBetween(DateTime from, DateTime to) {
  final out = <String>[];
  var m = DateTime(from.year, from.month);
  final last = DateTime(to.year, to.month);
  while (!m.isAfter(last)) {
    out.add(toMonthKey(m));
    m = DateTime(m.year, m.month + 1);
  }
  return out;
}

List<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();
