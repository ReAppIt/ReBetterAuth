import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/convex.dart';

/// Records `setAuth`/`clearAuth` into [events] and keeps the last callbacks.
class _FakeConvexClient implements ConvexAuthClient {
  _FakeConvexClient(this.events);

  final List<String> events;
  AuthTokenFetcher? fetchToken;
  void Function(bool isAuthenticated)? onChange;
  void Function(bool isRefreshing)? onRefreshChange;

  @override
  void setAuth(
    AuthTokenFetcher fetchToken,
    void Function(bool isAuthenticated) onChange, [
    void Function(bool isRefreshing)? onRefreshChange,
  ]) {
    events.add('setAuth');
    this.fetchToken = fetchToken;
    this.onChange = onChange;
    this.onRefreshChange = onRefreshChange;
  }

  @override
  void clearAuth() => events.add('clearAuth');
}

Future<String?> _fetchA({required bool forceRefreshToken}) async => 'a';
Future<String?> _fetchB({required bool forceRefreshToken}) async => 'b';

ConvexAuthProviderState _provider({
  bool loading = false,
  bool authenticated = false,
  AuthTokenFetcher fetch = _fetchA,
}) => ConvexAuthProviderState(
  isLoading: loading,
  isAuthenticated: authenticated,
  fetchAccessToken: fetch,
);

ConvexAuthState _state({
  bool loading = false,
  bool authenticated = false,
  bool refreshing = false,
}) => ConvexAuthState(
  isLoading: loading,
  isAuthenticated: authenticated,
  isRefreshing: refreshing,
);

void main() {
  late List<String> events;
  late _FakeConvexClient client;

  setUp(() {
    events = <String>[];
    client = _FakeConvexClient(events);
  });

  test('stays loading until the provider resolves a signed-out user', () {
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(loading: true),
    );
    final controller = ConvexAuthController(client: client, auth: auth);
    expect(controller.state.value, _state(loading: true));

    auth.value = _provider();
    expect(controller.state.value, _state());
    expect(events, isEmpty);
  });

  test('authenticates a signed-in user and follows the backend', () {
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(authenticated: true),
    );
    final controller = ConvexAuthController(client: client, auth: auth);
    expect(events, <String>['setAuth']);
    expect(client.fetchToken, same(_fetchA));
    expect(controller.state.value, _state(loading: true));

    client.onChange!(true);
    expect(controller.state.value, _state(authenticated: true));
    client.onChange!(false);
    expect(controller.state.value, _state());
  });

  test('publishes the sign-out before clearing Convex auth', () {
    final effects = <VoidCallback>[];
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(authenticated: true),
    );
    final controller = ConvexAuthController(
      client: client,
      auth: auth,
      scheduleEffects: effects.add,
    );
    effects.removeAt(0)();
    client.onChange!(true);
    controller.state.addListener(
      () => events.add(
        'authenticated: ${controller.state.value.isAuthenticated}',
      ),
    );

    auth.value = _provider();
    expect(events, <String>['setAuth', 'authenticated: false']);
    effects.removeAt(0)();
    expect(events, <String>['setAuth', 'authenticated: false', 'clearAuth']);
    expect(controller.state.value, _state());
  });

  test('authenticates again when the token fetcher changes', () {
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(authenticated: true),
    );
    final controller = ConvexAuthController(client: client, auth: auth);
    final staleOnChange = client.onChange!;
    staleOnChange(true);

    auth.value = _provider(authenticated: true, fetch: _fetchB);
    expect(events, <String>['setAuth', 'clearAuth', 'setAuth']);
    expect(client.fetchToken, same(_fetchB));
    expect(controller.state.value, _state(loading: true));

    staleOnChange(true);
    expect(controller.state.value, _state(loading: true));
    client.onChange!(true);
    expect(controller.state.value, _state(authenticated: true));
  });

  test('reports refreshing only while authenticated', () {
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(authenticated: true),
    );
    final controller = ConvexAuthController(client: client, auth: auth);
    client
      ..onChange!(true)
      ..onRefreshChange!(true);
    expect(
      controller.state.value,
      _state(authenticated: true, refreshing: true),
    );

    client.onChange!(false);
    expect(controller.state.value, _state());
  });

  test('goes back to loading while the provider reloads', () {
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(authenticated: true),
    );
    final controller = ConvexAuthController(client: client, auth: auth);
    client.onChange!(true);

    auth.value = _provider(loading: true, authenticated: true);
    expect(controller.state.value.isLoading, isTrue);
  });

  test('dispose clears Convex auth and ignores late answers', () {
    final auth = ValueNotifier<ConvexAuthProviderState>(
      _provider(authenticated: true),
    );
    final controller = ConvexAuthController(client: client, auth: auth);
    final onChange = client.onChange!;

    controller.dispose();
    expect(events, <String>['setAuth', 'clearAuth']);
    onChange(true);
    auth.value = _provider();
    expect(events, <String>['setAuth', 'clearAuth']);
  });
}
