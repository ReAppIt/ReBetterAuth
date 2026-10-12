import 'dart:async';

import 'package:re_better_auth/src/better_auth/client/routes.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/version.dart';

/// Storage for the last login method; `SecureStore` implements it.
abstract interface class LastLoginMethodStorage {
  /// Writes [value] under [key].
  Future<void> setItemAsync(String key, String value);

  /// Reads [key].
  Future<String?> getItemAsync(String key);

  /// Deletes [key].
  Future<void> deleteItemAsync(String key);
}

/// Maps a request URL to a login method name, or `null` to ignore it.
typedef ResolveLoginMethod = FutureOr<String?> Function(Object url);

const List<String> _paths = <String>[
  '/callback/',
  '/sign-in/email',
  '/sign-up/email',
];

String? _defaultResolveMethod(Object url) {
  final pathname = Uri.parse('http://localhost').resolve('$url').path;
  if (_paths.any(pathname.contains)) return pathname.split('/').last;
  if (pathname.contains('siwe')) return 'siwe';
  if (pathname.contains('/passkey/verify-authentication')) return 'passkey';
  return null;
}

/// Records the login method of every auth response (`email`, `google`, ...).
class LastLoginMethodClientPlugin extends BetterAuthClientPlugin {
  /// Creates the plugin; see [lastLoginMethodClient].
  LastLoginMethodClientPlugin({
    required this.storage,
    String? storagePrefix,
    ResolveLoginMethod? customResolveMethod,
  }) : resolveMethod = customResolveMethod ?? _defaultResolveMethod,
       lastLoginMethodName =
           '${storagePrefix == null || storagePrefix.isEmpty ? 'better-auth' : storagePrefix}_last_login_method';

  /// Where the method is stored.
  final LastLoginMethodStorage storage;

  /// Resolves the method from a request URL.
  final ResolveLoginMethod resolveMethod;

  /// Storage key, `<storagePrefix>_last_login_method`.
  final String lastLoginMethodName;

  @override
  String get id => 'last-login-method-expo';

  @override
  String get version => packageVersion;

  @override
  List<BetterFetchPlugin> get fetchPlugins => <BetterFetchPlugin>[
    BetterFetchPlugin(
      id: 'last-login-method-expo',
      name: 'Last Login Method',
      hooks: FetchHooks(
        onResponse: (ctx) async {
          final lastMethod = await resolveMethod(ctx.request.url);
          if (lastMethod == null || lastMethod.isEmpty) return null;
          await storage.setItemAsync(lastLoginMethodName, lastMethod);
          return null;
        },
      ),
    ),
  ];

  @override
  Map<String, Object?> getActions(
    BetterFetch $fetch,
    ClientStore $store,
    BetterAuthClientOptions? options,
  ) => <String, Object?>{
    'getLastUsedLoginMethod': () => storage.getItemAsync(lastLoginMethodName),
    'clearLastUsedLoginMethod': () =>
        storage.deleteItemAsync(lastLoginMethodName),
    'isLastUsedLoginMethod': (String method) async =>
        await storage.getItemAsync(lastLoginMethodName) == method,
  };
}

/// Tracks the last used login method in [storage] under
/// `<storagePrefix>_last_login_method`.
LastLoginMethodClientPlugin lastLoginMethodClient({
  required LastLoginMethodStorage storage,
  String? storagePrefix,
  ResolveLoginMethod? customResolveMethod,
}) => LastLoginMethodClientPlugin(
  storage: storage,
  storagePrefix: storagePrefix,
  customResolveMethod: customResolveMethod,
);

/// Typed access to the [lastLoginMethodClient] actions.
extension LastLoginMethodActions on AuthRoutes {
  /// The last used login method, or `null`.
  Future<String?> getLastUsedLoginMethod() =>
      (pluginsActions['getLastUsedLoginMethod']!
          as Future<String?> Function())();

  /// Forgets the last used login method.
  Future<void> clearLastUsedLoginMethod() =>
      (pluginsActions['clearLastUsedLoginMethod']!
          as Future<void> Function())();

  /// Whether [method] was the last used login method.
  Future<bool> isLastUsedLoginMethod(String method) =>
      (pluginsActions['isLastUsedLoginMethod']!
          as Future<bool> Function(String))(method);
}
