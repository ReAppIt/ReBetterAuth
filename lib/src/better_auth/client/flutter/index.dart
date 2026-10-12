import 'package:dio/dio.dart' show Dio;
import 'package:flutter/foundation.dart';
import 'package:re_better_auth/src/better_auth/client/config.dart';
import 'package:re_better_auth/src/better_auth/client/flutter/flutter_store.dart';
import 'package:re_better_auth/src/better_auth/client/query.dart';
import 'package:re_better_auth/src/better_auth/client/vanilla.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// Client returned by the Flutter `createAuthClient`; atoms are [ValueListenable]s.
class FlutterAuthClient extends BaseAuthClient {
  /// Wraps a built [config].
  FlutterAuthClient(super.config);

  final Map<String, AtomListenable<Object?>> _listenables =
      <String, AtomListenable<Object?>>{};

  /// The session; listening fetches it and keeps it fresh while listened to.
  ValueListenable<AuthQueryState<SessionData>> get useSession =>
      useAtom<AuthQueryState<SessionData>>('session');

  /// The atom named [key] (for example a plugin atom) as a [ValueListenable].
  ValueListenable<T> useAtom<T>(String key) =>
      _listenables.putIfAbsent(
            key,
            () => AtomListenable<T>(config.pluginsAtoms[key]! as Atom<T>),
          )
          as ValueListenable<T>;
}

/// Creates the client for Flutter apps (the `better-auth/react` equivalent).
///
/// [baseURL] gets `/api/auth` appended when it has no path.
FlutterAuthClient createAuthClient({
  String? baseURL,
  String? basePath,
  List<BetterAuthClientPlugin> plugins = const <BetterAuthClientPlugin>[],
  ClientFetchOption? fetchOptions,
  bool disableDefaultFetchPlugins = false,
  RevalidateOptions? sessionOptions,
  Dio? dio,
}) => FlutterAuthClient(
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
