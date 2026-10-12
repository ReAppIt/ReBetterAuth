import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:re_better_auth/src/better_auth/client/broadcast_channel.dart';
import 'package:re_better_auth/src/better_auth/client/focus_manager.dart';
import 'package:re_better_auth/src/better_auth/client/online_manager.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

int _now() => clock.now().millisecondsSinceEpoch ~/ 1000;

/// Skip a focus refetch if a session request ran within this many seconds.
const int focusRefetchRateLimitSeconds = 5;

/// What triggered a refetch: polling, app focus, or another client.
enum RefetchEvent {
  /// The polling interval fired.
  poll,

  /// The app regained focus or came back online.
  visibilitychange,

  /// Another client broadcast a session change.
  storage,
}

final Random _random = Random();

/// Wires polling, focus, connectivity, broadcasts and `$sessionSignal` to
/// [fetchSession]. Call [init] on mount and [cleanup] on unmount.
class SessionRefreshManager {
  /// Creates a manager; [shouldPollSession] gates each poll.
  SessionRefreshManager({
    required this.fetchSession,
    required this.sessionSignal,
    bool Function()? shouldPollSession,
    BetterAuthClientOptions? options,
  }) : shouldPollSession = shouldPollSession ?? (() => true),
       _refetchInterval = options?.sessionOptions?.refetchInterval,
       _refetchOnWindowFocus =
           options?.sessionOptions?.refetchOnWindowFocus ?? true,
       _refetchWhenOffline =
           options?.sessionOptions?.refetchWhenOffline ?? false;

  /// Fetches the session.
  final Future<void> Function() fetchSession;

  /// Whether polling should fetch right now.
  final bool Function() shouldPollSession;

  /// Signal that forces a fetch whenever it flips.
  final Atom<bool> sessionSignal;

  final Duration? _refetchInterval;
  final bool _refetchOnWindowFocus;
  final bool _refetchWhenOffline;

  bool _isInitialized = false;
  int _lastSessionRequest = 0;
  Timer? _pollInterval;
  void Function()? _unsubscribeBroadcast;
  void Function()? _unsubscribeFocus;
  void Function()? _unsubscribeOnline;
  void Function()? _unsubscribeSignal;
  void Function()? _cleanupBroadcastSetup;
  void Function()? _cleanupFocusSetup;
  void Function()? _cleanupOnlineSetup;

  bool _shouldRefetch() =>
      _refetchWhenOffline || getGlobalOnlineManager().isOnline;

  /// Fetches unless offline; focus events are rate limited.
  void triggerRefetch([RefetchEvent? event]) {
    if (!_shouldRefetch()) return;
    switch (event) {
      case RefetchEvent.storage:
        unawaited(fetchSession());
      case RefetchEvent.poll:
        _lastSessionRequest = _now();
        unawaited(fetchSession());
      case RefetchEvent.visibilitychange:
        final timeSinceLastRequest = _now() - _lastSessionRequest;
        if (timeSinceLastRequest < focusRefetchRateLimitSeconds) return;
        _lastSessionRequest = _now();
        unawaited(fetchSession());
      case null:
        unawaited(fetchSession());
    }
  }

  /// Tells other clients that the session changed because of [trigger].
  void broadcastSessionUpdate(String trigger) {
    getGlobalBroadcastChannel().post(
      BroadcastMessage(
        event: 'session',
        trigger: trigger,
        clientId: _random.nextInt(1 << 32).toRadixString(36),
        timestamp: _now(),
      ),
    );
  }

  void _setupPolling() {
    final interval = _refetchInterval;
    if (interval != null && interval > Duration.zero) {
      _pollInterval = Timer.periodic(interval, (_) {
        if (shouldPollSession()) triggerRefetch(RefetchEvent.poll);
      });
    }
  }

  void _setupBroadcast() {
    _unsubscribeBroadcast = getGlobalBroadcastChannel().subscribe(
      (_) => triggerRefetch(RefetchEvent.storage),
    );
  }

  void _setupFocusRefetch() {
    if (!_refetchOnWindowFocus) return;
    _unsubscribeFocus = getGlobalFocusManager().subscribe(
      (_) => triggerRefetch(RefetchEvent.visibilitychange),
    );
  }

  void _setupOnlineRefetch() {
    _unsubscribeOnline = getGlobalOnlineManager().subscribe((online) {
      if (online) triggerRefetch(RefetchEvent.visibilitychange);
    });
  }

  void _setupSignalSubscription() {
    _unsubscribeSignal = sessionSignal.listen(
      (_, _) => unawaited(fetchSession()),
    );
  }

  /// Starts every source; repeated calls are ignored until [cleanup].
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    _setupPolling();
    _setupBroadcast();
    _setupFocusRefetch();
    _setupOnlineRefetch();
    _setupSignalSubscription();
    _cleanupBroadcastSetup = getGlobalBroadcastChannel().setup();
    _cleanupFocusSetup = getGlobalFocusManager().setup();
    _cleanupOnlineSetup = getGlobalOnlineManager().setup();
  }

  /// Stops every source.
  void cleanup() {
    if (!_isInitialized) return;
    _pollInterval?.cancel();
    _pollInterval = null;
    for (final teardown in <void Function()?>[
      _unsubscribeBroadcast,
      _unsubscribeFocus,
      _unsubscribeOnline,
      _unsubscribeSignal,
      _cleanupBroadcastSetup,
      _cleanupFocusSetup,
      _cleanupOnlineSetup,
    ]) {
      teardown?.call();
    }
    _unsubscribeBroadcast = null;
    _unsubscribeFocus = null;
    _unsubscribeOnline = null;
    _unsubscribeSignal = null;
    _cleanupBroadcastSetup = null;
    _cleanupFocusSetup = null;
    _cleanupOnlineSetup = null;
    _isInitialized = false;
    _lastSessionRequest = 0;
  }
}

/// Creates a [SessionRefreshManager] (`createSessionRefreshManager`).
SessionRefreshManager createSessionRefreshManager({
  required Future<void> Function() fetchSession,
  required Atom<bool> sessionSignal,
  bool Function()? shouldPollSession,
  BetterAuthClientOptions? options,
}) => SessionRefreshManager(
  fetchSession: fetchSession,
  sessionSignal: sessionSignal,
  shouldPollSession: shouldPollSession,
  options: options,
);
