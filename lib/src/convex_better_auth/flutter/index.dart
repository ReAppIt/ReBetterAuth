import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:re_better_auth/src/better_auth/client/flutter/index.dart';
import 'package:re_better_auth/src/better_auth/client/query.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/convex/browser/sync/authentication_manager.dart';
import 'package:re_better_auth/src/convex/flutter/convex_auth_state.dart';
import 'package:re_better_auth/src/convex_better_auth/plugins/convex/client.dart';

/// The Better Auth session as a [ConvexAuthProviderState]: tokens come from
/// `/convex/token` and stay cached until forced or the session changes.
class AuthFromBetterAuth extends ChangeNotifier
    implements ValueListenable<ConvexAuthProviderState> {
  /// Follows [authClient]'s session until [dispose].
  AuthFromBetterAuth(this.authClient) {
    _session.addListener(_render);
    _render();
  }

  /// The Better Auth client.
  final FlutterAuthClient authClient;

  late final ValueListenable<AuthQueryState<SessionData>> _session =
      authClient.useSession;
  late AuthTokenFetcher _fetchAccessToken = _createFetcher();
  ConvexAuthProviderState? _value;
  String? _sessionId;
  String? _cachedToken;
  Future<String?>? _pendingToken;
  AuthQueryState<SessionData>? _tokenFailedAt;
  bool _disposed = false;

  @override
  ConvexAuthProviderState get value => _value!;

  void _render() {
    if (_disposed) return;
    final query = _session.value;
    final session = query.data;
    final sessionId = session?.session.id;
    if (sessionId != _sessionId) {
      // A new fetcher makes Convex authenticate again, for the new session.
      _sessionId = sessionId;
      _cachedToken = null;
      _pendingToken = null;
      _tokenFailedAt = null;
      _fetchAccessToken = _createFetcher();
    } else if (_tokenFailedAt != null &&
        !identical(query, _tokenFailedAt) &&
        session != null &&
        !query.isRefetching &&
        query.error == null) {
      // The session refreshed since the token failed: retry with a new fetcher.
      _tokenFailedAt = null;
      _fetchAccessToken = _createFetcher();
    }
    final next = ConvexAuthProviderState(
      isLoading: query.isPending && _cachedToken == null,
      isAuthenticated: session != null || _cachedToken != null,
      fetchAccessToken: _fetchAccessToken,
    );
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  AuthTokenFetcher _createFetcher() => ({required bool forceRefreshToken}) {
    final cachedToken = _cachedToken;
    if (cachedToken != null && !forceRefreshToken) {
      return Future<String?>.value(cachedToken);
    }
    final pending = _pendingToken;
    if (!forceRefreshToken && pending != null) return pending;
    late final Future<String?> request;
    request = _requestToken().whenComplete(() {
      if (identical(_pendingToken, request)) _pendingToken = null;
    });
    _pendingToken = request;
    return request;
  };

  Future<String?> _requestToken() async {
    final sessionId = _sessionId;
    String? token;
    try {
      final res = await authClient.convex.token(
        fetchOptions: ClientFetchOption(throwOnError: false),
      );
      final value = res.data?.token;
      token = value == null || value.isEmpty ? null : value;
    } on Object {
      token = null;
    }
    if (!_disposed && sessionId == _sessionId) {
      _cachedToken = token;
      _tokenFailedAt = token == null && sessionId != null
          ? _session.value
          : null;
      _render();
    }
    return token;
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeListener(_render);
    super.dispose();
  }
}

/// Authenticates [client] with Convex tokens for [authClient]'s session and
/// provides `useConvexAuth` to [child].
class ConvexBetterAuthProvider extends StatefulWidget {
  /// Creates the provider.
  const ConvexBetterAuthProvider({
    super.key,
    required this.client,
    required this.authClient,
    required this.child,
  });

  /// The Convex client's auth calls, such as a [ConvexTokenAuth].
  final ConvexAuthClient client;

  /// The Better Auth client, with the `convexClient()` plugin.
  final FlutterAuthClient authClient;

  /// The subtree.
  final Widget child;

  @override
  State<ConvexBetterAuthProvider> createState() =>
      _ConvexBetterAuthProviderState();
}

class _ConvexBetterAuthProviderState extends State<ConvexBetterAuthProvider> {
  late AuthFromBetterAuth _auth;

  @override
  void initState() {
    super.initState();
    _auth = AuthFromBetterAuth(widget.authClient);
  }

  @override
  void didUpdateWidget(ConvexBetterAuthProvider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.authClient, widget.authClient)) return;
    _auth.dispose();
    _auth = AuthFromBetterAuth(widget.authClient);
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ConvexProviderWithAuth(
    client: widget.client,
    useAuth: _auth,
    child: widget.child,
  );
}
