/// Called with `true` when the app gains focus.
typedef FocusListener = void Function(bool focused);

/// Source of app-focus events for session refetching (`FocusManager` in JS).
abstract interface class AuthFocusManager {
  /// Notifies listeners about a focus change.
  void setFocused(bool focused);

  /// Adds [listener]; returns the function that removes it.
  void Function() subscribe(FocusListener listener);

  /// Starts watching the platform; returns the teardown.
  void Function() setup();
}

/// Default manager: no platform source, listeners fire only on [setFocused].
class DefaultFocusManager implements AuthFocusManager {
  final Set<FocusListener> _listeners = <FocusListener>{};

  @override
  void Function() subscribe(FocusListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void setFocused(bool focused) {
    for (final listener in _listeners.toList()) {
      listener(focused);
    }
  }

  @override
  void Function() setup() => () {};
}

/// Process-wide focus manager, the Dart slot for `globalThis[kFocusManager]`.
AuthFocusManager? globalFocusManager;

/// The current focus manager, creating the default one on first use.
AuthFocusManager getGlobalFocusManager() =>
    globalFocusManager ??= DefaultFocusManager();
