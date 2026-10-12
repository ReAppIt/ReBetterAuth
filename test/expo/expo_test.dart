import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart'
    show ConnectivityResult;
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http_parser/http_parser.dart' show formatHttpDate;
import 'package:re_better_auth/vanilla.dart';

import '../support/fake_auth_server.dart';
import '../support/fakes.dart';

const String scheme = 'better-auth';

AuthClient makeClient({
  required FakeAuthServer server,
  required FlutterClientStorage storage,
  FakeBrowser? browser,
  FlutterWebAuth2Options webAuthOptions = const FlutterWebAuth2Options(),
  bool disableCache = false,
}) => createAuthClient(
  baseURL: 'http://localhost:3000',
  plugins: [
    flutterClient(
      scheme: scheme,
      storage: storage,
      webAuthOptions: webAuthOptions,
      disableCache: disableCache,
      openAuthSession: (browser ?? FakeBrowser()).call,
    ),
  ],
  fetchOptions: ClientFetchOption(customFetchImpl: server.fetch.call),
);

Map<String, Object?> storedCookies(MemoryStorage storage) =>
    jsonDecode(storage.map['better-auth_cookie'] ?? '{}')
        as Map<String, Object?>;

SuccessContext cookieResponse(String setCookie) => SuccessContext(
  data: null,
  response: FetchResponse(
    status: 200,
    bodyBytes: Uint8List(0),
    headers: FetchHeaders(<String, List<String>>{
      'set-cookie': <String>[setCookie],
    }),
  ),
  request: RequestContext(
    url: Uri.parse('https://example.com/api/auth/test'),
    headers: <String, String>{},
    body: null,
    method: 'GET',
    signal: CancelToken(),
    options: ClientFetchOption(),
  ),
);

