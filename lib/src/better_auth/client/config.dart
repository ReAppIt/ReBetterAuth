import 'package:re_better_auth/src/better_auth/client/fetch_plugins.dart';
import 'package:re_better_auth/src/better_auth/client/parser.dart';
import 'package:re_better_auth/src/better_auth/client/session_atom.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/error_codes.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_auth/utils/defu.dart';
import 'package:re_better_auth/src/better_auth/utils/url.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/dio_fetch.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

const Set<String> _sessionSignalPaths = <String>{
  '/sign-out',
  '/update-user',
  '/update-session',
  '/sign-up/email',
  '/sign-in/email',
  '/delete-user',
  '/verify-email',
  '/revoke-sessions',
  '/revoke-session',
  '/revoke-other-sessions',
  '/change-email',
  '/change-password',
};

/// Whether a successful request to [path] should refetch the session.
bool matchesSessionSignal(String path) => _sessionSignalPaths.contains(path);

/// Everything `createAuthClient` builds from its options.
class ClientConfig {
  ClientConfig._({
    required this.baseURL,
    required this.pluginsActions,
    required this.pluginsAtoms,
    required this.pluginPathMethods,
    required this.atomListeners,
    required this.hydrateSession,
    required this.$sessionSignal,
    required this.session,
    required this.$fetch,
    required this.$store,
    required this.errorCodes,
  });

  /// Resolved auth base URL, such as `https://api.example.com/api/auth`.
  final String baseURL;

  /// Plugin actions, deep-merged in plugin order.
  final Map<String, Object?> pluginsActions;

  /// Every atom by name.
  final Map<String, Atom<Object?>> pluginsAtoms;

  /// Forced methods by path.
  final Map<String, String> pluginPathMethods;

  /// Signals flipped after matching requests.
  final List<ClientAtomListener> atomListeners;

  /// Seeds the session atom once per client.
  final void Function(SessionData? sessionData) hydrateSession;

  /// Flip to make `useSession` refetch.
  final Atom<bool> $sessionSignal;

  /// The `useSession` atom.
  final SessionAtom session;

  /// The configured fetch.
  final BetterFetch $fetch;

  /// The shared store.
  final ClientStore $store;

  /// Core error codes plus every plugin's codes.
  final Map<String, RawError> errorCodes;
}

/// Builds the `$fetch`, session atom, store and plugin wiring for [options].
ClientConfig getClientConfig([BetterAuthClientOptions? options]) {
  final baseURL =
      getBaseURL(options?.baseURL, options?.basePath) ?? '/api/auth';
  final plugins = options?.plugins ?? const <BetterAuthClientPlugin>[];
  final pluginsFetchPlugins = <BetterFetchPlugin>[
    for (final plugin in plugins) ...plugin.fetchPlugins,
  ];
  final fetchOptions = options?.fetchOptions;
  final lifeCyclePlugin = BetterFetchPlugin(
    id: 'lifecycle-hooks',
    name: 'lifecycle-hooks',
    hooks: FetchHooks(
      onSuccess: fetchOptions?.onSuccess,
      onError: fetchOptions?.onError,
      onRequest: fetchOptions?.onRequest,
      onResponse: fetchOptions?.onResponse,
    ),
  );
  final restOfFetchOptions = (fetchOptions ?? ClientFetchOption()).copy()
    ..onSuccess = null
    ..onError = null
    ..onRequest = null
    ..onResponse = null;
  final dio = options?.dio;
  final $fetch = createFetch(
    ClientFetchOption(
        baseURL: baseURL,
        method: 'GET',
        jsonParser: (text) =>
            text.isEmpty ? null : parseJSON(text, strict: false),
        customFetchImpl: dio == null ? null : dioFetch(dio),
      ).merge(restOfFetchOptions)
      ..plugins = <BetterFetchPlugin>[
        lifeCyclePlugin,
        ...?restOfFetchOptions.plugins,
        if (!(options?.disableDefaultFetchPlugins ?? false)) redirectPlugin,
        ...pluginsFetchPlugins,
      ],
  );
  final sessionAtom = getSessionAtom($fetch, options);

  var hasHydrated = false;
  void hydrateSession(SessionData? sessionData) {
    if (hasHydrated || sessionData == null) return;
    hasHydrated = true;
    hydrateSessionAtom(sessionAtom.session, sessionData);
  }

  var pluginsActions = <String, Object?>{};
  final pluginsAtoms = <String, Atom<Object?>>{
    r'$sessionSignal': sessionAtom.$sessionSignal,
    'session': sessionAtom.session,
  };
  final pluginPathMethods = <String, String>{
    '/sign-out': 'POST',
    '/revoke-sessions': 'POST',
    '/revoke-other-sessions': 'POST',
    '/delete-user': 'POST',
  };
  final atomListeners = <ClientAtomListener>[
    ClientAtomListener(
      signal: r'$sessionSignal',
      matcher: matchesSessionSignal,
      callback: (path) {
        if (path == '/sign-out') {
          sessionAtom.broadcastSessionUpdate('signout');
        } else if (path == '/update-user' || path == '/update-session') {
          sessionAtom.broadcastSessionUpdate('updateUser');
        }
      },
    ),
  ];
  final errorCodes = <String, RawError>{...baseErrorCodes};

  for (final plugin in plugins) {
    pluginsAtoms.addAll(plugin.getAtoms($fetch));
    pluginPathMethods.addAll(plugin.pathMethods);
    atomListeners.addAll(plugin.atomListeners);
    errorCodes.addAll(plugin.errorCodes);
  }

  final $store = ClientStore(pluginsAtoms);

  for (final plugin in plugins) {
    pluginsActions = defu(
      plugin.getActions($fetch, $store, options),
      pluginsActions,
    );
  }

  return ClientConfig._(
    baseURL: baseURL,
    pluginsActions: pluginsActions,
    pluginsAtoms: pluginsAtoms,
    pluginPathMethods: pluginPathMethods,
    atomListeners: atomListeners,
    hydrateSession: hydrateSession,
    $sessionSignal: sessionAtom.$sessionSignal,
    session: sessionAtom.session,
    $fetch: $fetch,
    $store: $store,
    errorCodes: errorCodes,
  );
}
