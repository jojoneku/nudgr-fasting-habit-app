/// Guards dates a language model hands back against year drift.
///
/// A model resolves "Sept 24" against the year it *believes* it is, which is
/// its training year, not the user's. The snapshot now states today's date,
/// which fixes most of it, but a model can still slip, and a slipped year is
/// silent: "Sept 24" lands two years back, outside every view the user checks,
/// and reads as lost data. These clamp the slip on the client, where the real
/// clock is.
///
/// The rule is deliberately narrow: only a date implausibly far in the past is
/// touched. Logging something from last week, last month, or most of last year
/// passes through untouched. What changes is a date old enough that the user
/// almost certainly did not mean it, and the confirm or review card still shows
/// the result, so a genuine old date can be put back by hand.
library;

/// How old a model-supplied date may be before it is treated as a year slip.
/// Ten months: a little under a year, so "Dec 20" said in early October still
/// means last December, while the same day two years back does not survive.
const int kStaleDateDays = 300;

/// Months back a model-supplied `YYYY-MM` may sit before it counts as a slip.
const int kStaleMonths = 11;

/// [date] with a slipped year replaced by the most recent plausible one.
///
/// Returns [date] unchanged unless it is more than [kStaleDateDays] before
/// [now]. A stale date moves to the same month and day in [now]'s year, or the
/// year before when that would land in the future and [allowFuture] is false
/// (a past purchase cannot be next month). A payback date may be in the future,
/// so with [allowFuture] the current year is kept.
DateTime rebaseStaleDate(DateTime date, DateTime now,
    {bool allowFuture = false}) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (today.difference(day).inDays <= kStaleDateDays) return date;

  var candidate = _sameDayIn(now.year, date);
  if (!allowFuture && candidate.isAfter(today)) {
    candidate = _sameDayIn(now.year - 1, date);
  }
  return DateTime(candidate.year, candidate.month, candidate.day, date.hour,
      date.minute, date.second);
}

/// A `YYYY-MM` [monthKey] with a slipped year replaced.
///
/// Unchanged unless more than [kStaleMonths] before [now]'s month. A stale key
/// moves to [now]'s year, then back one year if that would put it more than six
/// months ahead: bills and receivables are planned a little ahead, never most of
/// a year. Anything that is not a `YYYY-MM` is returned as-is for the caller's
/// own fallback to handle.
String rebaseStaleMonthKey(String monthKey, DateTime now) {
  final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(monthKey);
  if (match == null) return monthKey;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return monthKey;

  final current = now.year * 12 + now.month;
  if (current - (year * 12 + month) <= kStaleMonths) return monthKey;

  var rebasedYear = now.year;
  if ((rebasedYear * 12 + month) - current > 6) rebasedYear -= 1;
  return '$rebasedYear-${month.toString().padLeft(2, '0')}';
}

/// [date]'s month and day in [year], with Feb 29 clamped to Feb 28 rather than
/// rolling over into March.
DateTime _sameDayIn(int year, DateTime date) {
  final lastDay = DateTime(year, date.month + 1, 0).day;
  return DateTime(year, date.month, date.day > lastDay ? lastDay : date.day);
}
