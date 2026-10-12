import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:re_better_auth/src/better_auth/client/focus_manager.dart';
import 'package:re_better_auth/src/better_auth/core/logger.dart';

/// Returns a Convex JWT, or `null` when none can be had.
typedef AuthTokenFetcher =
    Future<String?> Function({required bool forceRefreshToken});

/// The auth calls `ConvexProviderWithAuth` makes on a Convex client
/// (`IConvexReactClient`).
abstract interface class ConvexAuthClient {
  /// Authenticates with tokens from [fetchToken]; [onChange] reports whether
  /// Convex accepts them, [onRefreshChange] whether a rejected one is refetched.
  void setAuth(
    AuthTokenFetcher fetchToken,
    void Function(bool isAuthenticated) onChange, [
    void Function(bool isRefreshing)? onRefreshChange,
  ]);

  /// Drops the token.
  void clearAuth();
}

const Duration _maximumRefreshDelay = Duration(days: 20);

typedef _AuthConfig = ({
  AuthTokenFetcher fetchToken,
  void Function(bool isAuthenticated) onAuthChange,
});

typedef _FetchedToken = ({bool isFromOutdatedConfig, String? value});

/// [ConvexAuthClient] for Convex clients that take a fixed token, such as
/// `convex.setAuth(token: token)`: it sets each token through [setToken] and
/// refetches it [refreshTokenLeeway] before it expires.
class ConvexTokenAuth implements ConvexAuthClient {
  /// Creates the adapter; [setToken] receives `null` to clear the token.
  ConvexTokenAuth(
    this.setToken, {
    this.refreshTokenLeeway = const Duration(seconds: 10),
  });

  /// Applies a token to the Convex client.
  final Future<void> Function(String? token) setToken;

  /// How long before expiry the token is refetched.
  final Duration refreshTokenLeeway;

  _AuthConfig? _config;
  int _configVersion = 0;
  String? _token;
  Timer? _refetchTimer;
  DateTime? _refetchAt;
  void Function()? _unsubscribeFocus;

  @override
  void setAuth(
    AuthTokenFetcher fetchToken,
    void Function(bool isAuthenticated) onChange, [
    void Function(bool isRefreshing)? onRefreshChange,
  ]) => unawaited(_setConfig(fetchToken, onChange));

  @override
  void clearAuth() {
    _resetAuthState();
    _configVersion++;
    if (_token == null) return;
    _token = null;
    unawaited(_apply(null));
  }

  Future<void> _setConfig(
    AuthTokenFetcher fetchToken,
    void Function(bool isAuthenticated) onChange,
  ) async {
    _resetAuthState();
    final token = await _fetchTokenAndGuardAgainstRace(
      fetchToken,
      forceRefreshToken: false,
    );
    if (token.isFromOutdatedConfig) return;
    _config = (fetchToken: fetchToken, onAuthChange: onChange);
    _listenForResume();
    final value = token.value;
    if (value != null) {
      // No server confirmation to wait for: an applied token counts as accepted.
      if (!await _authenticate(value)) return;
      onChange(true);
    }
    await _refetchToken();
  }

  Future<void> _refetchToken() async {
    final config = _config;
    if (config == null) return;
    final token = await _fetchTokenAndGuardAgainstRace(
      config.fetchToken,
      forceRefreshToken: true,
    );
    if (token.isFromOutdatedConfig) return;
    final value = token.value;
    if (value == null) {
      if (_token != null) {
        _token = null;
        unawaited(_apply(null));
      }
      _setAndReportAuthFailed(config.onAuthChange);
      return;
    }
    if (value == _token) return;
    final hadAuth = _token != null;
    if (!await _authenticate(value)) return;
    _scheduleTokenRefetch(value);
    if (!hadAuth) config.onAuthChange(true);
  }

  void _scheduleTokenRefetch(String token) {
    if (_config == null) return;
    final decoded = _decodeToken(token);
    if (decoded == null) {
      logger.severe('Auth token is not a valid JWT, cannot refetch the token');
      return;
    }
    final iat = decoded['iat'];
    final exp = decoded['exp'];
    if (iat is! num || exp is! num || iat == 0 || exp == 0) {
      logger.severe(
        'Auth token does not have required fields, cannot refetch the token',
      );
      return;
    }
    final lifetimeSeconds = exp - iat;
    if (lifetimeSeconds <= 2) {
      logger.severe(
        'Auth token does not live long enough, cannot refetch the token',
      );
      return;
    }
    var delay = Duration(
      milliseconds: (lifetimeSeconds * 1000 - refreshTokenLeeway.inMilliseconds)
          .round(),
    );
    if (delay > _maximumRefreshDelay) delay = _maximumRefreshDelay;
    if (delay <= Duration.zero) {
      logger.warning(
        'Refetching auth token immediately, configured leeway '
        '${refreshTokenLeeway.inSeconds}s is larger than the token\'s '
        'lifetime ${lifetimeSeconds}s',
      );
      delay = Duration.zero;
    }
    _refetchTimer?.cancel();
    _refetchAt = clock.now().add(delay);
    _refetchTimer = Timer(delay, _runScheduledRefetch);
  }

  void _runScheduledRefetch() {
    _refetchTimer?.cancel();
    _refetchTimer = null;
    _refetchAt = null;
    unawaited(_refetchToken());
  }

  // Timers can fire late after the device slept, so check again on resume.
  void _listenForResume() {
    _unsubscribeFocus ??= getGlobalFocusManager().subscribe((focused) {
      final refetchAt = _refetchAt;
      if (!focused || refetchAt == null) return;
      if (clock.now().isBefore(refetchAt)) return;
      _runScheduledRefetch();
    });
  }

  Future<_FetchedToken> _fetchTokenAndGuardAgainstRace(
    AuthTokenFetcher fetchToken, {
    required bool forceRefreshToken,
  }) async {
    final originalConfigVersion = ++_configVersion;
    String? token;
    try {
      token = await fetchToken(forceRefreshToken: forceRefreshToken);
    } on Object catch (error, stackTrace) {
      logger.warning(
        'Fetching the Convex auth token failed',
        error,
        stackTrace,
      );
    }
    if (_configVersion != originalConfigVersion) {
      return (isFromOutdatedConfig: true, value: null);
    }
    return (isFromOutdatedConfig: false, value: token);
  }

  /// Applies [token]; `false` when a newer config took over meanwhile.
  Future<bool> _authenticate(String token) async {
    final version = _configVersion;
    _token = token;
    await _apply(token);
    return version == _configVersion;
  }

  Future<void> _apply(String? token) async {
    try {
      await setToken(token);
    } on Object catch (error, stackTrace) {
      logger.warning('Setting the Convex auth token failed', error, stackTrace);
    }
  }

  void _setAndReportAuthFailed(void Function(bool) onAuthChange) {
    onAuthChange(false);
    _resetAuthState();
  }

  void _resetAuthState() {
    _refetchTimer?.cancel();
    _refetchTimer = null;
    _refetchAt = null;
    _unsubscribeFocus?.call();
    _unsubscribeFocus = null;
    _config = null;
  }
}

Map<String, Object?>? _decodeToken(String token) {
  final parts = token.split('.');
  if (parts.length < 2) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}
