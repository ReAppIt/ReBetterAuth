import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

void main() {
  group('isJsonEqual', () {
    test('returns true for identical primitives', () {
      expect(isJsonEqual(1, 1), isTrue);
      expect(isJsonEqual('a', 'a'), isTrue);
      expect(isJsonEqual(true, true), isTrue);
      expect(isJsonEqual(null, null), isTrue);
    });

    test('returns false for different primitives', () {
      expect(isJsonEqual(1, 2), isFalse);
      expect(isJsonEqual('a', 'b'), isFalse);
      expect(isJsonEqual(true, false), isFalse);
      expect(isJsonEqual(null, 1), isFalse);
      expect(isJsonEqual(null, 'a'), isFalse);
    });

    test('returns true for same-reference objects', () {
      final obj = <String, Object?>{'a': 1};
      expect(isJsonEqual(obj, obj), isTrue);
    });

    test('returns true for structurally equal objects', () {
      expect(isJsonEqual({'a': 1, 'b': 'x'}, {'a': 1, 'b': 'x'}), isTrue);
    });

    test('returns true for nested objects', () {
      expect(
        isJsonEqual(
          {
            'user': {'id': '1', 'email': 'a@b.com'},
            'session': {'id': 's1'},
          },
          {
            'user': {'id': '1', 'email': 'a@b.com'},
            'session': {'id': 's1'},
          },
        ),
        isTrue,
      );
    });

    test('returns false for objects with different values', () {
      expect(isJsonEqual({'a': 1}, {'a': 2}), isFalse);
    });

    test('returns false for objects with different keys', () {
      expect(isJsonEqual({'a': 1}, {'b': 1}), isFalse);
      expect(isJsonEqual({'a': 1}, {'a': 1, 'b': 2}), isFalse);
    });

    test('returns true for identical arrays', () {
      expect(isJsonEqual([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('returns false for arrays of different length', () {
      expect(isJsonEqual([1, 2], [1, 2, 3]), isFalse);
    });

    test('returns false for arrays with different elements', () {
      expect(isJsonEqual([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('returns true for deeply nested structures', () {
      expect(
        isJsonEqual(
          {
            'a': [
              {
                'b': [1, 2],
              },
              {'c': null},
            ],
          },
          {
            'a': [
              {
                'b': [1, 2],
              },
              {'c': null},
            ],
          },
        ),
        isTrue,
      );
    });

    test('returns false for null vs object', () {
      expect(isJsonEqual(null, <String, Object?>{}), isFalse);
      expect(isJsonEqual(<String, Object?>{}, null), isFalse);
    });

    test('returns false for array vs object', () {
      expect(isJsonEqual(<Object?>[], <String, Object?>{}), isFalse);
    });

    test('compares DateTime by value (JS compares Date by reference)', () {
      expect(
        isJsonEqual({'at': DateTime.utc(2026)}, {'at': DateTime.utc(2026)}),
        isTrue,
      );
    });
  });

  group('withEquality', () {
    test('suppresses set when values are structurally equal', () {
      final store = Atom<Map<String, Object?>>({'a': 1, 'b': 'x'});
      withEquality(store, isJsonEqual);
      var calls = 0;
      store
        ..listen((_, _) => calls++)
        ..set({'a': 1, 'b': 'x'});
      expect(calls, 0);
    });

    test('allows set when values differ', () {
      final store = Atom<Map<String, Object?>>({'a': 1});
      withEquality(store, isJsonEqual);
      var calls = 0;
      store
        ..listen((_, _) => calls++)
        ..set({'a': 2});
      expect(calls, 1);
      expect(store.get(), {'a': 2});
    });

    test('returns an unsubscribe function that removes the gate', () {
      final store = Atom<Map<String, Object?>>({'a': 1});
      final unbind = withEquality(store, isJsonEqual);
      var calls = 0;
      store
        ..listen((_, _) => calls++)
        ..set({'a': 1});
      expect(calls, 0);

      unbind();
      store.set({'a': 1});
      expect(calls, 1);
    });

    test('works with nested session-like data', () {
      final store = Atom<Map<String, Object?>>({
        'data': {
          'user': {'id': '1'},
          'session': {'id': 's1'},
        },
        'error': null,
      });
      withEquality(store, isJsonEqual);
      var calls = 0;
      store
        ..listen((_, _) => calls++)
        ..set({
          'data': {
            'user': {'id': '1'},
            'session': {'id': 's1'},
          },
          'error': null,
        });
      expect(calls, 0);

      store.set({
        'data': {
          'user': {'id': '2'},
          'session': {'id': 's1'},
        },
        'error': null,
      });
      expect(calls, 1);
    });
  });
}
