import 'package:dio/dio.dart' show Dio;
import 'package:re_better_auth/src/better_auth/core/error_codes.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// Better-fetch options plus `disableSignal`, which lives on [BetterFetchOption].
typedef ClientFetchOption = BetterFetchOption;

/// Signals and atoms shared between the client and its plugins (`$store`).
class ClientStore {
  /// Wraps the client's [atoms].
  ClientStore(this.atoms);

  /// Every atom by name, including `$sessionSignal` and `session`.
  final Map<String, Atom<Object?>> atoms;

  /// Flips the boolean atom named [signal], waking its listeners.
  void notify(String signal) {
    final atom = atoms[signal]!;
    atom.set(!(atom.get()! as bool));
  }

  /// Subscribes [listener] to the atom named [signal].
  void listen(String signal, AtomListener<Object?> listener) {
    atoms[signal]!.subscribe(listener);
  }
}

/// Flips [signal] after a successful request whose path matches [matcher].
class ClientAtomListener {
  /// Creates a listener.
  const ClientAtomListener({
    required this.matcher,
    required this.signal,
    this.callback,
  });

  /// Whether a request path should trigger the signal.
  final bool Function(String path) matcher;

  /// Name of the boolean atom to flip.
  final String signal;

  /// Also called with the matched path.
  final void Function(String path)? callback;
}

/// When `useSession` refetches the session on its own.
class RevalidateOptions {
  /// Creates revalidation options.
  const RevalidateOptions({
    this.refetchInterval,
    this.refetchOnWindowFocus,
    this.refetchWhenOffline,
  });

  /// Polling interval while signed in; `null` or zero disables polling.
  final Duration? refetchInterval;

  /// Refetch when the app returns to the foreground; defaults to `true`.
  final bool? refetchOnWindowFocus;

  /// Keep refetching while offline; defaults to `false`.
  final bool? refetchWhenOffline;
}

/// Options for `createAuthClient`.
class BetterAuthClientOptions {
  /// Creates client options.
  const BetterAuthClientOptions({
    this.baseURL,
    this.basePath,
    this.plugins = const <BetterAuthClientPlugin>[],
    this.fetchOptions,
    this.disableDefaultFetchPlugins = false,
    this.sessionOptions,
    this.dio,
  });

  /// Server URL; `/api/auth` is appended when it has no path.
  final String? baseURL;

  /// Auth path used when [baseURL] has none; defaults to `/api/auth`.
  final String? basePath;

  /// Client plugins, applied in order.
  final List<BetterAuthClientPlugin> plugins;

  /// Defaults for every request; its hooks run as a lifecycle plugin.
  final ClientFetchOption? fetchOptions;

  /// Skips the built-in fetch plugins.
  final bool disableDefaultFetchPlugins;

  /// Session refetch behaviour.
  final RevalidateOptions? sessionOptions;

  /// Dio instance used as the transport; a shared default when `null`.
  final Dio? dio;
}

/// A client plugin; override only what it contributes.
abstract class BetterAuthClientPlugin {
  /// Const constructor for subclasses.
  const BetterAuthClientPlugin();

  /// Unique plugin id.
  String get id;

  /// Plugin version.
  String? get version => null;

  /// Actions merged into the client: nested maps of functions, called once.
  Map<String, Object?> getActions(
    BetterFetch $fetch,
    ClientStore $store,
    BetterAuthClientOptions? options,
  ) => const <String, Object?>{};

  /// Atoms added to `$store.atoms`.
  Map<String, Atom<Object?>> getAtoms(BetterFetch $fetch) =>
      const <String, Atom<Object?>>{};

  /// Forced methods for paths, such as `{'/sign-out': 'POST'}`.
  Map<String, String> get pathMethods => const <String, String>{};

  /// Better-fetch plugins installed on the client's `$fetch`.
  List<BetterFetchPlugin> get fetchPlugins => const <BetterFetchPlugin>[];

  /// Signals to flip after matching requests succeed.
  List<ClientAtomListener> get atomListeners => const <ClientAtomListener>[];

  /// Error codes the matching server plugin returns.
  Map<String, RawError> get errorCodes => const <String, RawError>{};
}
