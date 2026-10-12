import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_web_auth_2_platform_interface/flutter_web_auth_2_platform_interface.dart';
import 'package:re_better_auth/src/better_auth/client/query.dart';
import 'package:re_better_auth/src/better_auth/client/routes.dart';
import 'package:re_better_auth/src/better_auth/client/session_atom.dart';
import 'package:re_better_auth/src/better_auth/cookies/cookie_utils.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/json.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/better_fetch/url_search_params.dart';
import 'package:re_better_auth/src/better_fetch/utils.dart';
import 'package:re_better_auth/src/client_storage.dart';
import 'package:re_better_auth/src/focus_manager.dart';
import 'package:re_better_auth/src/online_manager.dart';
import 'package:re_better_auth/src/version.dart';

/// Opens an authentication browser session and returns the callback URL.
///
/// Throws a `PlatformException` with code `CANCELED` when the user closes it.
typedef OpenAuthSession =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
      required FlutterWebAuth2Options options,
    });

/// Builds a deep link the way `Linking.createURL` does in a standalone app.
String createURL(String path, String scheme) =>
    Uri.encodeFull('$scheme://$path');

bool _truthy(Object? value) =>
    value != null && value != false && value != 0 && value != '';

DateTime? _asDate(Object? value) => switch (value) {
  final DateTime date => date,
  final String text => DateTime.tryParse(text),
  _ => null,
};

/// Merges a `Set-Cookie` [header] into the stored cookie JSON [prevCookie].
/// `Max-Age<=0` or a past `Expires` deletes; others store `{value, expires}`.
String getSetCookie(String header, [String? prevCookie]) {
  final parsed = parseSetCookieHeader(header);
  final previous = safeJSONParse(prevCookie);
  final toSetCookie = previous is Map<String, Object?>
      ? Map<String, Object?>.of(previous)
      : <String, Object?>{};
  parsed.forEach((key, cookie) {
    final expiresAt = cookie.expires;
    final maxAge = cookie.maxAge;
    if (maxAge != null && maxAge <= 0) {
      toSetCookie.remove(key);
      return;
    }
    final now = clock.now();
    final expires = maxAge != null
        ? now.add(Duration(seconds: maxAge))
        : expiresAt;
    if (expires != null && !expires.isAfter(now)) {
      toSetCookie.remove(key);
      return;
    }
    toSetCookie[key] = <String, Object?>{
      'value': cookie.value,
      'expires': expires == null ? null : toISOString(expires),
    };
  });
  return jsonStringify(toSetCookie);
}

/// Builds a `Cookie` header (`a=1; b=2`) from stored cookie JSON, skipping
/// expired entries. Returns an empty string when nothing is stored.
String getCookie(String? cookie) {
  final parsed = safeJSONParse(cookie);
  if (parsed is! Map<String, Object?>) return '';
  final now = clock.now();
  final pairs = <String>[];
  parsed.forEach((key, value) {
    final stored = value is Map<String, Object?> ? value : null;
    final expires = _asDate(stored?['expires']);
    if (expires != null && expires.isBefore(now)) return;
    pairs.add('$key=${stored?['value']}');
  });
  return pairs.join('; ');
}

String? _getOAuthStateValue(String? cookieJson, List<String> cookiePrefix) {
  if (cookieJson == null || cookieJson.isEmpty) return null;
  final parsed = safeJSONParse(cookieJson);
  if (parsed is! Map<String, Object?>) return null;
  for (final prefix in cookiePrefix) {
    for (final name in <String>[
      '$secureCookiePrefix$prefix.oauth_state',
      '$prefix.oauth_state',
    ]) {
      final cookie = parsed[name];
      final value = cookie is Map<String, Object?> ? cookie['value'] : null;
      if (_truthy(value)) return '$value';
    }
  }
  return null;
}

