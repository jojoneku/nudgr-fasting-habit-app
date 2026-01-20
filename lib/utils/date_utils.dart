bool isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String formatTimeWithDay(DateTime dateTime, DateTime referenceDate) {
  int hour = dateTime.hour;
  String period = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12;
  if (hour == 0) hour = 12;
  String timeStr = '$hour:${dateTime.minute.toString().padLeft(2, '0')} $period';

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final tomorrow = today.add(const Duration(days: 1));
  
  final dateToCheck = DateTime(dateTime.year, dateTime.month, dateTime.day);
  final refDate = DateTime(referenceDate.year, referenceDate.month, referenceDate.day);

  // If the date is the same as the reference date, we don't need a suffix
  if (dateToCheck.isAtSameMomentAs(refDate)) {
    return timeStr;
  }

  if (dateToCheck.isAtSameMomentAs(today)) {
    return '$timeStr (Today)';
  } else if (dateToCheck.isAtSameMomentAs(yesterday)) {
    return '$timeStr (Yesterday)';
  } else if (dateToCheck.isAtSameMomentAs(tomorrow)) {
    return '$timeStr (Tom)';
  }

  // Fallback to +/- days
  if (dateToCheck.isAfter(refDate)) {
    final diff = dateToCheck.difference(refDate).inDays;
    return '$timeStr (+$diff d)';
  } else {
     final diff = refDate.difference(dateToCheck).inDays;
     return '$timeStr (-$diff d)';
  }
}
