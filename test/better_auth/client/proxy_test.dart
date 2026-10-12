import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/src/better_auth/client/config.dart';
import 'package:re_better_auth/src/better_auth/client/proxy.dart';
import 'package:re_better_auth/vanilla.dart';

import '../../support/fakes.dart';

/// Signals once for auth paths and organization paths, like `organizationClient`.
class _OrgSignalPlugin extends BetterAuthClientPlugin {
  final Atom<bool> $activeOrgSignal = Atom<bool>(false);

  @override
  String get id => 'organization';

  @override
  Map<String, Atom<Object?>> getAtoms(BetterFetch $fetch) =>
      <String, Atom<Object?>>{r'$activeOrgSignal': $activeOrgSignal};

  @override
  List<ClientAtomListener> get atomListeners => <ClientAtomListener>[
    ClientAtomListener(
      matcher: (path) => path.startsWith('/organization'),
      signal: r'$activeOrgSignal',
    ),
    ClientAtomListener(
      matcher: (path) =>
          path.startsWith('/sign-in') || path.startsWith('/sign-up'),
      signal: r'$activeOrgSignal',
    ),
  ];
}

void main() {
  setUp(resetGlobals);

  group('createDynamicPathProxy', () {
    test('default atomListeners matcher covers session-rotating endpoints', () {
      final matcher = getClientConfig().atomListeners.first.matcher;
      for (final path in <String>[
        '/sign-in/email',
        '/sign-up/email',
        '/sign-out',
        '/change-email',
        '/revoke-session',
        '/revoke-sessions',
        '/change-password',
        '/revoke-other-sessions',
      ]) {
        expect(matcher(path), isTrue, reason: path);
      }
      expect(matcher('/get-session'), isFalse);
      expect(matcher('/list-sessions'), isFalse);
    });

    test('triggers \$sessionSignal on /change-password', () {
      fakeAsync((async) {
        final signal = Atom<bool>(false);
        var sets = 0;
        signal.listen((_, _) => sets++);
        final client = createFetch(
          BetterFetchOption(
            customFetchImpl: FakeFetch(
              (_) => jsonResponse(<String, Object?>{}),
            ).call,
          ),
        );
        callDynamicPath<Object?>(
          '/change-password',
          client: client,
          knownPathMethods: const <String, String>{'/change-password': 'POST'},
          atoms: <String, Atom<Object?>>{r'$sessionSignal': signal},
          atomListeners: getClientConfig().atomListeners,
          body: <String, Object?>{
            'currentPassword': 'old',
            'newPassword': 'new',
            'revokeOtherSessions': true,
          },
        ).ignore();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        expect(sets, 1);
      });
    });

    test('should avoid duplicate signal processing', () {
      fakeAsync((async) {
        final signal = Atom<bool>(false);
        var sets = 0;
        signal.listen((_, _) => sets++);
        final client = createFetch(
          BetterFetchOption(
            customFetchImpl: FakeFetch(
              (_) => jsonResponse(<String, Object?>{}),
            ).call,
          ),
        );
        final listeners = <ClientAtomListener>[
          ClientAtomListener(
            matcher: (path) => path == '/test',
            signal: 'testSignal',
          ),
          ClientAtomListener(
            matcher: (path) => path == '/test',
            signal: 'testSignal',
          ),
        ];
        callDynamicPath<Object?>(
          '/test',
          client: client,
          knownPathMethods: const <String, String>{'/test': 'POST'},
          atoms: <String, Atom<Object?>>{'testSignal': signal},
          atomListeners: listeners,
        ).ignore();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        expect(sets, 1);
      });
    });

    test(
      'refreshes the organization signal once per auth or org path',
      () async {
        final plugin = _OrgSignalPlugin();
        final client = createAuthClient(
          baseURL: 'http://localhost:3000',
          plugins: [plugin],
          fetchOptions: ClientFetchOption(
            customFetchImpl: FakeFetch(
              (_) => jsonResponse(<String, Object?>{}),
            ).call,
          ),
        );
        var updates = 0;
        plugin.$activeOrgSignal.listen((_, _) => updates++);

        await client<Object?>(
          '/sign-in/email',
          body: <String, Object?>{'a': 1},
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(updates, 1);

        await client<Object?>(
          '/sign-up/email',
          body: <String, Object?>{'a': 1},
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(updates, 2);

        await client<Object?>(
          '/organization/set-active',
          body: <String, Object?>{'organizationId': 'o'},
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(updates, 3);
      },
    );

    test('disableSignal skips the signal flip', () {
      fakeAsync((async) {
        final signal = Atom<bool>(false);
        var sets = 0;
        signal.listen((_, _) => sets++);
        final client = createFetch(
          BetterFetchOption(
            customFetchImpl: FakeFetch(
              (_) => jsonResponse(<String, Object?>{}),
            ).call,
          ),
        );
        callDynamicPath<Object?>(
          '/sign-out',
          client: client,
          knownPathMethods: const <String, String>{'/sign-out': 'POST'},
          atoms: <String, Atom<Object?>>{r'$sessionSignal': signal},
          atomListeners: getClientConfig().atomListeners,
          fetchOptions: ClientFetchOption(disableSignal: true),
        ).ignore();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 20));
        expect(sets, 0);
      });
    });
  });

  group('getMethod', () {
    test('uses forced path methods, then fetchOptions, then the body', () {
      expect(getMethod('/sign-out', const {'/sign-out': 'POST'}), 'POST');
      expect(
        getMethod(
          '/x',
          const {},
          fetchOptions: ClientFetchOption(method: 'PUT'),
        ),
        'PUT',
      );
      expect(
        getMethod('/x', const {}, body: <String, Object?>{'a': 1}),
        'POST',
      );
      expect(getMethod('/x', const {}, body: <String, Object?>{}), 'GET');
    });
  });
}
