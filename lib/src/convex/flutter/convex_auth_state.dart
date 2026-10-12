import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:re_better_auth/src/convex/browser/sync/authentication_manager.dart';

/// Convex auth status, as [useConvexAuth] returns it.
@immutable
class ConvexAuthState {
  /// Creates a status.
  const ConvexAuthState({
    required this.isLoading,
    required this.isAuthenticated,
    required this.isRefreshing,
  });

  /// Whether the status is still being resolved.
  final bool isLoading;

  /// Whether the user is signed in and Convex accepted the token.
  final bool isAuthenticated;

  /// Whether an authenticated client is refetching a rejected token.
  final bool isRefreshing;

  @override
  bool operator ==(Object other) =>
      other is ConvexAuthState &&
      other.isLoading == isLoading &&
      other.isAuthenticated == isAuthenticated &&
      other.isRefreshing == isRefreshing;

  @override
  int get hashCode => Object.hash(isLoading, isAuthenticated, isRefreshing);
}

/// What an auth provider reports to [ConvexProviderWithAuth] (`useAuth()`).
@immutable
class ConvexAuthProviderState {
  /// Creates a provider state.
  const ConvexAuthProviderState({
    required this.isLoading,
    required this.isAuthenticated,
    required this.fetchAccessToken,
  });

  /// Whether the provider is still resolving the user.
  final bool isLoading;

  /// Whether a user is signed in.
  final bool isAuthenticated;

  /// Fetches the Convex token; a new function makes Convex authenticate again.
  final AuthTokenFetcher fetchAccessToken;

  @override
  bool operator ==(Object other) =>
      other is ConvexAuthProviderState &&
      other.isLoading == isLoading &&
      other.isAuthenticated == isAuthenticated &&
      other.fetchAccessToken == fetchAccessToken;

  @override
  int get hashCode => Object.hash(isLoading, isAuthenticated, fetchAccessToken);
}

typedef _EffectDeps = ({
  bool authenticated,
  bool loading,
  AuthTokenFetcher fetchAccessToken,
});

/// The state and effects of [ConvexProviderWithAuth] without widgets: it
/// authenticates [client] while [auth] has a user and publishes [state].
class ConvexAuthController {
  /// Follows [auth]; [scheduleEffects] runs effects after [state] listeners
  /// reacted, so Convex auth is cleared only once signed-in UI is gone.
  ConvexAuthController({
    required this.client,
    required this.auth,
    void Function(VoidCallback effects)? scheduleEffects,
  }) : _scheduleEffects = scheduleEffects ?? _runNow {
    auth.addListener(_render);
    _render();
  }

  static void _runNow(VoidCallback effects) => effects();

  /// The Convex client's auth calls.
  final ConvexAuthClient client;

  /// The auth provider's state.
  final ValueListenable<ConvexAuthProviderState> auth;

  final void Function(VoidCallback effects) _scheduleEffects;
  final ValueNotifier<ConvexAuthState> _state = ValueNotifier<ConvexAuthState>(
    const ConvexAuthState(
      isLoading: true,
      isAuthenticated: false,
      isRefreshing: false,
    ),
  );
  bool? _isConvexAuthenticated;
  bool _isRefreshing = false;
  _EffectDeps? _effectDeps;
  VoidCallback? _firstEffectCleanup;
  VoidCallback? _lastEffectCleanup;
  bool _effectsScheduled = false;
  bool _disposed = false;

  /// The status [useConvexAuth] returns.
  ValueListenable<ConvexAuthState> get state => _state;

  bool _depsChanged(ConvexAuthProviderState provider) {
    final deps = _effectDeps;
    return deps == null ||
        deps.authenticated != provider.isAuthenticated ||
        deps.loading != provider.isLoading ||
        deps.fetchAccessToken != provider.fetchAccessToken;
  }

  void _render() {
    if (_disposed) return;
    final provider = auth.value;
    if (provider.isLoading && _isConvexAuthenticated != null) {
      _isConvexAuthenticated = null;
      _isRefreshing = false;
    }
    if (!provider.isLoading &&
        !provider.isAuthenticated &&
        _isConvexAuthenticated != false) {
      _isConvexAuthenticated = false;
      _isRefreshing = false;
    }
    final isAuthenticated =
        provider.isAuthenticated && (_isConvexAuthenticated ?? false);
    _state.value = ConvexAuthState(
      isLoading: _isConvexAuthenticated == null,
      isAuthenticated: isAuthenticated,
      isRefreshing: _isRefreshing && isAuthenticated,
    );
    if (_effectsScheduled || !_depsChanged(provider)) return;
    _effectsScheduled = true;
    _scheduleEffects(_runEffects);
  }

