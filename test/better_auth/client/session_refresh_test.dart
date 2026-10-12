import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/src/better_auth/client/session_refresh.dart';
import 'package:re_better_auth/vanilla.dart';

import '../../support/fakes.dart';

void main() {
  late int calls;
  Future<void> mockFetchSession() async => calls++;

  setUp(() {
    resetGlobals();
    calls = 0;
    getGlobalOnlineManager().setOnline(true);
  });
  tearDown(resetGlobals);

  group('session-refresh', () {
    test('should call fetchSession when refetchInterval fires', () {
      fakeAsync((async) {
        final manager = createSessionRefreshManager(
          fetchSession: mockFetchSession,
          sessionSignal: Atom<bool>(false),
          options: const BetterAuthClientOptions(
            sessionOptions: RevalidateOptions(
              refetchInterval: Duration(seconds: 5),
            ),
          ),
        )..init();
        expect(calls, 0);

        async.elapse(const Duration(seconds: 5));
        expect(calls, 1);
        async.elapse(const Duration(seconds: 5));
        expect(calls, 2);

        manager.cleanup();
      });
    });

    test('should not poll when shouldPollSession returns false', () {
      fakeAsync((async) {
        final manager = createSessionRefreshManager(
          fetchSession: mockFetchSession,
          shouldPollSession: () => false,
          sessionSignal: Atom<bool>(false),
          options: const BetterAuthClientOptions(
            sessionOptions: RevalidateOptions(
              refetchInterval: Duration(seconds: 5),
            ),
          ),
        )..init();
        async.elapse(const Duration(seconds: 5));
        expect(calls, 0);
        manager.cleanup();
      });
    });

    test('should rate limit focus refetch after a recent request', () {
      fakeAsync((async) {
        final manager =
            createSessionRefreshManager(
                fetchSession: mockFetchSession,
                sessionSignal: Atom<bool>(false),
                options: const BetterAuthClientOptions(
                  sessionOptions: RevalidateOptions(refetchOnWindowFocus: true),
                ),
              )
              ..init()
              ..triggerRefetch(RefetchEvent.poll);
        expect(calls, 1);

        manager.triggerRefetch(RefetchEvent.visibilitychange);
        expect(calls, 1);
        manager.cleanup();
      });
    });

    test('should allow focus refetch after the rate limit window', () {
      fakeAsync((async) {
        final manager =
            createSessionRefreshManager(
                fetchSession: mockFetchSession,
                sessionSignal: Atom<bool>(false),
                options: const BetterAuthClientOptions(
                  sessionOptions: RevalidateOptions(refetchOnWindowFocus: true),
                ),
              )
              ..init()
              ..triggerRefetch(RefetchEvent.poll);
        expect(calls, 1);

        async.elapse(const Duration(seconds: 6));
        manager.triggerRefetch(RefetchEvent.visibilitychange);
        expect(calls, 2);
        manager.cleanup();
      });
    });

    test('should rate limit focus even after a visibilitychange fetch', () {
      fakeAsync((async) {
        final manager =
            createSessionRefreshManager(
                fetchSession: mockFetchSession,
                sessionSignal: Atom<bool>(false),
                options: const BetterAuthClientOptions(
                  sessionOptions: RevalidateOptions(refetchOnWindowFocus: true),
                ),
              )
              ..init()
              ..triggerRefetch(RefetchEvent.visibilitychange);
        expect(calls, 1);

        manager.triggerRefetch(RefetchEvent.visibilitychange);
        expect(calls, 1);
        manager.cleanup();
      });
    });

    test('should not refetch when offline unless refetchWhenOffline', () {
      final onlineManager = getGlobalOnlineManager()
        ..setOnline(true)
        ..setOnline(false);
      final manager = createSessionRefreshManager(
        fetchSession: mockFetchSession,
        sessionSignal: Atom<bool>(false),
        options: const BetterAuthClientOptions(
          sessionOptions: RevalidateOptions(refetchWhenOffline: false),
        ),
      );
      expect(onlineManager.isOnline, isFalse);

      manager
        ..triggerRefetch(RefetchEvent.visibilitychange)
        ..cleanup();
      expect(calls, 0);
      onlineManager.setOnline(true);
    });

    test('should call fetchSession for storage events', () {
      final manager =
          createSessionRefreshManager(
              fetchSession: mockFetchSession,
              sessionSignal: Atom<bool>(false),
            )
            ..init()
            ..triggerRefetch(RefetchEvent.storage);
      expect(calls, 1);
      manager.cleanup();
    });

    test('should call fetchSession when \$sessionSignal is flipped', () {
      fakeAsync((async) {
        final sessionSignal = Atom<bool>(false);
        final manager = createSessionRefreshManager(
          fetchSession: mockFetchSession,
          sessionSignal: sessionSignal,
        )..init();
        sessionSignal.set(!sessionSignal.get());
        async.flushTimers();
        expect(calls, 1);
        manager.cleanup();
      });
    });

    test('should refetch on \$sessionSignal even when offline', () {
      fakeAsync((async) {
        getGlobalOnlineManager().setOnline(false);
        final sessionSignal = Atom<bool>(false);
        final manager = createSessionRefreshManager(
          fetchSession: mockFetchSession,
          sessionSignal: sessionSignal,
          options: const BetterAuthClientOptions(
            sessionOptions: RevalidateOptions(refetchWhenOffline: false),
          ),
        )..init();
        sessionSignal.set(!sessionSignal.get());
        async.flushTimers();
        expect(calls, 1);
        manager.cleanup();
      });
    });

    for (final trigger in <String>['signout', 'updateUser']) {
      test('should broadcast session update with $trigger', () {
        final channel = FakeBroadcastChannel();
        globalBroadcastChannel = channel;
        final manager =
            createSessionRefreshManager(
                fetchSession: mockFetchSession,
                sessionSignal: Atom<bool>(false),
              )
              ..init()
              ..broadcastSessionUpdate(trigger);
        expect(channel.posts.single.event, 'session');
        expect(channel.posts.single.trigger, trigger);
        manager.cleanup();
      });
    }

    test('should clean up all subscriptions', () {
      fakeAsync((async) {
        final sessionSignal = Atom<bool>(false);
        createSessionRefreshManager(
            fetchSession: mockFetchSession,
            sessionSignal: sessionSignal,
            options: const BetterAuthClientOptions(
              sessionOptions: RevalidateOptions(
                refetchInterval: Duration(seconds: 5),
                refetchOnWindowFocus: true,
              ),
            ),
          )
          ..init()
          ..cleanup();
        sessionSignal.set(!sessionSignal.get());
        async.elapse(const Duration(seconds: 10));
        expect(calls, 0);
      });
    });

    test('should remove global setup listeners on cleanup', () {
      final channel = FakeBroadcastChannel();
      globalBroadcastChannel = channel;
      final sessionSignal = Atom<bool>(false);
      createSessionRefreshManager(
          fetchSession: mockFetchSession,
          sessionSignal: sessionSignal,
        )
        ..init()
        ..cleanup();
      final secondManager = createSessionRefreshManager(
        fetchSession: mockFetchSession,
        sessionSignal: sessionSignal,
      )..init();

      channel.deliver(
        const BroadcastMessage(
          event: 'session',
          trigger: 'getSession',
          clientId: 'test-client',
          timestamp: 1,
        ),
      );
      expect(calls, 1);
      secondManager.cleanup();
    });
  });
}
