import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/vanilla.dart';

import '../../support/fakes.dart';
import '../../support/test_plugin.dart';

SessionData _session(String userId, String email, String sessionId) =>
    SessionData(<String, Object?>{
      'user': <String, Object?>{
        'id': userId,
        'name': 'User $userId',
        'email': email,
        'emailVerified': false,
        'createdAt': DateTime.utc(2026),
        'updatedAt': DateTime.utc(2026),
      },
      'session': <String, Object?>{
        'id': sessionId,
        'userId': userId,
        'expiresAt': DateTime.utc(2027),
        'token': 'token-$sessionId',
        'createdAt': DateTime.utc(2026),
        'updatedAt': DateTime.utc(2026),
      },
    });

void main() {
  setUp(resetGlobals);
  tearDown(resetGlobals);

  group('run time proxy', () {
    test('exposes the real \$fetch and \$store', () {
      final client = createAuthClient();
      expect(client.$fetch, isA<BetterFetch>());
      expect(client.$store.atoms['session'], same(client.useSession));
    });

    test('proxy api should be called', () async {
      var apiCalled = false;
      final client = createAuthClient(
        plugins: [TestClientPlugin()],
        fetchOptions: ClientFetchOption(
          baseURL: 'http://localhost:3000',
          customFetchImpl: FakeFetch((_) {
            apiCalled = true;
            return emptyResponse();
          }).call,
        ),
      );
      await client<Object?>('/test');
      expect(apiCalled, isTrue);
    });

    test('state listener should be called on matched path', () {
      fakeAsync((async) {
        final plugin = TestClientPlugin();
        final client = createAuthClient(
          plugins: [plugin],
          fetchOptions: ClientFetchOption(
            baseURL: 'http://localhost:3000',
            customFetchImpl: FakeFetch((_) => emptyResponse()).call,
          ),
        );
        var changes = 0;
        plugin.$test.listen((_, _) => changes++);
        client<Object?>('/test').ignore();
        async.elapse(const Duration(milliseconds: 100));
        expect(changes, 1);
      });
    });

    test('should call useSession', () {
      fakeAsync((async) {
        var returnNull = false;
        final client = createAuthClient(
          plugins: [TestClientPlugin()],
          fetchOptions: ClientFetchOption(
            baseURL: 'http://localhost:3000',
            customFetchImpl: FakeFetch((_) {
              if (returnNull) return jsonResponse(null);
              return jsonResponse(<String, Object?>{
                'user': <String, Object?>{'id': 1, 'email': 'test@email.com'},
              });
            }).call,
          ),
        );
        final res = client.useSession..listen((_, _) {});
        async.flushTimers();
        expect(res.value.data?.user.id, '1');
        expect(res.value.data?.user.email, 'test@email.com');
        expect(res.value.error, isNull);
        expect(res.value.isPending, isFalse);

        returnNull = true;
        client<Object?>('/test2/sign-out').ignore();
        async.flushTimers();
        expect(res.value.data, isNull);
        expect(res.value.error, isNull);
        expect(res.value.isPending, isFalse);
      });
    });

    test('should hydrate session on an existing client', () {
      fakeAsync((async) {
        final client = createAuthClient(
          fetchOptions: ClientFetchOption(
            baseURL: 'http://localhost:3000',
            customFetchImpl: FakeFetch(
              (_) => jsonResponse(<String, Object?>{
                'user': <String, Object?>{
                  'id': '2',
                  'email': 'fresh@email.com',
                },
                'session': <String, Object?>{'id': 'session-2'},
              }),
            ).call,
          ),
        )..hydrateSession(_session('1', 'hydrated@email.com', 'session-1'));

        final session = client.useSession;
        expect(session.get().data?.user.email, 'hydrated@email.com');
        expect(session.get().isPending, isFalse);
        expect(session.get().isRefetching, isFalse);

        session.listen((_, _) {});
        async.flushTimers();
        expect(session.value.data?.user.email, 'fresh@email.com');
        expect(session.value.data?.session.id, 'session-2');
        expect(session.value.isRefetching, isFalse);
      });
    });

    test('should not overwrite session when already hydrated', () {
      final client =
          createAuthClient(
              fetchOptions: ClientFetchOption(
                baseURL: 'http://localhost:3000',
                customFetchImpl: FakeFetch((_) => jsonResponse(null)).call,
              ),
            )
            ..hydrateSession(_session('1', 'first@email.com', 'session-1'))
            ..hydrateSession(_session('2', 'second@email.com', 'session-2'));
      expect(client.useSession.value.data?.user.email, 'first@email.com');
    });

    test('should not hydrate when session is null', () {
      final client = createAuthClient(
        fetchOptions: ClientFetchOption(
          baseURL: 'http://localhost:3000',
          customFetchImpl: FakeFetch((_) => jsonResponse(null)).call,
        ),
      )..hydrateSession(null);
      expect(client.useSession.value.data, isNull);
      expect(client.useSession.value.isPending, isTrue);
    });

    test('should not re-hydrate after the session atom was cleared', () {
      final client = createAuthClient(
        fetchOptions: ClientFetchOption(
          baseURL: 'http://localhost:3000',
          customFetchImpl: FakeFetch((_) => jsonResponse(null)).call,
        ),
      );
      final initialSession = _session('1', 'hydrated@email.com', 'session-1');
      client.hydrateSession(initialSession);

      final sessionAtom = client.useSession;
      final current = sessionAtom.value;
      sessionAtom.set(
        AuthQueryState<SessionData>(
          data: null,
          error: current.error,
          isPending: false,
          isRefetching: current.isRefetching,
          refetch: current.refetch,
        ),
      );
      client.hydrateSession(initialSession);
      expect(sessionAtom.value.data, isNull);
    });

    test('should run per-call fetch options hooks', () async {
      var called = false;
      final client = createAuthClient(
        plugins: [TestClientPlugin()],
        fetchOptions: ClientFetchOption(
          baseURL: 'http://localhost:3000',
          customFetchImpl: FakeFetch((_) => emptyResponse()).call,
        ),
      );
      await client<Object?>(
        '/test',
        fetchOptions: ClientFetchOption(onSuccess: (_) => called = true),
      );
      expect(called, isTrue);
    });

    test('exposes core and plugin error codes', () {
      final client = createAuthClient();
      expect(
        client.$errorCodes['USER_ALREADY_EXISTS']?.message,
        'User already exists.',
      );
    });
  });

  group('plugin actions deep merge', () {
    test('merges actions from plugins with the same top-level key', () async {
      final client = createAuthClient(
        plugins: [DeepMergePluginA(), DeepMergePluginB()],
      );
      final signIn = client.pluginsActions['signIn']! as Map<String, Object?>;
      final methodA = signIn['methodA']! as Future<Object?> Function();
      final methodB = signIn['methodB']! as Future<Object?> Function();
      expect(await methodA(), {'success': true, 'method': 'A'});
      expect(await methodB(), {'success': true, 'method': 'B'});
    });

    test('keeps both methods regardless of plugin order', () {
      final ab = createAuthClient(
        plugins: [DeepMergePluginA(), DeepMergePluginB()],
      );
      final ba = createAuthClient(
        plugins: [DeepMergePluginB(), DeepMergePluginA()],
      );
      for (final client in [ab, ba]) {
        final signIn = client.pluginsActions['signIn']! as Map<String, Object?>;
        expect(signIn.keys, containsAll(<String>['methodA', 'methodB']));
      }
    });
  });

  group('typed routes', () {
    test('sends the documented paths, methods and bodies', () async {
      final fake = FakeFetch((_) => jsonResponse(<String, Object?>{}));
      final client = createAuthClient(
        baseURL: 'http://localhost:3000',
        fetchOptions: ClientFetchOption(customFetchImpl: fake.call),
      );
      await client.signIn.email(email: 'a@b.c', password: 'pw');
      await client.signUp.email(name: 'A', email: 'a@b.c', password: 'pw');
      await client.signOut();
      await client.getSession(
        query: const SessionQueryParams(disableCookieCache: true),
      );
      await client.revokeSessions();
      await client.updateUser(
        name: 'B',
        additionalFields: <String, Object?>{'favoriteColor': 'blue'},
      );
      await client.verifyEmail(token: 't');

      final calls = <String>[
        for (final r in fake.requests) '${r.method} ${r.uri.path}',
      ];
      expect(calls, [
        'POST /api/auth/sign-in/email',
        'POST /api/auth/sign-up/email',
        'POST /api/auth/sign-out',
        'GET /api/auth/get-session',
        'POST /api/auth/revoke-sessions',
        'POST /api/auth/update-user',
        'GET /api/auth/verify-email',
      ]);
      expect(fake.requests[0].json, {'email': 'a@b.c', 'password': 'pw'});
      expect(fake.requests[3].uri.queryParameters, {
        'disableCookieCache': 'true',
      });
      expect(fake.requests[5].json, {'favoriteColor': 'blue', 'name': 'B'});
      expect(fake.requests[6].uri.queryParameters, {'token': 't'});
    });

    test('sends the account fields of Better Auth 1.6 and 1.7', () async {
      final fake = FakeFetch((_) => jsonResponse(<String, Object?>{}));
      final client = createAuthClient(
        baseURL: 'http://localhost:3000',
        fetchOptions: ClientFetchOption(customFetchImpl: fake.call),
      );
      // Better Auth 1.6 fields.
      await client.unlinkAccount(providerId: 'google');
      await client.getAccessToken(providerId: 'google', accountId: 'g-1');
      await client.refreshToken(providerId: 'google');
      await client.accountInfo();
      // Better Auth 1.7 fields.
      await client.unlinkAccount(accountId: 'acc-1');
      await client.getAccessToken(accountId: 'acc-1');
      await client.refreshToken(useAccountCookie: true);
      await client.accountInfo(accountId: 'acc-1', userId: 'u1');

      final calls = <String>[
        for (final r in fake.requests) '${r.method} ${r.uri.path}',
      ];
      expect(calls, [
        'POST /api/auth/unlink-account',
        'POST /api/auth/get-access-token',
        'POST /api/auth/refresh-token',
        'GET /api/auth/account-info',
        'POST /api/auth/unlink-account',
        'POST /api/auth/get-access-token',
        'POST /api/auth/refresh-token',
        'GET /api/auth/account-info',
      ]);
      expect(fake.requests[0].json, {'providerId': 'google'});
      expect(fake.requests[1].json, {
        'providerId': 'google',
        'accountId': 'g-1',
      });
      expect(fake.requests[2].json, {'providerId': 'google'});
      expect(fake.requests[3].uri.query, isEmpty);
      expect(fake.requests[4].json, {'accountId': 'acc-1'});
      expect(fake.requests[5].json, {'accountId': 'acc-1'});
      expect(fake.requests[6].json, {'useAccountCookie': true});
      expect(fake.requests[7].uri.queryParameters, {
        'accountId': 'acc-1',
        'userId': 'u1',
      });
    });

    test('wraps responses in typed views', () async {
      final client = createAuthClient(
        baseURL: 'http://localhost:3000',
        fetchOptions: ClientFetchOption(
          customFetchImpl: FakeFetch((request) {
            if (request.uri.path.endsWith('/list-sessions')) {
              return jsonResponse(<Object?>[
                <String, Object?>{'id': 's1', 'userId': 'u1', 'token': 't1'},
              ]);
            }
            return jsonResponse(<String, Object?>{
              'redirect': false,
              'token': 'tok',
              'user': <String, Object?>{'id': 'u1', 'email': 'a@b.c'},
            });
          }).call,
        ),
      );
      final signIn = await client.signIn.email(email: 'a@b.c', password: 'pw');
      expect(signIn.data?.token, 'tok');
      expect(signIn.data?.user?.email, 'a@b.c');
      final sessions = await client.listSessions();
      expect(sessions.data?.single.token, 't1');
    });
  });
}
