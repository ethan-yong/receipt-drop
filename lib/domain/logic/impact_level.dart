/// Qualitative spend-impact tier, derived from a real RM amount.
enum ImpactLevel { low, med, high }

/// Thresholds are placeholder defaults (not derived from real spend data) —
/// adjust once product has real-world distribution to tune against.
ImpactLevel deriveImpactLevel(double? amountMyr, {List<double>? historicalAmounts}) {
  if (amountMyr == null) return ImpactLevel.low;
  if (amountMyr < 15) return ImpactLevel.low;
  if (amountMyr < 60) return ImpactLevel.med;
  return ImpactLevel.high;
}

extension ImpactLevelX on ImpactLevel {
  String get label {
    switch (this) {
      case ImpactLevel.low:
        return 'Low';
      case ImpactLevel.med:
        return 'Med';
      case ImpactLevel.high:
        return 'High';
    }
  }

  /// Stored in `outbox_transactions.impact_user`.
  String get storageValue => name;
}

ImpactLevel? impactLevelFromStorage(String? value) {
  switch (value) {
    case 'low':
      return ImpactLevel.low;
    case 'med':
      return ImpactLevel.med;
    case 'high':
      return ImpactLevel.high;
    default:
      return null;
  }
}
