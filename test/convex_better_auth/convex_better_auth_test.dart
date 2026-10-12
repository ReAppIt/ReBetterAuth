import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/convex.dart';
import 'package:re_better_auth/re_better_auth.dart';

import '../support/fakes.dart';

Map<String, Object?> _session(String id) => <String, Object?>{
  'user': <String, Object?>{'id': 'u1', 'email': 'a@b.c'},
  'session': <String, Object?>{'id': id, 'userId': 'u1'},
};

/// A server with a switchable session and numbered Convex tokens.
class _Server {
  Map<String, Object?>? session = _session('s1');
  bool tokenFails = false;
  int tokenRequests = 0;

  late final FakeFetch fetch = FakeFetch((request) {
    final path = request.uri.path;
    if (path.endsWith('/get-session')) return jsonResponse(session);
    if (path.endsWith('/convex/token')) {
      tokenRequests++;
      if (tokenFails) return jsonResponse(null, status: 500);
      return jsonResponse(<String, Object?>{'token': 'jwt-$tokenRequests'});
    }
    return jsonResponse(<String, Object?>{});
  });

  FlutterAuthClient client() => createAuthClient(
    baseURL: 'http://localhost:3000',
    plugins: <BetterAuthClientPlugin>[convexClient()],
    fetchOptions: ClientFetchOption(customFetchImpl: fetch.call),
  );
}

String? _fetchNow(
  FakeAsync async,
  AuthTokenFetcher fetch, {
  bool force = false,
}) {
  String? token;
  var done = false;
  fetch(forceRefreshToken: force).then((value) {
    token = value;
    done = true;
  });
  async.flushTimers();
  expect(done, isTrue);
  return token;
}

void main() {
  setUp(resetGlobals);
  tearDown(resetGlobals);

  test('convexClient has the upstream plugin id', () {
    expect(convexClient().id, 'convex');
  });

  test('convex.token() gets the JWT from GET /convex/token', () async {
    final server = _Server();
    final res = await server.client().convex.token();
    expect(res.data?.token, 'jwt-1');
    final request = server.fetch.requests.single;
    expect(
      '${request.method} ${request.uri.path}',
      'GET /api/auth/convex/token',
    );
  });

  group('AuthFromBetterAuth', () {
    test('loads with the session and caches the token', () {
      fakeAsync((async) {
        final server = _Server();
        final auth = AuthFromBetterAuth(server.client());
        expect(auth.value.isLoading, isTrue);
        expect(auth.value.isAuthenticated, isFalse);
        async.flushTimers();
        expect(auth.value.isLoading, isFalse);
        expect(auth.value.isAuthenticated, isTrue);

        final fetch = auth.value.fetchAccessToken;
        final first = fetch(forceRefreshToken: false);
        expect(fetch(forceRefreshToken: false), same(first));
        async.flushMicrotasks();
        expect(server.tokenRequests, 1);
        expect(_fetchNow(async, fetch), 'jwt-1');
        expect(server.tokenRequests, 1);
        expect(_fetchNow(async, fetch, force: true), 'jwt-2');
        expect(server.tokenRequests, 2);
        expect(auth.value.fetchAccessToken, same(fetch));
        auth.dispose();
      });
    });

    test('makes a new fetcher without the token for a new session', () {
      fakeAsync((async) {
        final server = _Server();
        final client = server.client();
        final auth = AuthFromBetterAuth(client);
        async.flushTimers();
        final first = auth.value.fetchAccessToken;
        expect(_fetchNow(async, first), 'jwt-1');

        server.session = _session('s2');
        client.useSession.value.refetch();
        async.flushTimers();
        final second = auth.value.fetchAccessToken;
        expect(second, isNot(same(first)));
        expect(_fetchNow(async, second), 'jwt-2');
        auth.dispose();
      });
    });

    test('is signed out once the session is gone', () {
      fakeAsync((async) {
        final server = _Server();
        final client = server.client();
        final auth = AuthFromBetterAuth(client);
        async.flushTimers();
        expect(_fetchNow(async, auth.value.fetchAccessToken), 'jwt-1');

        server.session = null;
        client.useSession.value.refetch();
        async.flushTimers();
        expect(auth.value.isAuthenticated, isFalse);
        expect(auth.value.isLoading, isFalse);
        auth.dispose();
      });
    });

    test('retries a failed token after the next good session refresh', () {
      fakeAsync((async) {
        final server = _Server()..tokenFails = true;
        final client = server.client();
        final auth = AuthFromBetterAuth(client);
        async.flushTimers();
        final failed = auth.value.fetchAccessToken;
        expect(_fetchNow(async, failed), isNull);
        expect(_fetchNow(async, failed, force: true), isNull);
        expect(auth.value.fetchAccessToken, same(failed));

        server.tokenFails = false;
        client.useSession.value.refetch();
        async.flushTimers();
        final retry = auth.value.fetchAccessToken;
        expect(retry, isNot(same(failed)));
        expect(_fetchNow(async, retry), 'jwt-3');
        auth.dispose();
      });
    });
  });
}
