import 'dart:async';

/// Receives an atom's new value and the value it replaced (`null` on subscribe).
typedef AtomListener<T> = void Function(T value, T? oldValue);

/// Runs when the first listener arrives; may return a cleanup for unmount.
typedef MountInitializer = void Function()? Function();

/// Delay between the last listener leaving and the mount cleanup running.
const Duration storeUnmountDelay = Duration(milliseconds: 1000);

final class _QueuedCall {
  _QueuedCall(this.listener, this.run);

  final Object listener;
  final void Function() run;
}

// Shared across atoms so nested updates notify in FIFO order.
final List<_QueuedCall> _listenerQueue = <_QueuedCall>[];
int _lqIndex = 0;

/// Port of nanostores `atom` with its `onMount` and `onSet` lifecycle.
class Atom<T> {
  /// Creates an atom holding [initialValue].
  Atom(T initialValue) : init = initialValue, _value = initialValue;

  /// The value the atom was created with.
  final T init;

  T _value;
  final List<AtomListener<T>> _listeners = <AtomListener<T>>[];
  final List<MountInitializer> _mountListeners = <MountInitializer>[];
  final List<void Function()> _unmountCallbacks = <void Function()>[];
  final List<void Function(AtomSetEvent<T> event)> _setListeners =
      <void Function(AtomSetEvent<T> event)>[];
  bool _active = false;

  /// The current value, read without mounting the atom.
  T get value => _value;

  /// Number of active listeners.
  int get lc => _listeners.length;

  /// Returns the value; with no listeners it mounts and schedules an unmount.
  T get() {
    if (lc == 0) {
      listen((_, _) {})();
    }
    return _value;
  }

  /// Stores [newValue] and notifies listeners when it differs from the old one.
  void set(T newValue) {
    if (_setListeners.isNotEmpty) {
      var aborted = false;
      final event = AtomSetEvent<T>._(newValue, () => aborted = true);
      for (final listener in _setListeners.reversed.toList()) {
        listener(event);
      }
      if (aborted) return;
    }
    final oldValue = _value;
    if (oldValue != newValue) {
      _value = newValue;
      notify(oldValue);
    }
  }

  /// Adds [listener] without calling it; returns the unsubscribe function.
  void Function() listen(AtomListener<T> listener) {
    if (lc == 0 && !_active && _mountListeners.isNotEmpty) {
      _active = true;
      for (final initialize in _mountListeners.reversed.toList()) {
        final destroy = initialize();
        if (destroy != null) _unmountCallbacks.add(destroy);
      }
    }
    _listeners.add(listener);
    return () {
      for (var i = _lqIndex + 1; i < _listenerQueue.length;) {
        if (identical(_listenerQueue[i].listener, listener)) {
          _listenerQueue.removeAt(i);
        } else {
          i++;
        }
      }
      final index = _listeners.indexWhere((l) => identical(l, listener));
      if (index != -1) {
        _listeners.removeAt(index);
        if (lc == 0) _off();
      }
    };
  }

  /// Like [listen], but calls [listener] immediately with the current value.
  void Function() subscribe(AtomListener<T> listener) {
    final unbind = listen(listener);
    listener(_value, null);
    return unbind;
  }

  /// Queues every listener with the current value and [oldValue].
  void notify([T? oldValue]) {
    final runListenerQueue = _listenerQueue.isEmpty;
    final value = _value;
    for (final listener in _listeners) {
      _listenerQueue.add(
        _QueuedCall(listener, () => listener(value, oldValue)),
      );
    }
    if (!runListenerQueue) return;
    try {
      for (_lqIndex = 0; _lqIndex < _listenerQueue.length; _lqIndex++) {
        _listenerQueue[_lqIndex].run();
      }
    } finally {
      _listenerQueue.clear();
      _lqIndex = 0;
    }
  }

  void _off() {
    if (_mountListeners.isEmpty) return;
    Timer(storeUnmountDelay, () {
      if (_active && lc == 0) {
        _active = false;
        final callbacks = List<void Function()>.of(_unmountCallbacks);
        _unmountCallbacks.clear();
        for (final destroy in callbacks) {
          destroy();
        }
      }
    });
  }
}

/// A pending [Atom.set]; calling [abort] keeps the old value.
final class AtomSetEvent<T> {
  AtomSetEvent._(this.newValue, this.abort);

  /// The value about to be stored.
  final T newValue;

  /// Cancels the write.
  final void Function() abort;
}

/// Runs [initialize] when [atom] gains its first listener; returns a remover.
void Function() onMount<T>(Atom<T> atom, MountInitializer initialize) {
  atom._mountListeners.add(initialize);
  return () => atom._mountListeners.remove(initialize);
}

/// Calls [listener] before every [Atom.set]; returns a remover.
void Function() onSet<T>(
  Atom<T> atom,
  void Function(AtomSetEvent<T> event) listener,
) {
  atom._setListeners.add(listener);
  return () => atom._setListeners.remove(listener);
}