/// Whether a session cookie's value differs, ignoring expiry-only changes.
bool hasSessionCookieChanged(String? prevCookie, String newCookie) {
  if (prevCookie == null || prevCookie.isEmpty) return true;
  try {
    final prev = jsonDecode(prevCookie);
    final next = jsonDecode(newCookie);
    if (prev is! Map<String, Object?> || next is! Map<String, Object?>) {
      return true;
    }
    final sessionKeys = <String>{
      for (final key in <String>[...prev.keys, ...next.keys])
        if (key.contains('session_token') || key.contains('session_data')) key,
    };
    for (final key in sessionKeys) {
      final prevValue = prev[key] is Map<String, Object?>
          ? (prev[key]! as Map<String, Object?>)['value']
          : null;
      final nextValue = next[key] is Map<String, Object?>
          ? (next[key]! as Map<String, Object?>)['value']
          : null;
      if (prevValue != nextValue) return true;
    }
    return false;
  } on FormatException {
    return true;
  }
}

/// Whether [setCookieHeader] sets a better-auth cookie: a name starting with
/// a prefix (after `__Secure-`), or for `''` ending in `session_token`/`data`.
bool hasBetterAuthCookies(String setCookieHeader, List<String> cookiePrefix) {
  final cookies = parseSetCookieHeader(setCookieHeader);
  const cookieSuffixes = <String>['session_token', 'session_data'];
  for (final name in cookies.keys) {
    final nameWithoutSecure = stripSecureCookiePrefix(name);
    for (final prefix in cookiePrefix) {
      if (prefix.isNotEmpty) {
        if (nameWithoutSecure.startsWith(prefix)) return true;
      } else if (cookieSuffixes.any(nameWithoutSecure.endsWith)) {
        return true;
      }
    }
  }
  return false;
}

String _pathname(Object url, [String? baseURL]) {
  final target = Uri.tryParse('$url');
  if (target == null) return '';
  if (target.hasScheme || baseURL == null) return target.path;
  return Uri.tryParse(baseURL)?.resolveUri(target).path ?? target.path;
}

Future<String> _defaultOpenAuthSession({
  required String url,
  required String callbackUrlScheme,
  required FlutterWebAuth2Options options,
}) => FlutterWebAuth2.authenticate(
  url: url,
  callbackUrlScheme: callbackUrlScheme,
  options: options,
);

/// Port of `expoClient`: keeps cookies in secure storage, attaches them to
/// auth requests, caches the session and runs social sign-in in a browser.
class FlutterClientPlugin extends BetterAuthClientPlugin {
  /// Creates the plugin; see [flutterClient].
  FlutterClientPlugin({
    required this.scheme,
    required FlutterClientStorage storage,
    String? storagePrefix,
    List<String>? cookiePrefix,
    this.disableCache = false,
    this.webAuthOptions = const FlutterWebAuth2Options(),
    OpenAuthSession? openAuthSession,
  }) : storage = createManagedStorage(storage),
       storagePrefix = storagePrefix == null || storagePrefix.isEmpty
           ? 'better-auth'
           : storagePrefix,
       cookiePrefix = cookiePrefix ?? const <String>['better-auth'],
       _openAuthSession = openAuthSession ?? _defaultOpenAuthSession;

  /// App URL scheme, such as `myapp`.
  final String scheme;

  /// Chunking, serialized storage for cookies and the session cache.
  final ManagedStorage storage;

  /// Prefix of the storage keys.
  final String storagePrefix;

  /// Prefixes identifying better-auth cookies in `Set-Cookie`.
  final List<String> cookiePrefix;

  /// Disables the cached session used for instant startup.
  final bool disableCache;

  /// Options for the browser session (ephemeral sessions, Android flags...).
  final FlutterWebAuth2Options webAuthOptions;

  final OpenAuthSession _openAuthSession;
  ClientStore? _store;
  Future<void>? _sessionCacheHydration;

  /// Storage key of the cookie JSON, `<storagePrefix>_cookie`.
  String get cookieName => '${storagePrefix}_cookie';

  /// Storage key of the cached session, `<storagePrefix>_session_data`.
  String get localCacheName => '${storagePrefix}_session_data';

  SessionAtom? get _sessionAtom => _store?.atoms['session'] as SessionAtom?;

