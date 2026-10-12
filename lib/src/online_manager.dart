import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:re_better_auth/src/better_auth/client/online_manager.dart';

/// Source of connectivity changes; defaults to connectivity_plus.
typedef ConnectivityChanges = Stream<List<ConnectivityResult>> Function();

/// [OnlineManager] fed by connectivity_plus; any non-`none` result is online.
class FlutterOnlineManager implements OnlineManager {
  /// Creates the manager; [connectivityChanges] replaces the platform source.
  FlutterOnlineManager({ConnectivityChanges? connectivityChanges})
    : _connectivityChanges =
          connectivityChanges ?? (() => Connectivity().onConnectivityChanged);

  final ConnectivityChanges _connectivityChanges;
  final Set<OnlineListener> _listeners = <OnlineListener>{};
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  @override
  bool isOnline = true;

  @override
  void Function() subscribe(OnlineListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void setOnline(bool online) {
    if (isOnline == online) return;
    isOnline = online;
    for (final listener in _listeners.toList()) {
      listener(online);
    }
  }

  @override
  void Function() setup() {
    try {
      _subscription = _connectivityChanges().listen(
        (results) => setOnline(
          results.any((result) => result != ConnectivityResult.none),
        ),
        // No connectivity plugin: assume online, as Expo does.
        onError: (Object _) => setOnline(true),
      );
    } on Object {
      setOnline(true);
    }
    return () {
      unawaited(_subscription?.cancel());
      _subscription = null;
    };
  }
}

/// Installs a [FlutterOnlineManager] as the global online manager if none is set.
OnlineManager setupFlutterOnlineManager() =>
    globalOnlineManager ??= FlutterOnlineManager();
