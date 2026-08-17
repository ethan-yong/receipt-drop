/// Local-clock helpers for spend-map day vs night tile styling.
///
/// Light: 06:00 inclusive through 17:59. Dark: 18:00 through 05:59.
/// Deliberately clock-based (not sunrise/sunset, not system theme).

/// Whether the map should use the night JSON style at [localNow].
bool isMapNightMode(DateTime localNow) {
  final hour = localNow.hour;
  return hour < 6 || hour >= 18;
}

/// Duration until the next 06:00 or 18:00 local boundary after [localNow].
///
/// Always positive so a single [Timer] can wake and re-apply the style.
Duration untilNextMapStyleChange(DateTime localNow) {
  final dayStart = DateTime(localNow.year, localNow.month, localNow.day, 6);
  final nightStart = DateTime(localNow.year, localNow.month, localNow.day, 18);
  final nextDayStart = dayStart.add(const Duration(days: 1));

  if (localNow.isBefore(dayStart)) {
    return dayStart.difference(localNow);
  }
  if (localNow.isBefore(nightStart)) {
    return nightStart.difference(localNow);
  }
  return nextDayStart.difference(localNow);
}