  Future<void> _restoreSessionCache() async {
    if (disableCache) return;
    final sessionAtom = _sessionAtom;
    if (sessionAtom == null) return;
    final initialSessionState = sessionAtom.get();
    if (initialSessionState.data != null) return;
    final raw = await storage.getItemAsync(localCacheName);
    final cached = raw != null && raw.isNotEmpty ? safeJSONParse(raw) : null;
    if (cached is! Map<String, Object?>) return;
    final user = cached['user'];
    final session = cached['session'];
    final expiresAt = _asDate(
      session is Map<String, Object?> ? session['expiresAt'] : null,
    );
    final fresh =
        user is Map<String, Object?> &&
        _truthy(user['id']) &&
        session is Map<String, Object?> &&
        _truthy(session['id']) &&
        expiresAt != null &&
        expiresAt.isAfter(clock.now());
    if (fresh && identical(sessionAtom.get(), initialSessionState)) {
      sessionAtom.set(
        AuthQueryState<SessionData>(
          data: SessionData(cached),
          error: null,
          isPending: initialSessionState.isPending,
          isRefetching: initialSessionState.isRefetching,
          refetch: initialSessionState.refetch,
        ),
      );
    }
  }

  Future<void> _hydrateSessionCache() => _sessionCacheHydration ??=
      _restoreSessionCache().catchError((Object error, StackTrace stackTrace) {
        _sessionCacheHydration = null;
        Error.throwWithStackTrace(error, stackTrace);
      });

  Future<void> _clearSessionCache() async {
    await storage.setItemAsync(cookieName, '{}');
    final sessionAtom = _sessionAtom;
    if (sessionAtom != null) {
      final current = sessionAtom.get();
      sessionAtom.set(
        AuthQueryState<SessionData>(
          data: null,
          error: null,
          isPending: false,
          isRefetching: current.isRefetching,
          refetch: current.refetch,
        ),
      );
    }
    await storage.setItemAsync(localCacheName, '{}');
  }

  @override
  String get id => 'expo';

  @override
  String get version => packageVersion;

  @override
  Map<String, Object?> getActions(
    BetterFetch $fetch,
    ClientStore $store,
    BetterAuthClientOptions? options,
  ) {
    _store = $store;
    return <String, Object?>{
      'getCookie': () async =>
          getCookie(await storage.getItemAsync(cookieName)),
    };
  }

  @override
  List<BetterFetchPlugin> get fetchPlugins => <BetterFetchPlugin>[
    BetterFetchPlugin(
      id: 'expo',
      name: 'Expo',
      hooks: FetchHooks(onSuccess: _onSuccess),
      init: _init,
    ),
  ];

