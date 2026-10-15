/// Returns the first selected weekday whose early reminder is still ahead.
/// [startTarget] supplies the first allowed date and the local clock time.
DateTime? nextRepeatTarget(
  DateTime startTarget,
  int repeatDays,
  int leadMinutes,
  DateTime now,
) {
  if (repeatDays <= 0 || repeatDays > 127) return null;
  final firstDay = DateTime(
    startTarget.year,
    startTarget.month,
    startTarget.day,
  );
  for (var offset = 0; offset < 15; offset++) {
    final day = DateTime(firstDay.year, firstDay.month, firstDay.day + offset);
    if ((repeatDays & (1 << (day.weekday - 1))) == 0) continue;
    final target = DateTime(
      day.year,
      day.month,
      day.day,
      startTarget.hour,
      startTarget.minute,
    );
    if (target.subtract(Duration(minutes: leadMinutes)).isAfter(now)) {
      return target;
    }
  }
  return null;
}

/// First selected local day, including today when it is selected.
DateTime? nextRepeatDay(int repeatDays, DateTime now) {
  if (repeatDays <= 0 || repeatDays > 127) return null;
  final today = DateTime(now.year, now.month, now.day);
  for (var offset = 0; offset < 7; offset++) {
    final day = DateTime(today.year, today.month, today.day + offset);
    if ((repeatDays & (1 << (day.weekday - 1))) != 0) return day;
  }
  return null;
}

String repeatDaysLabel(int repeatDays) {
  const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return [
    for (var index = 0; index < 7; index++)
      if ((repeatDays & (1 << index)) != 0) labels[index],
  ].join(', ');
}
