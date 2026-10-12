import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

import '../../support/fakes.dart';

void main() {
  setUp(resetGlobals);
  tearDown(resetGlobals);

  group('AtomListenable', () {
    test('notifies on new values and stops after the last listener', () {
      final atom = Atom<int>(1);
      final listenable = AtomListenable<int>(atom);
      var calls = 0;
      void listener() => calls++;

      listenable.addListener(listener);
      atom.set(2);
      expect(calls, 1);
      expect(listenable.value, 2);

      listenable.removeListener(listener);
      atom.set(3);
      expect(calls, 1);
      expect(listenable.value, 3);
      expect(atom.lc, 0);
    });

    test('mounts the atom while listened and unmounts afterwards', () {
      fakeAsync((async) {
        final atom = Atom<int>(0);
        var mounted = false;
        onMount(atom, () {
          mounted = true;
          return () => mounted = false;
        });
        final listenable = AtomListenable<int>(atom);
        void listener() {}

        listenable.addListener(listener);
        expect(mounted, isTrue);
        listenable.removeListener(listener);
        async.elapse(storeUnmountDelay);
        expect(mounted, isFalse);
      });
    });
  });

  group('FlutterAuthClient', () {
    test('useSession fetches the session while listened', () {
      fakeAsync((async) {
        final client = createAuthClient(
          baseURL: 'http://localhost:3000',
          fetchOptions: ClientFetchOption(
            customFetchImpl: FakeFetch(
              (_) => jsonResponse(<String, Object?>{
                'user': <String, Object?>{'id': 'u1', 'email': 'a@b.c'},
                'session': <String, Object?>{'id': 's1'},
              }),
            ).call,
          ),
        );
        final session = client.useSession;
        expect(identical(session, client.useSession), isTrue);

        var notified = 0;
        session.addListener(() => notified++);
        async.flushTimers();
        expect(session.value.data?.user.email, 'a@b.c');
        expect(notified, greaterThan(0));
      });
    });
  });
}
