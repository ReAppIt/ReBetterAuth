import 'package:flutter/widgets.dart';
import 'package:re_better_auth/src/better_auth/client/focus_manager.dart';

/// [AuthFocusManager] driven by the app lifecycle; resumed means focused.
class FlutterFocusManager implements AuthFocusManager {
  final Set<FocusListener> _listeners = <FocusListener>{};
  AppLifecycleListener? _subscription;

  /// Last reported focus state; `null` until the first change.
  bool? isFocused;

  @override
  void Function() subscribe(FocusListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void setFocused(bool focused) {
    if (isFocused == focused) return;
    isFocused = focused;
    for (final listener in _listeners.toList()) {
      listener(focused);
    }
  }

  @override
  void Function() setup() {
    _subscription = AppLifecycleListener(
      onStateChange: (state) => setFocused(state == AppLifecycleState.resumed),
    );
    return () {
      _subscription?.dispose();
      _subscription = null;
    };
  }
}

/// Installs a [FlutterFocusManager] as the global focus manager if none is set.
AuthFocusManager setupFlutterFocusManager() =>
    globalFocusManager ??= FlutterFocusManager();