  Future<void> _onSuccess(SuccessContext context) async {
    final pathname = _pathname(context.request.url);
    final setCookie = context.response.headers.get('set-cookie');
    if (setCookie != null && setCookie.isNotEmpty) {
      // Ignore third-party cookies such as `__cf_bm` to avoid refetch loops.
      if (hasBetterAuthCookies(setCookie, cookiePrefix)) {
        final update = await storage.updateItemAsync(
          cookieName,
          (currentValue) => getSetCookie(setCookie, currentValue),
        );
        if (update != null &&
            hasSessionCookieChanged(update.previousValue, update.value)) {
          _store?.notify(r'$sessionSignal');
        }
      }
    }

    if (pathname.endsWith('/get-session') && !disableCache) {
      await storage.setItemAsync(localCacheName, jsonStringify(context.data));
    }
    if (pathname.endsWith('/sign-out')) await _clearSessionCache();

    final isSignInRequest =
        pathname.endsWith('/sign-in') || pathname.contains('/sign-in/');
    final isLinkSocialRequest = pathname.endsWith('/link-social');
    final data = context.data;
    final requestBody = context.request.body;
    final isIdTokenRequest =
        requestBody is String && requestBody.contains('idToken');
    if (data is! Map<String, Object?> ||
        !_truthy(data['redirect']) ||
        !(isSignInRequest || isLinkSocialRequest) ||
        isIdTokenRequest) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await FlutterWebAuth2Platform.instance.clearAllDanglingCalls();
      } on Object {
        // Nothing to dismiss.
      }
    }

    final storedCookieJson = await storage.getItemAsync(cookieName);
    final oauthStateValue = _getOAuthStateValue(storedCookieJson, cookiePrefix);
    final params = UrlSearchParams()
      ..append('authorizationURL', '${data['url']}');
    if (oauthStateValue != null) params.append('oauthState', oauthStateValue);
    final proxyURL =
        '${context.request.baseURL}/expo-authorization-proxy?$params';
    final String resultUrl;
    try {
      resultUrl = await _openAuthSession(
        url: proxyURL,
        callbackUrlScheme: scheme,
        options: webAuthOptions,
      );
    } on PlatformException catch (error) {
      if (error.code == 'CANCELED') return;
      rethrow;
    }
    final query = Uri.tryParse(resultUrl)?.query ?? '';
    final cookie = UrlSearchParams.parse(query).get('cookie');
    if (cookie == null || cookie.isEmpty) return;
    final update = await storage.updateItemAsync(
      cookieName,
      (currentValue) => getSetCookie(cookie, currentValue),
    );
    if (update != null) _store?.notify(r'$sessionSignal');
  }

  Future<PluginInitResult> _init(String url, BetterFetchOption options) async {
    final pathname = _pathname(url, options.baseURL);
    if (pathname.endsWith('/get-session')) await _hydrateSessionCache();
    final body = options.body;
    // ID-token sign-in is verified by the provider token, not by cookies.
    final isIdTokenRequest =
        body is Map<String, Object?> && body.containsKey('idToken');

    if (isIdTokenRequest) {
      final storedCookie = pathname.endsWith('/link-social')
          ? await storage.getItemAsync(cookieName)
          : null;
      final cookie = getCookie(storedCookie);
      options.headers = <String, String?>{
        ...?options.headers,
        if (cookie.isNotEmpty) 'cookie': cookie,
        'x-skip-oauth-proxy': 'true',
      };
    } else {
      final storedCookie = await storage.getItemAsync(cookieName);
      final cookie = getCookie(storedCookie);
      options.headers = <String, String?>{
        ...?options.headers,
        if (cookie.isNotEmpty) 'cookie': cookie,
        'expo-origin': createURL('', scheme),
        'x-skip-oauth-proxy': 'true',
      };
      if (body is Map<String, Object?>) {
        for (final key in const <String>[
          'callbackURL',
          'newUserCallbackURL',
          'errorCallbackURL',
        ]) {
          final value = body[key];
          if (value is String && value.startsWith('/')) {
            body[key] = createURL(value, scheme);
          }
        }
      }
      if (pathname.endsWith('/sign-out')) await _clearSessionCache();
    }
    return (url: url, options: options);
  }
}

/// The Flutter client plugin (`expoClient`) for `createAuthClient`. [scheme]
/// must be trusted by the server as `<scheme>://`; throws on the web.
FlutterClientPlugin flutterClient({
  required String scheme,
  required FlutterClientStorage storage,
  String? storagePrefix,
  List<String>? cookiePrefix,
  bool disableCache = false,
  FlutterWebAuth2Options webAuthOptions = const FlutterWebAuth2Options(),
  OpenAuthSession? openAuthSession,
}) {
  if (kIsWeb) {
    throw UnsupportedError('re_better_auth supports iOS and Android only.');
  }
  if (scheme.isEmpty) {
    throw ArgumentError.value(scheme, 'scheme', 'Scheme not provided');
  }
  setupFlutterFocusManager();
  setupFlutterOnlineManager();
  return FlutterClientPlugin(
    scheme: scheme,
    storage: storage,
    storagePrefix: storagePrefix,
    cookiePrefix: cookiePrefix,
    disableCache: disableCache,
    webAuthOptions: webAuthOptions,
    openAuthSession: openAuthSession,
  );
}

/// Typed access to the [flutterClient] actions.
extension FlutterClientActions on AuthRoutes {
  /// The stored cookies as a `Cookie` header for your own API requests.
  Future<String> getCookie() =>
      (pluginsActions['getCookie']! as Future<String> Function())();
}
