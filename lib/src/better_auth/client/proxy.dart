import 'dart:async';

import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// Method for [path]: forced by [knownPathMethods], else `fetchOptions.method`,
/// else POST when [body] has entries, else GET.
String getMethod(
  String path,
  Map<String, String> knownPathMethods, {
  Map<String, Object?>? body,
  ClientFetchOption? fetchOptions,
}) {
  final method = knownPathMethods[path];
  if (method != null) return method;
  final explicit = fetchOptions?.method;
  if (explicit != null) return explicit;
  if (body != null && body.isNotEmpty) return 'POST';
  return 'GET';
}

/// Sends [routePath] like the JS dynamic proxy for `client.a.b(args)`; on
/// success flips matching atom signals 10 ms later unless `disableSignal`.
Future<BetterFetchResponse<T>> callDynamicPath<T>(
  String routePath, {
  required BetterFetch client,
  required Map<String, String> knownPathMethods,
  required Map<String, Atom<Object?>> atoms,
  required List<ClientAtomListener> atomListeners,
  Map<String, Object?>? body,
  Map<String, Object?>? query,
  ClientFetchOption? fetchOptions,
  ClientFetchOption? defaultFetchOptions,
}) {
  final options = (defaultFetchOptions ?? ClientFetchOption()).merge(
    fetchOptions,
  );
  final method = getMethod(
    routePath,
    knownPathMethods,
    body: body,
    fetchOptions: fetchOptions,
  );
  final extraBody = options.body;
  final callOptions = options.copy()
    ..body = method == 'GET'
        ? null
        : <String, Object?>{
            ...?body,
            if (extraBody is Map<String, Object?>) ...extraBody,
          }
    ..query = query ?? options.query
    ..method = method
    ..onSuccess = (context) async {
      await options.onSuccess?.call(context);
      if (options.disableSignal ?? false) return;
      final matches = atomListeners.where((s) => s.matcher(routePath)).toList();
      if (matches.isEmpty) return;
      final visited = <String>{};
      for (final match in matches) {
        final signal = atoms[match.signal];
        if (signal == null) return;
        if (!visited.add(match.signal)) continue;
        final val = signal.get();
        Timer(const Duration(milliseconds: 10), () => signal.set(val != true));
        match.callback?.call(routePath);
      }
    };
  return client<T>(routePath, callOptions);
}