Future<void> applyCookieResponse(
  FlutterClientPlugin plugin,
  String setCookie,
) => Future<void>.value(
  plugin.fetchPlugins.first.hooks!.onSuccess!(cookieResponse(setCookie)),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetGlobals);
  tearDown(resetGlobals);

  test('should preserve the public storage exports', () {
    expect(
      normalizeCookieName('better-auth:session_token'),
      'better-auth_session_token',
    );
    expect(storageAdapter(MemoryStorage()), isA<FlutterClientStorage>());
  });

  group('expo', () {
    late FakeAuthServer server;
    late MemoryStorage storage;
    late FakeBrowser browser;
    late AuthClient client;

    setUp(() {
      server = FakeAuthServer();
      storage = MemoryStorage();
      browser = FakeBrowser();
      client = makeClient(server: server, storage: storage, browser: browser);
    });

    test('should store cookie with expires date', () async {
      await client.signIn.email(email: 'test@test.com', password: 'password');
      final token = storedCookies(storage)['better-auth.session_token']! as Map;
      expect(token['value'], isNotEmpty);
      expect(token['expires'], isA<String>());
    });

    test('should send cookie and get session', () async {
      await client.signIn.email(email: 'test@test.com', password: 'password');
      final (:data, error: _) = await client.getSession();
      expect(data?.session.id, 'session-1');
      expect(data?.user.id, 'user-1');
    });

    test('should use the scheme to open the browser', () async {
      final (data: res, error: _) = await client.signIn.social(
        provider: 'google',
        callbackURL: '/dashboard',
      );
      final request = server.requests.last;
      expect(request.json?['callbackURL'], 'better-auth:///dashboard');
      expect(res?.url, contains('accounts.google'));
      expect(browser.calls.single.url, contains('accounts.google'));
      expect(browser.calls.single.callbackUrlScheme, scheme);
    });

    test('should pass webAuthOptions to the browser session', () async {
      final ephemeralClient = makeClient(
        server: server,
        storage: storage,
        browser: browser,
        webAuthOptions: const FlutterWebAuth2Options(preferEphemeral: true),
      );
      await ephemeralClient.signIn.social(
        provider: 'google',
        callbackURL: '/dashboard',
      );
      expect(browser.calls.single.url, contains('accounts.google'));
      expect(browser.calls.single.options.preferEphemeral, isTrue);
    });

    test('should get cookies', () async {
      await client.signIn.email(email: 'test@test.com', password: 'password');
      expect(await client.getCookie(), contains('better-auth.session_token'));
    });

    test('should remove expired cookies from store when Max-Age=0', () {
      final prevCookie = jsonEncode(<String, Object?>{
        'better-auth.session_token': <String, Object?>{
          'value': 'abc123',
          'expires': null,
        },
        'better-auth.session_data': <String, Object?>{
          'value': 'xyz789',
          'expires': null,
        },
      });
      const header =
          'better-auth.session_token=; Max-Age=0, better-auth.session_data=; Max-Age=0';
      final result = jsonDecode(getSetCookie(header, prevCookie)) as Map;
      expect(result['better-auth.session_token'], isNull);
      expect(result['better-auth.session_data'], isNull);
    });

    test('should remove cookies with past Expires from store', () {
      final prevCookie = jsonEncode(<String, Object?>{
        'better-auth.session_token': <String, Object?>{
          'value': 'abc123',
          'expires': null,
        },
      });
      final pastDate = formatHttpDate(
        DateTime.now().subtract(const Duration(seconds: 1)),
      );
      final result =
          jsonDecode(
                getSetCookie(
                  'better-auth.session_token=; Expires=$pastDate',
                  prevCookie,
                ),
              )
              as Map;
      expect(result['better-auth.session_token'], isNull);
    });

    test('should parse multiple Set-Cookie headers with Expires commas', () {
      final map = parseSetCookieHeader(
        'better-auth.session_token=abc; Expires=Wed, 21 Oct 2015 07:28:00 GMT; Path=/, '
        'better-auth.session_data=xyz; Expires=Thu, 22 Oct 2015 07:28:00 GMT; Path=/',
      );
      expect(map['better-auth.session_token']?.value, 'abc');
      expect(map['better-auth.session_data']?.value, 'xyz');
      expect(
        map['better-auth.session_token']?.expires,
        DateTime.utc(2015, 10, 21, 7, 28),
      );
    });

    test('should skip cookies with empty names', () {
      const malformedHeader = '; abc.state=xyz; Path=/';
      expect(parseSetCookieHeader(malformedHeader).containsKey(''), isFalse);

      final parsed2 = parseSetCookieHeader(
        '=empty-value; Path=/, valid-cookie=value; Path=/',
      );
      expect(parsed2.containsKey(''), isFalse);
      expect(parsed2['valid-cookie']?.value, 'value');

      final prevCookie = jsonEncode(<String, Object?>{
        'abc.session_token': <String, Object?>{
          'value': 'valid-token',
          'expires': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      });
      final result =
          jsonDecode(getSetCookie(malformedHeader, prevCookie)) as Map;
      expect((result['abc.session_token'] as Map)['value'], 'valid-token');
    });

    test('should not trigger infinite refetch with non-better-auth cookies', () {
      bool has(String header, List<String> prefix) =>
          hasBetterAuthCookies(header, prefix);
      const ba = <String>['better-auth'];
      expect(has('better-auth.session_token=abc; Path=/', ba), isTrue);
      expect(has('better-auth.session_data=xyz; Path=/', ba), isTrue);
      expect(has('__Secure-better-auth.session_token=abc; Path=/', ba), isTrue);
      expect(has('__Secure-better-auth.session_data=xyz; Path=/', ba), isTrue);
      expect(has('__cf_bm=abc123; Path=/; HttpOnly; Secure', ba), isFalse);
      expect(
        has(
          '__cf_bm=abc123; Path=/; HttpOnly; Secure, better-auth.session_token=xyz; Path=/',
          ba,
        ),
        isTrue,
      );
      expect(has('my-app.session_token=abc; Path=/', const ['my-app']), isTrue);
      expect(has('my-app.session_token=abc; Path=/', ba), isFalse);
      expect(has('my-app.session_data=abc; Path=/', const ['my-app']), isTrue);
      expect(has('session_token=abc; Path=/', const ['']), isTrue);
      expect(has('my_custom_session_token=abc; Path=/', const ['']), isTrue);
      expect(has('my_custom_session_data=xyz; Path=/', const ['']), isTrue);
      expect(
        has(
          '__cf_bm=abc123; Path=/, _ga=GA1.2.123456789.1234567890; Path=/',
          ba,
        ),
        isFalse,
      );
      expect(has('better-auth.other_cookie=abc; Path=/', ba), isTrue);
      expect(has('better-auth-passkey=xyz; Path=/', ba), isTrue);
      expect(has('__Secure-better-auth-passkey=xyz; Path=/', ba), isTrue);
      expect(has('better-auth-custom-challenge=xyz; Path=/', ba), isTrue);
    });

    test('should preserve unchanged session properties on sign-out', () async {
      final atom = client.useSession;
      final before = atom.get();
      await client.signOut();
      final after = atom.get();
      expect(after.data, isNull);
      expect(after.error, isNull);
      expect(after.isPending, isFalse);
      expect(after.isRefetching, before.isRefetching);
      expect(after.refetch, same(before.refetch));
    });

    test('should send the expo-origin header instead of origin', () async {
      await client.signIn.email(
        email: 'test@test.com',
        password: 'password',
        callbackURL: 'http://localhost:3000/callback',
      );
      final headers = server.requests.last.headers;
      expect(headers['expo-origin'], 'better-auth://');
      expect(headers['x-skip-oauth-proxy'], 'true');
      expect(headers.containsKey('origin'), isFalse);
    });

    test(
      'should not send cookie or expo-origin for ID token requests',
      () async {
        storage.map['better-auth_cookie'] = jsonEncode(<String, Object?>{
          'better-auth.session_token': <String, Object?>{
            'value': 'existing-token',
            'expires': DateTime.now()
                .toUtc()
                .add(const Duration(hours: 1))
                .toIso8601String(),
          },
        });
        await client.signIn.social(
          provider: 'google',
          idToken: const IdTokenCredential(token: 'fake-id-token'),
        );
        final headers = server.requests.last.headers;
        expect(headers.containsKey('cookie'), isFalse);
        expect(headers.containsKey('expo-origin'), isFalse);
        expect(headers.containsKey('origin'), isFalse);
        expect(browser.calls, isEmpty);
      },
    );

    test('should send cookie for link-social ID token requests', () async {
      storage.map['better-auth_cookie'] = jsonEncode(<String, Object?>{
        'better-auth.session_token': <String, Object?>{
          'value': 'existing-token',
          'expires': DateTime.now()
              .toUtc()
              .add(const Duration(hours: 1))
              .toIso8601String(),
        },
      });
      await client.linkSocial(
        provider: 'google',
        idToken: const IdTokenCredential(token: 'fake-id-token'),
      );
      final headers = server.requests.last.headers;
      expect(
        headers['cookie'],
        contains('better-auth.session_token=existing-token'),
      );
      expect(headers.containsKey('expo-origin'), isFalse);
    });

    test('should preserve existing cookies on link-social', () async {
      await client.signIn.email(email: 'test@test.com', password: 'password');
      const testCookie = 'better-auth.test-key';
      final before = storedCookies(storage);
      expect(before[testCookie], isNull);

      browser.next = (_) async => 'better-auth://?cookie=$testCookie=abc';
      await client.linkSocial(provider: 'google');

      final after = storedCookies(storage);
      expect((after[testCookie]! as Map)['value'], 'abc');
      for (final key in before.keys) {
        expect(
          (after[key]! as Map)['value'],
          (before[key]! as Map)['value'],
          reason: 'cookie "$key" value is preserved',
        );
      }
    });

    test(
      'should not corrupt cookies when the redirect has no cookie',
      () async {
        await client.signIn.email(email: 'test@test.com', password: 'password');
        final before = storedCookies(storage);
        expect(before['better-auth.session_token'], isNotNull);

        browser.next = (_) async => 'better-auth:///dashboard';
        await client.signIn.social(
          provider: 'google',
          callbackURL: '/dashboard',
        );

        final after = storedCookies(storage);
        expect(after['null'], isNull);
        expect(
          (after['better-auth.session_token']! as Map)['value'],
          (before['better-auth.session_token']! as Map)['value'],
        );
      },
    );

    test(
      'should not include oauthState with the database state strategy',
      () async {
        await client.signIn.social(
          provider: 'google',
          callbackURL: '/dashboard',
        );
        final proxyUrl = Uri.parse(browser.calls.last.url);
        expect(proxyUrl.path, contains('expo-authorization-proxy'));
        expect(
          proxyUrl.queryParameters['authorizationURL'],
          googleAuthorizationURL,
        );
        expect(proxyUrl.queryParameters.containsKey('oauthState'), isFalse);
      },
    );

    test('stores the redirect cookie and refreshes the session', () async {
      await client.signIn.social(provider: 'google', callbackURL: '/dashboard');
      final token = storedCookies(storage)['better-auth.session_token']! as Map;
      expect(
        token['value'],
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjYxMzQwZj',
      );
    });

    test('returns quietly when the user cancels the browser', () async {
      browser.next = (_) async => throw PlatformException(code: 'CANCELED');
      final (:data, :error) = await client.signIn.social(
        provider: 'google',
        callbackURL: '/dashboard',
      );
      expect(error, isNull);
      expect(data?.redirect, isTrue);
      expect(storage.map['better-auth_cookie'], isNull);
    });
  });

  group('expo with cookieCache', () {
    late FakeAuthServer server;
    late MemoryStorage storage;
    late AuthClient client;

    setUp(() {
      server = FakeAuthServer(cookieCache: true);
      storage = MemoryStorage();
      client = makeClient(server: server, storage: storage);
    });

    test('should store both cookies with expires dates', () async {
      await client.signIn.email(email: 'test@test.com', password: 'password');
      final cookies = storedCookies(storage);
      for (final name in <String>[
        'better-auth.session_token',
        'better-auth.session_data',
      ]) {
        expect((cookies[name]! as Map)['value'], isNotEmpty);
        expect((cookies[name]! as Map)['expires'], isA<String>());
      }
    });

    test('should refresh session_data without erasing session_token', () async {
      await client.signIn.email(email: 'test@test.com', password: 'password');
      final before = storedCookies(storage);
      server.rotateSessionData = true;
      final (:data, error: _) = await client.getSession();
      expect(data?.session.id, 'session-1');
      final after = storedCookies(storage);
      expect(
        (after['better-auth.session_token']! as Map)['value'],
        (before['better-auth.session_token']! as Map)['value'],
      );
      expect(
        (after['better-auth.session_data']! as Map)['value'],
        isNot((before['better-auth.session_data']! as Map)['value']),
      );
    });

    test(
      'should keep stored cookies when the server reports no session',
      () async {
        await client.signIn.email(email: 'test@test.com', password: 'password');
        server.sessionValid = false;
        final (:data, error: _) = await client.getSession();
        expect(data, isNull);
        final cookies = storedCookies(storage);
        expect(cookies['better-auth.session_token'], isNotNull);
        expect(cookies['better-auth.session_data'], isNotNull);
      },
    );

    test('should allow independent cookiePrefix configuration', () {
      const header = 'my-app.session_token=abc; Path=/';
      expect(hasBetterAuthCookies(header, const ['my-app']), isTrue);
      expect(hasBetterAuthCookies(header, const ['better-auth']), isFalse);
    });

    test('should support a list of cookie prefixes', () {
      const prefixes = <String>['better-auth', 'my-app'];
      expect(
        hasBetterAuthCookies('better-auth.session_token=abc; Path=/', prefixes),
        isTrue,
      );
      expect(
        hasBetterAuthCookies('my-app.session_data=xyz; Path=/', prefixes),
        isTrue,
      );
      expect(
        hasBetterAuthCookies('other-app.session_token=def; Path=/', prefixes),
        isFalse,
      );
      expect(
        hasBetterAuthCookies('better-auth-passkey=xyz; Path=/', prefixes),
        isTrue,
      );
      expect(
        hasBetterAuthCookies('my-app-passkey=xyz; Path=/', prefixes),
        isTrue,
      );
      expect(
        hasBetterAuthCookies(
          '__Secure-my-app.session_token=abc; Path=/',
          prefixes,
        ),
        isTrue,
      );
      expect(
        hasBetterAuthCookies('session_token=abc; Path=/', const []),
        isFalse,
      );
      expect(
        hasBetterAuthCookies('session_token=abc; Path=/', const ['']),
        isTrue,
      );
    });

    group('chunked storage consistency', () {
      test('should update a value without losing concurrent changes', () async {
        final backing = MemoryStorage();
        backing.onSet = (name, value) async {
          await Future<void>.delayed(Duration.zero);
          backing.map[name] = value;
        };
        final first = flutterClient(scheme: 'test', storage: backing);
        final second = flutterClient(scheme: 'test', storage: backing);

        await Future.wait(<Future<void>>[
          applyCookieResponse(first, 'better-auth.first=value; Path=/'),
          applyCookieResponse(second, 'better-auth.second=value; Path=/'),
        ]);

        final stored = await storageAdapter(
          backing,
        ).getItemAsync('better-auth_cookie');
        final parsed = jsonDecode(stored ?? '{}') as Map;
        expect((parsed['better-auth.first'] as Map)['value'], 'value');
        expect((parsed['better-auth.second'] as Map)['value'], 'value');
      });

      test('should not notify when a cookie update cannot be stored', () async {
        final previousValue = jsonEncode(<String, Object?>{
          'better-auth.session_token': <String, Object?>{
            'value': 'previous',
            'expires': null,
          },
        });
        final backing = MemoryStorage()
          ..onGet = ((_) async => previousValue)
          ..onSet = (_, _) async => throw StateError('keychain rejected write');
        final plugin = flutterClient(scheme: 'test', storage: backing);
        final signal = Atom<bool>(false);
        var notified = 0;
        signal.listen((_, _) => notified++);
        plugin.getActions(
          createFetch(),
          ClientStore(<String, Atom<Object?>>{r'$sessionSignal': signal}),
          null,
        );
        final logs = captureSevereLogs();

        await applyCookieResponse(
          plugin,
          'better-auth.session_token=next; Path=/',
        );
        expect(logs, hasLength(1));
        expect(notified, 0);
      });
    });
  });

  group('expo with cookie storeStateStrategy', () {
    test('should include the stored oauthState in the proxy URL', () async {
      final server = FakeAuthServer(cookieStateStrategy: true);
      final browser = FakeBrowser();
      final client = makeClient(
        server: server,
        storage: MemoryStorage(),
        browser: browser,
      );
      await client.signIn.social(provider: 'google', callbackURL: '/dashboard');
      final url = browser.calls.last.url;
      expect(url, contains('/expo-authorization-proxy'));
      expect(url, contains('authorizationURL='));
      expect(Uri.parse(url).queryParameters['oauthState'], 'oauth-state-value');
    });
  });

  group('expo secure storage availability', () {
    test(
      'rejects asynchronously when the secure store is unavailable',
      () async {
        final storageError = PlatformException(
          code: 'User interaction is not allowed',
        );
        final storage = MemoryStorage()
          ..onGet = (_) async => throw storageError;
        final client = makeClient(server: FakeAuthServer(), storage: storage);

        expect(storage.getCalls, isEmpty);
        await expectLater(client.getSession(), throwsA(same(storageError)));
        expect(storage.getCalls, isNotEmpty);
      },
    );
  });

  group('expo session cache hydration', () {
    test('shares cold-start hydration without restoring stale data', () async {
      final sessionCacheRead = Completer<String?>();
      final storage = MemoryStorage();
      storage.onGet = (key) {
        if (key == 'better-auth_session_data') return sessionCacheRead.future;
        return Future<String?>.value(storage.map[key]);
      };
      final client = makeClient(server: FakeAuthServer(), storage: storage);

      final firstRequest = client.getSession();
      final secondRequest = client.getSession();
      while (!storage.getCalls.contains('better-auth_session_data')) {
        await Future<void>.delayed(Duration.zero);
      }

      final sessionAtom = client.useSession;
      final serverSession = SessionData(<String, Object?>{
        'user': <String, Object?>{
          'id': 'server-user',
          'email': 'server@example.com',
        },
        'session': <String, Object?>{
          'id': 'server-session',
          'expiresAt': DateTime.now().add(const Duration(minutes: 1)),
        },
      });
      final current = sessionAtom.get();
      sessionAtom.set(
        AuthQueryState<SessionData>(
          data: serverSession,
          error: null,
          isPending: current.isPending,
          isRefetching: current.isRefetching,
          refetch: current.refetch,
        ),
      );
      sessionCacheRead.complete(
        jsonEncode(<String, Object?>{
          'user': <String, Object?>{'id': 'cached-user'},
          'session': <String, Object?>{
            'id': 'cached-session',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
        }),
      );
      await Future.wait(<Future<Object?>>[firstRequest, secondRequest]);

      final reads = storage.getCalls.where(
        (k) => k == 'better-auth_session_data',
      );
      final writes = storage.setCalls.where(
        (c) => c.$1 == 'better-auth_session_data',
      );
      expect(sessionAtom.get().data?.json, same(serverSession.json));
      expect(reads.length, writes.length + 1);
    });

    test('preserves additional fields through the cache round-trip', () async {
      final server = FakeAuthServer(
        userFields: const <String, Object?>{'favoriteColor': 'blue'},
        sessionFields: const <String, Object?>{'deviceLabel': 'test-device'},
      );
      final storage = MemoryStorage();
      final writer = makeClient(server: server, storage: storage);
      await writer.signIn.email(email: 'test@test.com', password: 'password');
      await writer.getSession();

      final coldStart = makeClient(server: server, storage: storage);
      storage.getCalls.clear();
      await coldStart.getSession();
      expect(storage.getCalls, contains('better-auth_session_data'));
      final data = coldStart.useSession.get().data;
      expect(data?.user['favoriteColor'], 'blue');
      expect(data?.session['deviceLabel'], 'test-device');

      storage
        ..getCalls.clear()
        ..setCalls.clear();
      await coldStart.getSession();
      final reads = storage.getCalls.where(
        (k) => k == 'better-auth_session_data',
      );
      final writes = storage.setCalls.where(
        (c) => c.$1 == 'better-auth_session_data',
      );
      expect(reads.length, writes.length);
    });

    for (final (label, expiresAt) in <(String, String?)>[
      (
        'expired',
        DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      ),
      ('missing', null),
      ('invalid', 'not-a-date'),
    ]) {
      test('does not hydrate when session.expiresAt is $label', () async {
        final storage = MemoryStorage({
          'better-auth_session_data': jsonEncode(<String, Object?>{
            'user': <String, Object?>{'id': 'u1'},
            'session': <String, Object?>{'id': 's1', 'expiresAt': ?expiresAt},
          }),
        });
        final client = makeClient(server: FakeAuthServer(), storage: storage);
        await client.getSession();
        expect(client.useSession.get().data, isNull);
      });
    }

    test('does not hydrate when disableCache is set', () async {
      final storage = MemoryStorage({
        'better-auth_session_data': jsonEncode(<String, Object?>{
          'user': <String, Object?>{'id': 'u1'},
          'session': <String, Object?>{
            'id': 's1',
            'expiresAt': DateTime.now()
                .toUtc()
                .add(const Duration(minutes: 1))
                .toIso8601String(),
          },
        }),
      });
      final client = makeClient(
        server: FakeAuthServer(),
        storage: storage,
        disableCache: true,
      );
      await client.getSession();
      expect(storage.getCalls, isNot(contains('better-auth_session_data')));
      expect(client.useSession.get().data, isNull);
    });
  });

  test('FlutterFocusManager does not notify an unchanged value', () {
    final focusManager = setupFlutterFocusManager();
    var calls = 0;
    focusManager
      ..subscribe((_) => calls++)
      ..setFocused(true);
    expect(calls, 1);
    focusManager.setFocused(true);
    expect(calls, 1);
    focusManager.setFocused(false);
    expect(calls, 2);
    focusManager.setFocused(false);
    expect(calls, 2);
  });

  test('FlutterOnlineManager does not notify an unchanged value', () {
    final onlineManager = setupFlutterOnlineManager();
    var calls = 0;
    onlineManager
      ..subscribe((_) => calls++)
      ..setOnline(false);
    expect(calls, 1);
    onlineManager.setOnline(false);
    expect(calls, 1);
    onlineManager.setOnline(true);
    expect(calls, 2);
    onlineManager.setOnline(true);
    expect(calls, 2);
  });

  test('FlutterOnlineManager follows connectivity changes', () async {
    final changes = StreamController<List<ConnectivityResult>>();
    addTearDown(changes.close);
    final manager = FlutterOnlineManager(
      connectivityChanges: () => changes.stream,
    );
    final teardown = manager.setup();
    changes.add(<ConnectivityResult>[ConnectivityResult.none]);
    await settle();
    expect(manager.isOnline, isFalse);
    changes.add(<ConnectivityResult>[ConnectivityResult.wifi]);
    await settle();
    expect(manager.isOnline, isTrue);
    teardown();
  });

  test('flutterClient requires a scheme', () {
    expect(
      () => flutterClient(scheme: '', storage: MemoryStorage()),
      throwsArgumentError,
    );
  });

  test('createURL builds deep links like expo-linking', () {
    expect(createURL('', 'myapp'), 'myapp://');
    expect(createURL('/dashboard', 'myapp'), 'myapp:///dashboard');
  });
}
