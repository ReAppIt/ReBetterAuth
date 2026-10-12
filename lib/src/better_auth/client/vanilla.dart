import 'package:dio/dio.dart' show Dio;
import 'package:re_better_auth/src/better_auth/client/config.dart';
import 'package:re_better_auth/src/better_auth/client/proxy.dart';
import 'package:re_better_auth/src/better_auth/client/routes.dart';
import 'package:re_better_auth/src/better_auth/client/session_atom.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/error_codes.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// Shared surface of the vanilla and Flutter clients: routes, `$fetch`,
/// `$store` and plugin actions.
abstract class BaseAuthClient extends AuthRoutes {
  /// Wraps a built [config].
  BaseAuthClient(this.config);

  /// The wiring built by `getClientConfig`.
  final ClientConfig config;

  /// The configured fetch; use it for endpoints without a typed method.
  BetterFetch get $fetch => config.$fetch;

  /// Atoms and signals shared with plugins.
  ClientStore get $store => config.$store;

  /// Resolved auth base URL.
  String get baseURL => config.baseURL;

  /// Core and plugin error codes by code.
  Map<String, RawError> get $errorCodes => config.errorCodes;

  @override
  Map<String, Object?> get pluginsActions => config.pluginsActions;

  /// Seeds the session once (for example from your own cache) before mounting.
  void hydrateSession(SessionData? session) => config.hydrateSession(session);

  @override
  Future<BetterFetchResponse<T>> call<T>(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    ClientFetchOption? fetchOptions,
  }) => callDynamicPath<T>(
    path,
    client: config.$fetch,
    knownPathMethods: config.pluginPathMethods,
    atoms: config.pluginsAtoms,
    atomListeners: config.atomListeners,
    body: body,
    query: query,
    fetchOptions: fetchOptions,
  );
}

/// Client returned by the vanilla `createAuthClient`; atoms are raw [Atom]s.
class AuthClient extends BaseAuthClient {
  /// Wraps a built [config].
  AuthClient(super.config);

  /// The session atom; listening to it fetches and keeps the session fresh.
  SessionAtom get useSession => config.session;
}

/// Creates a framework-agnostic client (`better-auth/client`).
AuthClient createAuthClient({
  String? baseURL,
  String? basePath,
  List<BetterAuthClientPlugin> plugins = const <BetterAuthClientPlugin>[],
  ClientFetchOption? fetchOptions,
  bool disableDefaultFetchPlugins = false,
  RevalidateOptions? sessionOptions,
  Dio? dio,
}) => AuthClient(
  getClientConfig(
    BetterAuthClientOptions(
      baseURL: baseURL,
      basePath: basePath,
      plugins: plugins,
      fetchOptions: fetchOptions,
      disableDefaultFetchPlugins: disableDefaultFetchPlugins,
      sessionOptions: sessionOptions,
      dio: dio,
    ),
  ),
);

/// Typed access to the atom named [key] in [client]'s store.
Atom<T> getAtom<T>(BaseAuthClient client, String key) =>
    client.$store.atoms[key]! as Atom<T>;