  void _runEffects() {
    _effectsScheduled = false;
    if (_disposed) return;
    final provider = auth.value;
    if (!_depsChanged(provider)) return;
    _effectDeps = (
      authenticated: provider.isAuthenticated,
      loading: provider.isLoading,
      fetchAccessToken: provider.fetchAccessToken,
    );
    _cleanupEffects();
    if (!provider.isAuthenticated) return;
    var isThisEffectRelevant = true;
    client.setAuth(
      provider.fetchAccessToken,
      (backendReportsIsAuthenticated) {
        if (!isThisEffectRelevant) return;
        _isConvexAuthenticated = backendReportsIsAuthenticated;
        _render();
      },
      (isRefreshing) {
        if (!isThisEffectRelevant) return;
        _isRefreshing = isRefreshing;
        _render();
      },
    );
    _firstEffectCleanup = () {
      isThisEffectRelevant = false;
      _isConvexAuthenticated = (_isConvexAuthenticated ?? false) ? false : null;
      _isRefreshing = false;
    };
    _lastEffectCleanup = () {
      client.clearAuth();
      _isConvexAuthenticated = null;
      _isRefreshing = false;
    };
  }

  void _cleanupEffects() {
    final first = _firstEffectCleanup;
    final last = _lastEffectCleanup;
    _firstEffectCleanup = null;
    _lastEffectCleanup = null;
    if (first == null && last == null) return;
    first?.call();
    last?.call();
    _render();
  }

  /// Stops following [auth] and clears Convex auth if it was set.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    auth.removeListener(_render);
    _cleanupEffects();
    _state.dispose();
  }
}

/// Authenticates [client] while [useAuth] has a user and provides
/// [useConvexAuth] to [child].
class ConvexProviderWithAuth extends StatefulWidget {
  /// Creates the provider.
  const ConvexProviderWithAuth({
    super.key,
    required this.client,
    required this.useAuth,
    required this.child,
  });

  /// The Convex client's auth calls.
  final ConvexAuthClient client;

  /// The auth provider's state.
  final ValueListenable<ConvexAuthProviderState> useAuth;

  /// The subtree.
  final Widget child;

  @override
  State<ConvexProviderWithAuth> createState() => _ConvexProviderWithAuthState();
}

class _ConvexProviderWithAuthState extends State<ConvexProviderWithAuth> {
  late ConvexAuthController _controller;

  ConvexAuthController _createController() => ConvexAuthController(
    client: widget.client,
    auth: widget.useAuth,
    scheduleEffects: _afterFrame,
  );

  // Effects wait for the rebuild, like React's: clearing Convex auth before the
  // Authenticated subtree is gone would re-run its queries unauthenticated.
  static void _afterFrame(VoidCallback effects) {
    SchedulerBinding.instance
      ..addPostFrameCallback((_) => effects())
      ..ensureVisualUpdate();
  }

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(ConvexProviderWithAuth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.client, widget.client) &&
        identical(oldWidget.useAuth, widget.useAuth)) {
      return;
    }
    _controller.dispose();
    _controller = _createController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ConvexAuthScope(notifier: _controller.state, child: widget.child);
}

class _ConvexAuthScope
    extends InheritedNotifier<ValueListenable<ConvexAuthState>> {
  const _ConvexAuthScope({required super.notifier, required super.child});
}

/// The Convex auth status from the nearest [ConvexProviderWithAuth];
/// [context] rebuilds when it changes.
ConvexAuthState useConvexAuth(BuildContext context) {
  final scope = context.dependOnInheritedWidgetOfExactType<_ConvexAuthScope>();
  if (scope == null) {
    throw FlutterError(
      'Could not find `ConvexProviderWithAuth` (or `ConvexBetterAuthProvider`) '
      'as an ancestor widget.',
    );
  }
  return scope.notifier!.value;
}
