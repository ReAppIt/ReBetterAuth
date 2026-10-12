import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

void main() {
  group('atom', () {
    test('listen waits for changes; subscribe calls immediately', () {
      final atom = Atom<int>(1);
      final listened = <(int, int?)>[];
      final subscribed = <(int, int?)>[];
      atom
        ..listen((value, old) => listened.add((value, old)))
        ..subscribe((value, old) => subscribed.add((value, old)));

      expect(listened, isEmpty);
      expect(subscribed, [(1, null)]);

      atom.set(2);
      expect(listened, [(2, 1)]);
      expect(subscribed, [(1, null), (2, 1)]);
    });

    test('set ignores an equal value', () {
      final atom = Atom<String>('a');
      var calls = 0;
      atom
        ..listen((_, _) => calls++)
        ..set('a');
      expect(calls, 0);
    });

    test('unsubscribe removes the listener and lowers lc', () {
      final atom = Atom<int>(0);
      var calls = 0;
      final unbind = atom.listen((_, _) => calls++);
      expect(atom.lc, 1);
      unbind();
      atom.set(1);
      expect(calls, 0);
      expect(atom.lc, 0);
    });
  });

  group('onMount', () {
    test('mounts on the first listener and unmounts after the delay', () {
      fakeAsync((async) {
        final atom = Atom<int>(0);
        var mounts = 0;
        var unmounts = 0;
        onMount(atom, () {
          mounts++;
          return () => unmounts++;
        });

        final first = atom.listen((_, _) {});
        final second = atom.listen((_, _) {});
        expect(mounts, 1);

        first();
        second();
        async.elapse(storeUnmountDelay - const Duration(milliseconds: 1));
        expect(unmounts, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(unmounts, 1);

        atom.listen((_, _) {});
        expect(mounts, 2);
      });
    });

    test('a new listener within the delay keeps the atom mounted', () {
      fakeAsync((async) {
        final atom = Atom<int>(0);
        var unmounts = 0;
        onMount(
          atom,
          () =>
              () => unmounts++,
        );

        atom.listen((_, _) {})();
        async.elapse(const Duration(milliseconds: 500));
        final unbind = atom.listen((_, _) {});
        async.elapse(storeUnmountDelay);
        expect(unmounts, 0);

        unbind();
        async.elapse(storeUnmountDelay);
        expect(unmounts, 1);
      });
    });

    test('get() without listeners mounts and schedules an unmount', () {
      fakeAsync((async) {
        final atom = Atom<int>(5);
        var mounts = 0;
        var unmounts = 0;
        onMount(atom, () {
          mounts++;
          return () => unmounts++;
        });

        expect(atom.get(), 5);
        expect(mounts, 1);
        expect(atom.lc, 0);
        async.elapse(storeUnmountDelay);
        expect(unmounts, 1);
      });
    });

    test('.value does not mount', () {
      final atom = Atom<int>(5);
      var mounts = 0;
      onMount(atom, () {
        mounts++;
        return null;
      });
      expect(atom.value, 5);
      expect(mounts, 0);
    });

    test('mount callbacks run in reverse registration order', () {
      final atom = Atom<int>(0);
      final order = <String>[];
      onMount(atom, () {
        order.add('first');
        return null;
      });
      onMount(atom, () {
        order.add('second');
        return null;
      });
      atom.listen((_, _) {});
      expect(order, ['second', 'first']);
    });
  });

  group('onSet', () {
    test('abort keeps the previous value', () {
      final atom = Atom<int>(1);
      var calls = 0;
      atom.listen((_, _) => calls++);
      final remove = onSet<int>(atom, (event) {
        if (event.newValue.isNegative) event.abort();
      });

      atom.set(-1);
      expect(atom.value, 1);
      expect(calls, 0);

      atom.set(2);
      expect(atom.value, 2);

      remove();
      atom.set(-3);
      expect(atom.value, -3);
    });
  });

  group('listener queue', () {
    test('nested updates run after the current notification round', () {
      final a = Atom<int>(0);
      final b = Atom<int>(0);
      final order = <String>[];
      a
        ..listen((value, _) {
          order.add('a1:$value');
          b.set(value);
        })
        ..listen((value, _) => order.add('a2:$value'));
      b.listen((value, _) => order.add('b:$value'));

      a.set(1);
      expect(order, ['a1:1', 'a2:1', 'b:1']);
    });

    test('unsubscribing drops already queued calls of that listener', () {
      final atom = Atom<int>(0);
      final calls = <String>[];
      late void Function() unbindSecond;
      atom.listen((_, _) {
        calls.add('first');
        unbindSecond();
      });
      unbindSecond = atom.listen((_, _) => calls.add('second'));

      atom.set(1);
      expect(calls, ['first']);
    });
  });
}
