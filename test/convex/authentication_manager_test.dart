import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/convex.dart';
import 'package:re_better_auth/vanilla.dart';

import '../support/fakes.dart';

String _jwt({required int iat, required int exp}) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'RS256'})}.${part({'iat': iat, 'exp': exp})}.sig';
}

/// Hands out [tokens] in order and records each `forceRefreshToken`.
class _Tokens {
  _Tokens(this.tokens);

  final List<String?> tokens;
  final List<bool> calls = <bool>[];

  Future<String?> call({required bool forceRefreshToken}) async {
    calls.add(forceRefreshToken);
    return tokens.isEmpty ? null : tokens.removeAt(0);
  }
}

void main() {
  setUp(resetGlobals);
  tearDown(resetGlobals);

  late List<String?> applied;
  late List<bool> changes;
  late ConvexTokenAuth auth;

  setUp(() {
    applied = <String?>[];
    changes = <bool>[];
    auth = ConvexTokenAuth((token) async => applied.add(token));
  });

  int nowSeconds() => clock.now().millisecondsSinceEpoch ~/ 1000;

  test('sets the token, then refetches it 10s before it expires', () {
    fakeAsync((async) {
      final now = nowSeconds();
      final t1 = _jwt(iat: now - 600, exp: now + 3000);
      final t2 = _jwt(iat: now, exp: now + 3600);
      final t3 = _jwt(iat: now + 3590, exp: now + 7190);
      final tokens = _Tokens(<String?>[t1, t2, t3]);

      auth.setAuth(tokens.call, changes.add);
      async.flushMicrotasks();
      expect(tokens.calls, <bool>[false, true]);
      expect(applied, <String?>[t1, t2]);
      expect(changes, <bool>[true]);

      async.elapse(const Duration(seconds: 3589));
      expect(tokens.calls, hasLength(2));
      async.elapse(const Duration(seconds: 1));
      expect(tokens.calls, <bool>[false, true, true]);
      expect(applied, <String?>[t1, t2, t3]);
      expect(changes, <bool>[true]);
    });
  });

  test('fetches a fresh token when there is no cached one', () {
    fakeAsync((async) {
      final now = nowSeconds();
      final t1 = _jwt(iat: now, exp: now + 3600);
      final tokens = _Tokens(<String?>[null, t1]);

      auth.setAuth(tokens.call, changes.add);
      async.flushMicrotasks();
      expect(tokens.calls, <bool>[false, true]);
      expect(applied, <String?>[t1]);
      expect(changes, <bool>[true]);
    });
  });

  test('reports unauthenticated when no token can be fetched', () {
    fakeAsync((async) {
      final tokens = _Tokens(<String?>[]);

      auth.setAuth(tokens.call, changes.add);
      async.flushMicrotasks();
      expect(tokens.calls, <bool>[false, true]);
      expect(applied, isEmpty);
      expect(changes, <bool>[false]);
    });
  });

  test('clears the token when a scheduled refetch gets none', () {
    fakeAsync((async) {
      final now = nowSeconds();
      final t1 = _jwt(iat: now - 60, exp: now + 3540);
      final t2 = _jwt(iat: now, exp: now + 3600);
      final tokens = _Tokens(<String?>[t1, t2]);

      auth.setAuth(tokens.call, changes.add);
      async.elapse(const Duration(hours: 1));
      expect(applied, <String?>[t1, t2, null]);
      expect(changes, <bool>[true, false]);
      async.elapse(const Duration(hours: 2));
      expect(tokens.calls, hasLength(3));
    });
  });

  test('clearAuth clears the token and cancels the refetch', () {
    fakeAsync((async) {
      final now = nowSeconds();
      final tokens = _Tokens(<String?>[
        _jwt(iat: now - 60, exp: now + 3540),
        _jwt(iat: now, exp: now + 3600),
      ]);

      auth.setAuth(tokens.call, changes.add);
      async.flushMicrotasks();
      auth.clearAuth();
      async.flushMicrotasks();
      expect(applied.last, isNull);
      async.elapse(const Duration(hours: 2));
      expect(tokens.calls, hasLength(2));
    });
  });

  test('ignores a token fetched for a replaced config', () {
    fakeAsync((async) {
      final now = nowSeconds();
      final slow = Completer<String?>();
      final stale = _jwt(iat: now, exp: now + 60);
      final fresh = _jwt(iat: now - 60, exp: now + 3540);
      final fresh2 = _jwt(iat: now, exp: now + 3600);
      final staleChanges = <bool>[];

      auth
        ..setAuth(
          ({required forceRefreshToken}) => slow.future,
          staleChanges.add,
        )
        ..setAuth(_Tokens(<String?>[fresh, fresh2]).call, changes.add);
      async.flushMicrotasks();
      slow.complete(stale);
      async.flushMicrotasks();
      expect(applied, <String?>[fresh, fresh2]);
      expect(staleChanges, isEmpty);
    });
  });

  test('refetches on resume when the refetch time passed in sleep', () {
    fakeAsync((async) {
      final now = nowSeconds();
      final tokens = _Tokens(<String?>[
        _jwt(iat: now - 60, exp: now + 3540),
        _jwt(iat: now, exp: now + 3600),
        _jwt(iat: now, exp: now + 7200),
      ]);
      auth.setAuth(tokens.call, changes.add);
      async.flushMicrotasks();

      getGlobalFocusManager().setFocused(true);
      async.flushMicrotasks();
      expect(tokens.calls, hasLength(2));

      withClock(Clock.fixed(clock.now().add(const Duration(hours: 2))), () {
        getGlobalFocusManager().setFocused(true);
      });
      async.flushMicrotasks();
      expect(tokens.calls, <bool>[false, true, true]);
      expect(applied, hasLength(3));
    });
  });

  test('does not schedule a refetch for a token without iat and exp', () {
    fakeAsync((async) {
      final tokens = _Tokens(<String?>['a.e30.sig', 'b.e30.sig']);

      auth.setAuth(tokens.call, changes.add);
      async.elapse(const Duration(days: 30));
      expect(tokens.calls, <bool>[false, true]);
      expect(changes, <bool>[true]);
    });
  });
}
