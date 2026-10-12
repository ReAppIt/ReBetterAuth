import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';
import 'package:re_better_auth/src/better_fetch/url.dart';
import 'package:re_better_auth/src/better_fetch/utils.dart';

void main() {
  group('method modifiers', () {
    for (final method in <String>['get', 'post', 'put', 'patch', 'delete']) {
      test('resolves @$method consistently for method and URL', () {
        final path = '@$method/users';
        final options = BetterFetchOption(baseURL: 'https://example.com');
        expect(getMethod(path), method.toUpperCase());
        expect('${getURL(path, options)}', 'https://example.com/users');
      });
    }

    test('prefers an explicit method over the modifier', () {
      expect(
        getMethod('@put/users', BetterFetchOption(method: 'patch')),
        'PATCH',
      );
    });

    for (final path in <String>[
      '@unknown/users',
      '/users/@put/profile',
      '@PUT/users',
    ]) {
      test('preserves an unrecognized modifier in $path', () {
        expect(getMethod(path), 'GET');
        expect(
          getMethod(
            path,
            BetterFetchOption(body: <String, Object?>{'id': '1'}),
          ),
          'POST',
        );
        expect(
          '${getURL(path, BetterFetchOption(baseURL: 'https://example.com'))}',
          'https://example.com/${path.replaceFirst(RegExp('^/'), '').replaceAll('@', '%40')}',
        );
      });
    }

    test("preserves a bare modifier's existing method and path behavior", () {
      expect(getMethod('@put'), 'PUT');
      expect(
        '${getURL('@put', BetterFetchOption(baseURL: 'https://example.com'))}',
        'https://example.com/%40put',
      );
    });
  });

  group('getBody', () {
    test('returns null when there is no body', () {
      expect(getBody(BetterFetchOption(), <String, String>{}), isNull);
    });

    test('JSON-stringifies a serializable body by default', () {
      final body = getBody(
        BetterFetchOption(body: <String, Object?>{'a': 1}),
        <String, String>{},
      );
      expect(body, jsonEncode({'a': 1}));
    });

    test('JSON-stringifies when content-type is application/json', () {
      final body = getBody(
        BetterFetchOption(body: <String, Object?>{'a': 1}),
        <String, String>{'content-type': 'application/json'},
      );
      expect(body, jsonEncode({'a': 1}));
    });

    test('serializes DateTime values to ISO 8601 like JSON.stringify', () {
      final date = DateTime.utc(2026, 6, 6);
      final body = getBody(
        BetterFetchOption(body: <String, Object?>{'at': date}),
        <String, String>{},
      );
      expect(body, '{"at":"2026-06-06T00:00:00.000Z"}');
    });

    for (final (name, value) in <(String, String)>[
      ('content-type', 'application/x-www-form-urlencoded'),
      ('content-type', 'application/x-www-form-urlencoded; charset=utf-8'),
      ('content-type', 'Application/X-WWW-Form-Urlencoded'),
      ('Content-Type', 'application/x-www-form-urlencoded'),
    ]) {
      test('encodes a form-urlencoded body given $name: $value', () async {
        final options = BetterFetchOption(
          body: <String, Object?>{'a': '1', 'b': '2'},
          headers: <String, String?>{name: value},
        );
        expect(getBody(options, await getHeaders(options)), 'a=1&b=2');
      });
    }

    test('passes a string body through untouched', () {
      expect(
        getBody(BetterFetchOption(body: 'raw'), <String, String>{}),
        'raw',
      );
    });

    test('passes non-serializable bodies through untouched', () {
      final bytes = Uint8List.fromList(<int>[1, 2]);
      expect(
        getBody(BetterFetchOption(body: bytes), <String, String>{}),
        same(bytes),
      );
    });
  });
}
