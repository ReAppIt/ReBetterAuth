import 'package:flutter/foundation.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// Exposes an [Atom] as a [ValueListenable] (`useStore` of the react binding).
/// The first listener mounts the atom; notifies only when the value changes.
class AtomListenable<T> implements ValueListenable<T> {
  /// Wraps [store]; reading the initial snapshot mounts it briefly.
  AtomListenable(this.store) : _snapshot = store.get();

  /// The wrapped atom.
  final Atom<T> store;

  T _snapshot;
  final List<VoidCallback> _listeners = <VoidCallback>[];
  void Function()? _unbind;

  @override
  T get value => _unbind == null ? store.value : _snapshot;

  @override
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
    if (_unbind != null) return;
    _snapshot = store.value;
    _unbind = store.listen((value, _) {
      if (identical(_snapshot, value)) return;
      _snapshot = value;
      for (final callback in List<VoidCallback>.of(_listeners)) {
        callback();
      }
    });
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isNotEmpty) return;
    _unbind?.call();
    _unbind = null;
  }
}
