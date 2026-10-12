import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

import '../support/fakes.dart';

void main() {
  group('create-fetch-runtime-test', () {
    test('should merge baseURL and url', () async {
      final seen = <String>[];
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch((_) => emptyResponse()).call,
        ),
      );
      Future<void> check(String url, String baseURL) => $fetch<Object?>(
        url,
        BetterFetchOption(
          baseURL: baseURL,
          body: <String, Object?>{'id': 1},
          onRequest: (context) {
            seen.add('${context.url}');
            return null;
          },
        ),
      );

      await check('/echo', 'http://localhost:4001');
      await check('/path', 'http://localhost:4001/v1');
      await check('/path', 'http://localhost:4001/v1/');
      await check('/path/', 'http://localhost:4001/v1/');
      expect(seen, [
        'http://localhost:4001/echo',
        'http://localhost:4001/v1/path',
        'http://localhost:4001/v1/path',
        'http://localhost:4001/v1/path/',
      ]);
    });

    test('should work with method modifiers', () async {
      final $f = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch(
            (request) =>
                jsonResponse(<String, Object?>{'method': request.method}),
          ).call,
        ),
      );
      for (final method in <String>['get', 'post', 'put', 'patch']) {
        final res = await $f<Map<String, Object?>>('@$method/method');
        expect(res.data, {'method': method.toUpperCase()});
      }
    });

    test('treats literal colons as path text', () async {
      var requestURL = '';
      final fetch = createFetch(
        BetterFetchOption(
          baseURL: 'https://places.googleapis.com',
          customFetchImpl: FakeFetch((request) {
            requestURL = '${request.url}';
            return emptyResponse();
          }).call,
        ),
      );
      await fetch<Object?>('/v1/places:searchNearby');
      expect(
        requestURL,
        'https://places.googleapis.com/v1/places:searchNearby',
      );
    });

    test('keeps the request-context identity stable across hooks', () async {
      final seen = <RequestContext>[];
      BetterFetchPlugin capture(String id) => BetterFetchPlugin(
        id: id,
        name: id,
        hooks: FetchHooks(
          onRequest: (context) {
            seen.add(context);
            return RequestContext(
              url: context.url,
              headers: context.headers,
              body: context.body,
              method: context.method,
              signal: context.signal,
              options: context.options,
            );
          },
        ),
      );
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch((_) => emptyResponse()).call,
          plugins: <BetterFetchPlugin>[capture('a'), capture('b')],
        ),
      );
      RequestContext? successRequest;
      await $fetch<Object?>(
        '/',
        BetterFetchOption(
          onSuccess: (context) => successRequest = context.request,
        ),
      );
      expect(seen, hasLength(2));
      expect(seen[1], same(seen[0]));
      expect(successRequest, same(seen[0]));
    });
  });

  group('plugin', () {
    test('passes modified options to subsequent plugins', () async {
      Duration? receivedTimeout;
      final setTimeoutPlugin = BetterFetchPlugin(
        id: 'set-timeout',
        name: 'Set timeout',
        init: (url, options) => (
          url: url,
          options: options.copy()..timeout = const Duration(milliseconds: 100),
        ),
      );
      final readTimeoutPlugin = BetterFetchPlugin(
        id: 'read-timeout',
        name: 'Read timeout',
        init: (url, options) {
          receivedTimeout = options.timeout;
          return (url: url, options: null);
        },
      );
      final fetch = createFetch(
        BetterFetchOption(
          plugins: <BetterFetchPlugin>[setTimeoutPlugin, readTimeoutPlugin],
          customFetchImpl: FakeFetch((_) => emptyResponse()).call,
        ),
      );
      await fetch<Object?>('https://example.com');
      expect(receivedTimeout, const Duration(milliseconds: 100));
    });

    test('runs plugin hooks after the per-call hooks', () async {
      final order = <String>[];
      final fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch(
            (_) => jsonResponse(<String, Object?>{}),
          ).call,
          plugins: <BetterFetchPlugin>[
            BetterFetchPlugin(
              id: 'p',
              name: 'p',
              hooks: FetchHooks(onSuccess: (_) => order.add('plugin')),
            ),
          ],
        ),
      );
      await fetch<Object?>(
        '/',
        BetterFetchOption(onSuccess: (_) => order.add('call')),
      );
      expect(order, ['call', 'plugin']);
    });
  });

  group('create-fetch-headers', () {
    test('preserves headers passed as a plain object', () async {
      final fake = FakeFetch((_) => emptyResponse());
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: fake.call,
        ),
      );
      await $fetch<Object?>(
        '/x',
        BetterFetchOption(headers: <String, String?>{'cookie': 'session=abc'}),
      );
      expect(fake.requests.single.headers['cookie'], 'session=abc');
    });

    test('merges config headers with per-call headers', () async {
      final fake = FakeFetch((_) => emptyResponse());
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          headers: <String, String?>{'x-base': 'base'},
          customFetchImpl: fake.call,
        ),
      );
      await $fetch<Object?>(
        '/x',
        BetterFetchOption(headers: <String, String?>{'cookie': 'session=abc'}),
      );
      expect(fake.requests.single.headers['x-base'], 'base');
      expect(fake.requests.single.headers['cookie'], 'session=abc');
    });

    test('exposes options.headers to plugins as a spreadable map', () async {
      Map<String, String?>? spread;
      final inspectPlugin = BetterFetchPlugin(
        id: 'inspect',
        name: 'inspect',
        init: (url, options) {
          spread = <String, String?>{...?options.headers};
          return (url: url, options: options);
        },
      );
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch((_) => emptyResponse()).call,
          plugins: <BetterFetchPlugin>[inspectPlugin],
        ),
      );
      await $fetch<Object?>(
        '/x',
        BetterFetchOption(headers: <String, String?>{'x-user': 'u'}),
      );
      expect(spread, {'x-user': 'u'});
    });
  });

  group('catchAllError', () {
    test('returns transport errors as a 500 error', () async {
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          catchAllError: true,
          customFetchImpl: FakeFetch((_) => throw StateError('offline')).call,
        ),
      );
      final (:data, :error) = await $fetch<Object?>('/x');
      expect(data, isNull);
      expect(error?.status, 500);
      expect(error?.statusText, 'Fetch Error');
      expect(error?['error'], isA<StateError>());
    });

    test('rethrows transport errors without it', () {
      final $fetch = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch((_) => throw StateError('offline')).call,
        ),
      );
      expect($fetch<Object?>('/x'), throwsStateError);
    });
  });
}
