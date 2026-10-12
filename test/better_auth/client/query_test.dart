import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/src/better_auth/client/session_atom.dart';
import 'package:re_better_auth/vanilla.dart';

import '../../support/fakes.dart';
import '../../support/test_plugin.dart';

const String _base = 'http://localhost:3000';

Map<String, Object?> _sessionPayload() => <String, Object?>{
  'user': <String, Object?>{'id': '1', 'email': 'test@test.com'},
  'session': <String, Object?>{'id': 'session-1'},
};

FetchResponse _nullSession() =>
    jsonResponse(<String, Object?>{'session': null, 'user': null});

AuthClient _client(FakeHandler handler, {RevalidateOptions? sessionOptions}) =>
    createAuthClient(
      plugins: [TestClientPlugin()],
      sessionOptions: sessionOptions,
      fetchOptions: ClientFetchOption(
        baseURL: _base,
        customFetchImpl: FakeFetch(handler).call,
      ),
    );

BetterFetch _fetch(FakeFetch fake) =>
    createFetch(BetterFetchOption(baseURL: _base, customFetchImpl: fake.call));

void main() {
  setUp(resetGlobals);
  tearDown(resetGlobals);

  group('useAuthQuery - error handling', () {
    test('should preserve stale data on network error', () {
      fakeAsync((async) {
        var shouldFail = false;
        final client = _client((_) {
          if (shouldFail) throw StateError('Failed to fetch');
          return jsonResponse(_sessionPayload());
        });
        final session = client.useSession..listen((_, _) {});
        async.flushTimers();
        expect(session.value.data?.user.email, 'test@test.com');
        expect(session.value.error, isNull);

        shouldFail = true;
        session.value.refetch().ignore();
        async.flushTimers();
        expect(session.value.data?.user.email, 'test@test.com');
        expect(session.value.error?.status, 0);
      });
    });

    test('should clear data on 401 unauthorized response', () {
      fakeAsync((async) {
        var returnUnauthorized = false;
        final client = _client((request) {
          if (returnUnauthorized && request.uri.path.contains('/get-session')) {
            return jsonResponse(<String, Object?>{
              'message': 'Unauthorized',
            }, status: 401);
          }
          return jsonResponse(_sessionPayload());
        });
        final session = client.useSession..listen((_, _) {});
        async.flushTimers();
        expect(session.value.data?.user.id, '1');

        returnUnauthorized = true;
        session.value.refetch().ignore();
        async.flushTimers();
        expect(session.value.data, isNull);
      });
    });

    for (final (earlier, initialOutcome, refreshed, expected)
        in <(String, Object Function(), FetchResponse Function(), Object?)>[
          (
            'unauthorized',
            () => jsonResponse(<String, Object?>{
              'message': 'Unauthorized',
            }, status: 401),
            () => jsonResponse(<String, Object?>{'id': 'current'}),
            <String, Object?>{'id': 'current'},
          ),
          (
            'successful',
            () => jsonResponse(<String, Object?>{'id': 'previous'}),
            () => jsonResponse(<String, Object?>{
              'message': 'Unauthorized',
            }, status: 401),
            null,
          ),
          (
            'network failure',
            () => StateError('Failed to fetch'),
            () => jsonResponse(<String, Object?>{'id': 'current'}),
            <String, Object?>{'id': 'current'},
          ),
        ]) {
      test('keeps the latest result when an earlier $earlier request '
          'finishes last', () {
        fakeAsync((async) {
          final initialRequest = Completer<FetchResponse>();
          var calls = 0;
          final fake = FakeFetch((_) {
            calls++;
            return calls == 1 ? initialRequest.future : refreshed();
          });
          final $signal = Atom<bool>(false);
          final query = useAuthQuery<Object?>(
            <Atom<Object?>>[$signal],
            '/test',
            _fetch(fake),
            options: ClientFetchOption(method: 'GET'),
          );
          final unsubscribe = query.listen((_, _) {});
          async.elapse(Duration.zero);
          expect(calls, 1);

          $signal.set(true);
          async.elapse(Duration.zero);
          expect(calls, 2);
          expect(query.get().data, expected);
          final latestState = query.get();

          final outcome = initialOutcome();
          if (outcome is FetchResponse) {
            initialRequest.complete(outcome);
          } else {
            initialRequest.completeError(outcome);
          }
          async.elapse(Duration.zero);
          expect(query.get(), same(latestState));
          unsubscribe();
        });
      });
    }

    test('runs fetch callbacks for superseded requests', () {
      fakeAsync((async) {
        final initialRequest = Completer<FetchResponse>();
        var calls = 0;
        final fake = FakeFetch((_) {
          calls++;
          return calls == 1
              ? initialRequest.future
              : jsonResponse(<String, Object?>{'id': 'current'});
        });
        var onSuccess = 0;
        var onError = 0;
        final query = useAuthQuery<Object?>(
          <Atom<Object?>>[Atom<bool>(false)],
          '/test',
          _fetch(fake),
          options: ClientFetchOption(
            method: 'GET',
            onSuccess: (_) => onSuccess++,
            onError: (_) => onError++,
          ),
        );
        final unsubscribe = query.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(calls, 1);

        query.get().refetch().ignore();
        async.flushMicrotasks();
        initialRequest.complete(
          jsonResponse(<String, Object?>{
            'message': 'Unauthorized',
          }, status: 401),
        );
        async.elapse(Duration.zero);
        expect(onSuccess, 1);
        expect(onError, 1);
        unsubscribe();
      });
    });

    test('should normalize null session responses to null data', () {
      fakeAsync((async) {
        final session = _client((_) => _nullSession()).useSession
          ..listen((_, _) {});
        async.flushTimers();
        expect(session.value.data, isNull);
      });
    });

    test('should preserve non-null session responses without a session', () {
      fakeAsync((async) {
        final session = _client(
          (_) => jsonResponse(<String, Object?>{
            'user': <String, Object?>{'id': '1', 'email': 'test@test.com'},
          }),
        ).useSession..listen((_, _) {});
        async.flushTimers();
        expect(session.value.data?.user.email, 'test@test.com');
      });
    });

    test('should defer remount refetch until the initial fetch resolves', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final initialFetch = Completer<FetchResponse>();
        final fake = FakeFetch((_) {
          fetchCount++;
          if (fetchCount == 1) return initialFetch.future;
          return jsonResponse(<String, Object?>{'data': 'fresh'});
        });
        final $signal = Atom<bool>(false);
        final queryAtom = useAuthQuery<Object?>(
          <Atom<Object?>>[$signal],
          '/test',
          _fetch(fake),
          options: ClientFetchOption(method: 'GET'),
        );

        final unsubscribe1 = queryAtom.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(fetchCount, 1);

        unsubscribe1();
        async.elapse(storeUnmountDelay);

        final unsubscribe2 = queryAtom.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(fetchCount, 1);

        initialFetch.complete(jsonResponse(<String, Object?>{'data': 'stale'}));
        async.flushTimers();
        expect(fetchCount, 2);
        unsubscribe2();
      });
    });

    test('should revalidate and restore signal listeners after remount', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final fake = FakeFetch((_) {
          fetchCount++;
          return jsonResponse(<String, Object?>{'data': 'request-$fetchCount'});
        });
        final $signal = Atom<bool>(false);
        final queryAtom = useAuthQuery<Object?>(
          <Atom<Object?>>[$signal],
          '/test',
          _fetch(fake),
          options: ClientFetchOption(method: 'GET'),
        );

        final unsubscribe1 = queryAtom.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(fetchCount, 1);
        expect(queryAtom.get().data, {'data': 'request-1'});

        unsubscribe1();
        async.elapse(storeUnmountDelay);

        $signal.set(true);
        async.flushTimers();
        expect(fetchCount, 1);

        final unsubscribe2 = queryAtom.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(fetchCount, 2);
        expect(queryAtom.get().data, {'data': 'request-2'});

        $signal.set(false);
        async.flushTimers();
        expect(fetchCount, 3);
        expect(queryAtom.get().data, {'data': 'request-3'});
        unsubscribe2();
      });
    });

    test('should fire one initial fetch when signals change around mount', () {
      fakeAsync((async) {
        var fetchCount = 0;
        final fake = FakeFetch((_) {
          fetchCount++;
          return Completer<FetchResponse>().future;
        });
        final $signal = Atom<bool>(false);
        final queryAtom = useAuthQuery<Object?>(
          <Atom<Object?>>[$signal],
          '/test',
          _fetch(fake),
          options: ClientFetchOption(method: 'GET'),
        );

        $signal
          ..set(true)
          ..set(false)
          ..set(true);
        final unsubscribe = queryAtom.listen((_, _) {});
        $signal.set(false);
        async.elapse(Duration.zero);
        expect(fetchCount, 1);
        unsubscribe();
      });
    });

    test('should clean up the equality gate when the query unmounts', () {
      fakeAsync((async) {
        final fake = FakeFetch((_) => Completer<FetchResponse>().future);
        final queryAtom = useAuthQuery<Object?>(
          <Atom<Object?>>[Atom<bool>(false)],
          '/test',
          _fetch(fake),
          options: ClientFetchOption(method: 'GET'),
        );
        final unsubscribe = queryAtom.listen((_, _) {});
        async.elapse(Duration.zero);
        final previous = queryAtom.get();

        unsubscribe();
        async.elapse(storeUnmountDelay);

        final equalState = AuthQueryState<Object?>(
          data: previous.data,
          error: previous.error,
          isPending: previous.isPending,
          isRefetching: previous.isRefetching,
          refetch: previous.refetch,
        );
        queryAtom.set(equalState);
        expect(queryAtom.get(), same(equalState));
      });
    });

    test('should preserve stale data on 500 server error', () {
      fakeAsync((async) {
        var returnServerError = false;
        final session = _client((request) {
          if (returnServerError && request.uri.path.contains('/get-session')) {
            return jsonResponse(<String, Object?>{
              'message': 'Internal Server Error',
            }, status: 500);
          }
          return jsonResponse(_sessionPayload());
        }).useSession..listen((_, _) {});
        async.flushTimers();
        expect(session.value.data?.user.id, '1');

        returnServerError = true;
        session.value.refetch().ignore();
        async.flushTimers();
        expect(session.value.data?.user.id, '1');
      });
    });

    test('should keep the data reference when refetch returns the same', () {
      fakeAsync((async) {
        final session = _client(
          (_) => jsonResponse(_sessionPayload()),
        ).useSession..listen((_, _) {});
        async.flushTimers();
        final initialData = session.value.data;
        expect(initialData, isNotNull);

        session.value.refetch().ignore();
        async.flushTimers();
        expect(session.value.data?.json, same(initialData?.json));
      });
    });

    test('should allow an unmounted session request to settle', () {
      fakeAsync((async) {
        final pending = Completer<FetchResponse>();
        final fake = FakeFetch((_) => pending.future);
        final session = getSessionAtom(_fetch(fake)).session;

        final unsubscribe = session.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(session.get().isPending, isTrue);
        expect(session.get().isRefetching, isTrue);

        unsubscribe();
        async.elapse(storeUnmountDelay);
        expect(fake.requests.single.signal.isCancelled, isFalse);
        expect(session.value.isPending, isTrue);
        expect(session.value.isRefetching, isTrue);

        pending.complete(_nullSession());
        async.flushTimers();
        expect(session.value.isPending, isFalse);
        expect(session.value.isRefetching, isFalse);
      });
    });

    test('should cancel a session request superseded by refetch', () {
      fakeAsync((async) {
        final pending = <Completer<FetchResponse>>[];
        final fake = FakeFetch((_) {
          final completer = Completer<FetchResponse>();
          pending.add(completer);
          return completer.future;
        });
        final session = getSessionAtom(_fetch(fake)).session;
        final unsubscribe = session.listen((_, _) {});
        async.elapse(Duration.zero);

        var refetched = false;
        session.value.refetch().then((_) => refetched = true).ignore();
        async.elapse(Duration.zero);
        expect(fake.requests, hasLength(2));
        expect(fake.requests[0].signal.isCancelled, isTrue);
        expect(fake.requests[1].signal.isCancelled, isFalse);

        for (final completer in pending) {
          completer.complete(_nullSession());
        }
        async.flushMicrotasks();
        expect(refetched, isTrue);
        unsubscribe();
      });
    });

    test('should let a listener refetch supersede the current request', () {
      fakeAsync((async) {
        final pending = <Completer<FetchResponse>>[];
        final fake = FakeFetch((_) {
          final completer = Completer<FetchResponse>();
          pending.add(completer);
          return completer.future;
        });
        final session = getSessionAtom(_fetch(fake)).session;
        Future<void>? refetch;
        final unsubscribe = session.listen((current, _) {
          if (current.isRefetching && refetch == null) {
            refetch = current.refetch();
          }
        });
        async.elapse(Duration.zero);
        expect(fake.requests, hasLength(1));
        expect(fake.requests[0].signal.isCancelled, isFalse);

        pending[0].complete(_nullSession());
        async.flushMicrotasks();
        expect(refetch, isNotNull);
        var done = false;
        refetch!.then((_) => done = true).ignore();
        async.flushTimers();
        for (final completer in pending.skip(1)) {
          completer.complete(_nullSession());
        }
        async.flushTimers();
        expect(done, isTrue);
        unsubscribe();
      });
    });

    test('should revalidate a settled session request on remount', () {
      fakeAsync((async) {
        final fake = FakeFetch((_) => _nullSession());
        final session = getSessionAtom(_fetch(fake)).session;

        final unsubscribeFirst = session.listen((_, _) {});
        async.flushTimers();
        expect(fake.requests, hasLength(1));

        unsubscribeFirst();
        async.elapse(storeUnmountDelay);
        final unsubscribeSecond = session.listen((_, _) {});
        async.flushTimers();
        expect(fake.requests, hasLength(2));
        unsubscribeSecond();
      });
    });

    test(
      'should reuse the in-flight initial request after a quick remount',
      () {
        fakeAsync((async) {
          final pending = Completer<FetchResponse>();
          final fake = FakeFetch((_) => pending.future);
          final session = getSessionAtom(_fetch(fake)).session;

          final first = session.listen((_, _) {});
          async.elapse(Duration.zero);
          first();
          async.elapse(storeUnmountDelay);

          final second = session.listen((_, _) {});
          async.elapse(Duration.zero);
          expect(fake.requests, hasLength(1));
          expect(fake.requests.single.signal.isCancelled, isFalse);

          pending.complete(_nullSession());
          async.flushMicrotasks();
          second();
        });
      },
    );

    test('should not refetch a just-settled request on remount', () {
      fakeAsync((async) {
        final pending = Completer<FetchResponse>();
        var requestCount = 0;
        final fake = FakeFetch((_) {
          requestCount++;
          return requestCount > 1 ? _nullSession() : pending.future;
        });
        final session = getSessionAtom(_fetch(fake)).session;

        final first = session.listen((_, _) {});
        async.elapse(Duration.zero);
        first();
        async.elapse(storeUnmountDelay);

        pending.complete(_nullSession());
        async.flushMicrotasks();
        expect(session.value.isPending, isFalse);

        final second = session.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(requestCount, 1);
        second();
      });
    });

    test('should retry a failed session request on remount', () {
      fakeAsync((async) {
        final pending = Completer<FetchResponse>();
        var fetchCount = 0;
        final fake = FakeFetch((_) {
          fetchCount++;
          return fetchCount > 1 ? _nullSession() : pending.future;
        });
        final session = getSessionAtom(_fetch(fake)).session;

        final first = session.listen((_, _) {});
        async.elapse(Duration.zero);
        first();
        async.elapse(storeUnmountDelay);

        pending.complete(
          jsonResponse(<String, Object?>{
            'message': 'Internal Server Error',
          }, status: 500),
        );
        async.flushMicrotasks();

        final second = session.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(fetchCount, 2);
        second();
      });
    });

    test('should retry an incomplete session refresh on remount', () {
      fakeAsync((async) {
        final methods = <String>[];
        final pending = Completer<FetchResponse>();
        final fake = FakeFetch((request) {
          methods.add(request.method);
          if (methods.length == 1) return pending.future;
          if (request.method == 'POST') {
            throw StateError('Session refresh failed');
          }
          return _nullSession();
        });
        final session = getSessionAtom(_fetch(fake)).session;

        final first = session.listen((_, _) {});
        async.elapse(Duration.zero);
        first();
        async.elapse(storeUnmountDelay);

        pending.complete(
          jsonResponse(<String, Object?>{
            'needsRefresh': true,
            'session': <String, Object?>{
              'id': 'session-1',
              'expiresAt': DateTime.now()
                  .add(const Duration(minutes: 1))
                  .toUtc()
                  .toIso8601String(),
            },
            'user': <String, Object?>{'id': 'user-1'},
          }),
        );
        async.elapse(Duration.zero);
        expect(session.value.data?.session.id, 'session-1');

        final second = session.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(methods, ['GET', 'POST', 'GET']);
        second();
      });
    });

    test('should revalidate after the session signal changes', () {
      fakeAsync((async) {
        final pending = Completer<FetchResponse>();
        var fetchCount = 0;
        final fake = FakeFetch((_) {
          fetchCount++;
          return fetchCount > 1 ? _nullSession() : pending.future;
        });
        final bundle = getSessionAtom(_fetch(fake));
        final session = bundle.session;

        final first = session.listen((_, _) {});
        async.elapse(Duration.zero);
        first();
        async.elapse(storeUnmountDelay);

        pending.complete(_nullSession());
        async.flushMicrotasks();
        bundle.$sessionSignal.set(!bundle.$sessionSignal.get());

        final second = session.listen((_, _) {});
        async.elapse(Duration.zero);
        expect(fetchCount, 2);
        second();
      });
    });

    test('should avoid an extra post-focus fetch for an unchanged payload', () {
      fakeAsync((async) {
        var fetchCallCount = 0;
        final client = _client((_) {
          fetchCallCount++;
          return jsonResponse(_sessionPayload());
        }, sessionOptions: const RevalidateOptions(refetchOnWindowFocus: true));

        final session = client.useSession..listen((_, _) {});
        async.flushTimers();
        final initialData = session.value.data;
        expect(fetchCallCount, 1);

        getGlobalFocusManager().setFocused(true);
        async.flushTimers();
        expect(fetchCallCount, 2);
        expect(session.value.data?.json, same(initialData?.json));
      });
    });
  });
}
