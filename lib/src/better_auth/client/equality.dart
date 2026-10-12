import 'package:re_better_auth/src/nanostores/atom.dart';

/// Deep structural equality for decoded JSON: maps, lists and primitives.
bool isJsonEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!isJsonEqual(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (!b.containsKey(key) || !isJsonEqual(value, b[key])) return false;
    }
    return true;
  }
  if (a is Map || a is List || b is Map || b is List) return false;
  return a == b;
}

/// Aborts every `set` on [store] whose value [isEqual] the current one.
///
/// Returns the function that removes the gate.
void Function() withEquality<T>(
  Atom<T> store,
  bool Function(T a, T b) isEqual,
) => onSet<T>(store, (event) {
  if (isEqual(store.value, event.newValue)) event.abort();
});
