/// Deep-merges [base] over [defaults] like `defu`: [base] wins, maps merge,
/// lists concatenate, and `null` values in [base] are skipped.
Map<String, Object?> defu(
  Map<String, Object?> base,
  Map<String, Object?> defaults,
) {
  final object = Map<String, Object?>.of(defaults);
  base.forEach((key, value) {
    if (value == null) return;
    final existing = object[key];
    if (value is List<Object?> && existing is List<Object?>) {
      object[key] = <Object?>[...value, ...existing];
    } else if (value is Map<String, Object?> &&
        existing is Map<String, Object?>) {
      object[key] = defu(value, existing);
    } else {
      object[key] = value;
    }
  });
  return object;
}
