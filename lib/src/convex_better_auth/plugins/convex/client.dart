import 'package:re_better_auth/src/better_auth/client/routes.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/version.dart';

/// `/convex/token` result.
extension type ConvexToken(JsonMap json) {
  /// The Convex JWT.
  String? get token => json['token'] as String?;
}

/// Client side of the server's `convex()` plugin; see [convexClient].
class ConvexClientPlugin extends BetterAuthClientPlugin {
  /// Creates the plugin.
  const ConvexClientPlugin();

  @override
  String get id => 'convex';

  @override
  String get version => packageVersion;
}

/// The client plugin for `@convex-dev/better-auth`'s server `convex()` plugin;
/// its endpoints are on `authClient.convex`.
ConvexClientPlugin convexClient() => const ConvexClientPlugin();

/// Endpoints of the server's `convex()` plugin.
class ConvexRoutes {
  /// Creates the namespace for [client].
  const ConvexRoutes(this.client);

  /// The client this namespace calls through.
  final AuthRoutes client;

  /// Exchanges the session for a Convex JWT.
  Future<BetterFetchResponse<ConvexToken>> token({
    ClientFetchOption? fetchOptions,
  }) async {
    final res = await client.call<JsonMap>(
      '/convex/token',
      fetchOptions: fetchOptions,
    );
    final data = res.data;
    return (data: data == null ? null : ConvexToken(data), error: res.error);
  }
}

/// Typed access to the server's `convex()` plugin.
extension ConvexAuthRoutes on AuthRoutes {
  /// `/convex/*` endpoints.
  ConvexRoutes get convex => ConvexRoutes(this);
}
