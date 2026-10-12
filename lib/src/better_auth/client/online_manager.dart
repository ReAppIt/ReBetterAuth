/// Called with the new connectivity state.
typedef OnlineListener = void Function(bool online);

/// Source of connectivity events for session refetching.
abstract interface class OnlineManager {
  /// Records a connectivity change and notifies listeners.
  void setOnline(bool online);

  /// Whether the device is currently considered online.
  bool get isOnline;

  /// Adds [listener]; returns the function that removes it.
  void Function() subscribe(OnlineListener listener);

  /// Starts watching the platform; returns the teardown.
  void Function() setup();
}

/// Default manager: always online until told otherwise via [setOnline].
class DefaultOnlineManager implements OnlineManager {
  final Set<OnlineListener> _listeners = <OnlineListener>{};

  @override
  bool isOnline = true;

  @override
  void Function() subscribe(OnlineListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void setOnline(bool online) {
    isOnline = online;
    for (final listener in _listeners.toList()) {
      listener(online);
    }
  }

  @override
  void Function() setup() => () {};
}

/// Process-wide online manager, the Dart slot for `globalThis[kOnlineManager]`.
OnlineManager? globalOnlineManager;

/// The current online manager, creating the default one on first use.
OnlineManager getGlobalOnlineManager() =>
    globalOnlineManager ??= DefaultOnlineManager();
