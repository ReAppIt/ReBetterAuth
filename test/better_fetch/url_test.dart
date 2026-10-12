import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';
import 'package:re_better_auth/src/better_fetch/url.dart';

void main() {
  group('url', () {
    test('interpolates a path param', () {
      final url = getURL(
        'param/:id',
        BetterFetchOption(
          params: <String, Object?>{'id': '1'},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/param/1');
    });

    test("uses the url's own origin when it starts with http", () {
      final url = getURL(
        'http://localhost:4001/param/:id',
        BetterFetchOption(params: <String, Object?>{'id': '1'}),
      );
      expect('$url', 'http://localhost:4001/param/1');
    });

    test('appends a query param', () {
      final url = getURL(
        '/query',
        BetterFetchOption(
          query: <String, Object?>{'id': '1'},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/query?id=1');
    });

    test('normalizes repeated leading slashes before joining with base', () {
      final url = getURL(
        '///accounts/list',
        BetterFetchOption(baseURL: 'https://api.example.com'),
      );
      expect('$url', 'https://api.example.com/accounts/list');
    });

    test('omits null query values', () {
      final url = getURL(
        '/query',
        BetterFetchOption(
          query: <String, Object?>{'id': '1', 'nullValue': null},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/query?id=1');
    });

    test('merges query params already present on the url', () {
      final url = getURL(
        '/query?name=test&age=20',
        BetterFetchOption(
          query: <String, Object?>{'id': '1'},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/query?name=test&age=20&id=1');
    });

    test('orders query params by insertion', () {
      final url = getURL(
        '/query',
        BetterFetchOption(
          query: <String, Object?>{'id': '1', 'name': 'test2'},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/query?id=1&name=test2');
    });

    test('encodes query param values', () {
      final url = getURL(
        '/query',
        BetterFetchOption(
          query: <String, Object?>{'id': '#20', 'name': 'test 2'},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/query?id=%2320&name=test%202');
    });

    test('encodes dynamic path params', () {
      final url = getURL(
        '/param/:id/:space',
        BetterFetchOption(
          params: <String, Object?>{'id': '#test', 'space': 'item 1'},
          baseURL: 'http://localhost:4001',
        ),
      );
      expect('$url', 'http://localhost:4001/param/%23test/item%201');
    });

    test('encodes dynamic path params as single path segments', () {
      final url = getURL(
        '/v1/users/:id',
        BetterFetchOption(
          params: <String, Object?>{'id': 'teams/engineering'},
          baseURL: 'https://api.example.com',
        ),
      );
      expect('$url', 'https://api.example.com/v1/users/teams%2Fengineering');
    });

    test('encodes colons in dynamic path params', () {
      final url = getURL(
        '/v1/users/:id',
        BetterFetchOption(
          params: <String, Object?>{'id': 'team:member'},
          baseURL: 'https://api.example.com',
        ),
      );
      expect('$url', 'https://api.example.com/v1/users/team%3Amember');
    });

    test('encodes fragment markers in literal path segments', () {
      final url = getURL(
        '/files/report#draft',
        BetterFetchOption(baseURL: 'https://api.example.com'),
      );
      expect('$url', 'https://api.example.com/files/report%23draft');
    });

    test('encodes array path params as single path segments', () {
      final url = getURL(
        '/v1/:resource/:id',
        BetterFetchOption(
          params: <Object?>['teams/engineering', 'current'],
          baseURL: 'https://api.example.com',
        ),
      );
      expect('$url', 'https://api.example.com/v1/teams%2Fengineering/current');
    });

    test('rejects reserved dynamic path params', () {
      expect(
        () => getURL(
          '/v1/users/:id',
          BetterFetchOption(
            params: <String, Object?>{'id': '..'},
            baseURL: 'https://api.example.com',
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => '${e.message}',
            'message',
            contains('reserved path segments'),
          ),
        ),
      );
    });

    test('expands list query values into repeated params', () {
      final url = getURL(
        '/test',
        BetterFetchOption(
          query: <String, Object?>{
            'filterValue': <Object?>['admin', 'user'],
          },
          baseURL: 'http://localhost:4000',
        ),
      );
      expect(
        '$url',
        'http://localhost:4000/test?filterValue=admin&filterValue=user',
      );
    });

    test('serializes object query values as JSON strings', () {
      final url = getURL(
        '/test',
        BetterFetchOption(
          query: <String, Object?>{
            'options': <String, Object?>{'page': 1, 'limit': 10},
          },
          baseURL: 'http://localhost:4000',
        ),
      );
      expect(
        '$url',
        'http://localhost:4000/test?options=%7B%22page%22%3A1%2C%22limit%22%3A10%7D',
      );
    });

    test('leaves plain string query values untouched', () {
      final url = getURL(
        '/test',
        BetterFetchOption(
          query: <String, Object?>{'foo': 'bar'},
          baseURL: 'http://localhost:4000',
        ),
      );
      expect('$url', 'http://localhost:4000/test?foo=bar');
    });
  });
}
