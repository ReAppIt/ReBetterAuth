import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

import '../support/fakes.dart';

const String base = 'http://localhost:4000';

/// Emulates the h3 test router of the upstream suite.
FetchResponse router(RecordedRequest request) {
  final uri = request.uri;
  final path = uri.path;
  Object? parsedBody() {
    final body = request.body;
    if (body is String) {
      try {
        return jsonDecode(body);
      } on FormatException {
        return UrlSearchParamsLike.parse(body);
      }
    }
    if (body is Uint8List) return utf8.decode(body);
    return body?.toString();
  }

  switch (path) {
    case '/ok':
      return textResponse('ok', contentType: 'text/html');
    case '/binary':
      return FetchResponse(
        status: 200,
        bodyBytes: Uint8List.fromList(<int>[1, 2, 3]),
        headers: FetchHeaders(<String, List<String>>{
          'content-type': <String>['application/octet-stream'],
        }),
      );
    case '/post':
      return jsonResponse(<String, Object?>{
        'body': parsedBody(),
        'headers': request.headers,
      });
    case '/query':
      return jsonResponse(uri.queryParameters);
    case '/echo':
      final body = request.body;
      return jsonResponse(<String, Object?>{
        'path': path,
        'body': body is Uint8List ? utf8.decode(body) : body,
        'headers': request.headers,
      });
    case '/404':
      return jsonResponse(
        <String, Object?>{
          'statusCode': 404,
          'statusMessage': 'Cannot find any path matching /404.',
          'stack': <Object?>[],
        },
        status: 404,
        statusText: 'Cannot find any path matching /404.',
      );
    case '/204':
      return emptyResponse(status: 204);
    case '/error':
      return jsonResponse(<String, Object?>{'message': 'error'}, status: 500);
    case '/method':
      return textResponse(request.method);
  }
  if (path.startsWith('/param/')) return textResponse(path);
  return jsonResponse(null, status: 404);
}

/// Parses form bodies so `/post` can echo them as a map.
class UrlSearchParamsLike {
  static Map<String, String> parse(String body) => Uri.splitQueryString(body);
}

BetterFetchOption withRouter([BetterFetchOption? options]) =>
    (options ?? BetterFetchOption())..customFetchImpl = FakeFetch(router).call;

void main() {
  group('fetch', () {
    final $echo = createFetch(
      BetterFetchOption(baseURL: base, customFetchImpl: FakeFetch(router).call),
    );

    test('returns the response body', () async {
      final (:data, error: _) = await betterFetch<Object?>(
        '$base/ok',
        withRouter(),
      );
      expect(data, 'ok');
    });

    test('returns bytes for binary content-type', () async {
      final (:data, error: _) = await betterFetch<Object?>(
        '$base/binary',
        withRouter(),
      );
      expect(data, isA<Uint8List>());
    });

    test('prepends baseURL to a relative url', () async {
      final (:data, error: _) = await betterFetch<Object?>(
        '/ok',
        withRouter(BetterFetchOption(baseURL: base)),
      );
      expect(data, 'ok');
    });

    test('supports an absolute baseURL in a fetch instance', () async {
      final fetch = createFetch(withRouter(BetterFetchOption(baseURL: base)));
      final res = await fetch<Object?>('/ok');
      expect(res.data, 'ok');
      expect(res.error, isNull);
    });

    test('stringifies an object body automatically', () async {
      final (:data, error: _) = await betterFetch<Map<String, Object?>>(
        '$base/post',
        withRouter(
          BetterFetchOption(method: 'POST', body: <String, Object?>{'num': 42}),
        ),
      );
      expect(data?['body'], {'num': 42});
    });

    test('stringifies an array body automatically', () async {
      final (:data, error: _) = await betterFetch<Map<String, Object?>>(
        '$base/post',
        withRouter(
          BetterFetchOption(
            method: 'POST',
            body: <Object?>[
              <String, Object?>{'num': 42},
              <String, Object?>{'num': 43},
            ],
          ),
        ),
      );
      expect(data?['body'], [
        {'num': 42},
        {'num': 43},
      ]);
    });

    test('sends custom headers', () async {
      final (:data, error: _) = await betterFetch<Map<String, Object?>>(
        '$base/post',
        withRouter(
          BetterFetchOption(
            method: 'POST',
            body: <String, Object?>{'num': 42},
            headers: <String, String?>{'X-header': '1'},
          ),
        ),
      );
      expect(data?['headers'], containsPair('x-header', '1'));
      expect(
        data?['headers'],
        containsPair('content-type', 'application/json'),
      );
    });

    for (final query in <Map<String, String>>[
      {'foo': 'bar'},
      {'foo': 'bar', 'bar': 'baz'},
    ]) {
      test('forwards query params $query', () async {
        final (:data, error: _) = await betterFetch<Map<String, Object?>>(
          '$base/query',
          withRouter(BetterFetchOption(method: 'GET', query: query)),
        );
        expect(data, query);
      });
    }

    test('does not stringify the body when content-type is not json', () async {
      const message = '"Hallo von Pascal"';
      final (:data, error: _) = await $echo<Map<String, Object?>>(
        '/echo',
        BetterFetchOption(
          method: 'POST',
          body: message,
          headers: <String, String?>{'Content-Type': 'text/plain'},
        ),
      );
      expect(data?['body'], message);
    });

    test('passes a byte body through untouched', () async {
      const message = 'Hallo von Pascal';
      final (:data, error: _) = await $echo<Map<String, Object?>>(
        '/echo',
        BetterFetchOption(
          method: 'POST',
          body: Uint8List.fromList(utf8.encode(message)),
          headers: <String, String?>{'Content-Type': 'text/plain'},
        ),
      );
      expect(data?['body'], message);
    });

    test('returns a structured error for a 404', () async {
      final (:data, :error) = await betterFetch<Object?>(
        '$base/404',
        withRouter(),
      );
      expect(data, isNull);
      expect(error?.status, 404);
      expect(error?.statusText, 'Cannot find any path matching /404.');
      expect(error?['statusCode'], 404);
      expect(error?['stack'], isEmpty);
    });

    test('returns an empty body for a 204 response', () async {
      final (:data, error: _) = await betterFetch<Object?>(
        '$base/204',
        withRouter(),
      );
      expect(data, '');
    });

    test('returns an empty body for a HEAD request', () async {
      final (:data, error: _) = await betterFetch<Object?>(
        '$base/ok',
        withRouter(BetterFetchOption(method: 'HEAD')),
      );
      expect(data, '');
    });

    test('retries the configured number of times on error', () {
      fakeAsync((async) {
        var count = 0;
        betterFetch<Object?>(
          '$base/error',
          withRouter(
            BetterFetchOption(
              retry: const RetryOptions.count(3),
              onError: (_) => count++,
            ),
          ),
        ).ignore();
        async.elapse(const Duration(seconds: 5));
        expect(count, 4);
      });
    });

    test('waits a linear delay between retries', () {
      fakeAsync((async) {
        var count = 0;
        final beforeCall = clock.now();
        var lastCallTime = beforeCall;
        betterFetch<Object?>(
          '$base/error',
          withRouter(
            BetterFetchOption(
              retry: const LinearRetry(3, delay: Duration(milliseconds: 200)),
              onError: (_) {
                count++;
                lastCallTime = clock.now();
              },
            ),
          ),
        ).ignore();
        async.elapse(const Duration(seconds: 2));
        expect(count, 4);
        expect(
          lastCallTime.difference(beforeCall),
          greaterThanOrEqualTo(const Duration(milliseconds: 600)),
        );
      });
    });

    test('increases the delay with exponential backoff', () {
      fakeAsync((async) {
        var count = 0;
        final delays = <Duration>[];
        DateTime? lastCallTime;
        betterFetch<Object?>(
          '$base/error',
          withRouter(
            BetterFetchOption(
              retry: const ExponentialRetry(
                3,
                baseDelay: Duration(milliseconds: 100),
                maxDelay: Duration(seconds: 1),
              ),
              onError: (_) {
                count++;
                final now = clock.now();
                if (lastCallTime != null) {
                  delays.add(now.difference(lastCallTime!));
                }
                lastCallTime = now;
              },
            ),
          ),
        ).ignore();
        async.elapse(const Duration(seconds: 3));
        expect(count, 4);
        expect(delays[1], greaterThan(delays[0]));
        expect(delays[2], greaterThan(delays[1]));
        expect(
          delays[0],
          greaterThanOrEqualTo(const Duration(milliseconds: 100)),
        );
        expect(
          delays[1],
          greaterThanOrEqualTo(const Duration(milliseconds: 200)),
        );
        expect(
          delays[2],
          greaterThanOrEqualTo(const Duration(milliseconds: 400)),
        );
      });
    });

    test('resolves a dynamic path param', () async {
      final (:data, error: _) = await betterFetch<Object?>(
        '$base/param/:id',
        withRouter(BetterFetchOption(params: <Object?>['2'])),
      );
      expect(data, '/param/2');
    });

    test('resolves the http method from a method modifier prefix', () async {
      final post = await betterFetch<Object?>(
        '@post/method',
        withRouter(BetterFetchOption(baseURL: base)),
      );
      expect(post.data, 'POST');
      final get = await betterFetch<Object?>(
        '@get/method',
        withRouter(BetterFetchOption(baseURL: base)),
      );
      expect(get.data, 'GET');
    });

    test('sets a Bearer auth header', () async {
      final (:data, error: _) = await betterFetch<Map<String, Object?>>(
        '$base/post',
        withRouter(
          BetterFetchOption(method: 'POST', auth: Bearer.value('test')),
        ),
      );
      expect(data?['headers'], containsPair('authorization', 'Bearer test'));
    });

    test('sets a Bearer auth header from an async token', () async {
      final (:data, error: _) = await betterFetch<Map<String, Object?>>(
        '$base/post',
        withRouter(
          BetterFetchOption(method: 'POST', auth: Bearer(() async => 'test')),
        ),
      );
      expect(data?['headers'], containsPair('authorization', 'Bearer test'));
    });

    test('sets a Basic auth header from username and password', () async {
      String? header;
      await betterFetch<Object?>(
        '$base/post',
        withRouter(
          BetterFetchOption(
            auth: Basic(
              username: () => 'test-user',
              password: () async => 'test-password',
            ),
            onRequest: (context) {
              header = context.headers['authorization'];
              return null;
            },
          ),
        ),
      );
      expect(header, 'Basic dGVzdC11c2VyOnRlc3QtcGFzc3dvcmQ=');
    });
  });

  group('fetch-error', () {
    final f = createFetch(
      BetterFetchOption(
        baseURL: 'http://localhost:4001',
        customFetchImpl: FakeFetch((_) => emptyResponse(status: 500)).call,
        throwOnError: true,
      ),
    );

    test('throws a BetterFetchError when the response is not ok', () {
      expect(f<Object?>('/ok'), throwsA(isA<BetterFetchError>()));
    });
  });

  group('hooks', () {
    test('calls onRequest and onResponse', () async {
      var onRequest = 0;
      var onResponse = 0;
      final f = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch(
            (_) => jsonResponse(<String, Object?>{'message': 'ok'}),
          ).call,
          onRequest: (_) {
            onRequest++;
            return null;
          },
          onResponse: (_) {
            onResponse++;
            return null;
          },
        ),
      );
      await f<Object?>('/ok');
      expect(onRequest, 1);
      expect(onResponse, 1);
    });

    test('calls onError but not onSuccess on a failing response', () async {
      ErrorContext? errorContext;
      var onResponse = 0;
      var onSuccess = 0;
      final f = createFetch(
        BetterFetchOption(
          baseURL: 'http://localhost:4001',
          customFetchImpl: FakeFetch(
            (_) => jsonResponse(<String, Object?>{
              'message': 'Server Error',
            }, status: 500),
          ).call,
          onError: (context) => errorContext = context,
          onResponse: (_) {
            onResponse++;
            return null;
          },
          onSuccess: (_) => onSuccess++,
        ),
      );
      await f<Object?>('/ok');
      expect(errorContext?.responseText, '{"message":"Server Error"}');
      expect(errorContext?.error.message, 'Server Error');
      expect(errorContext?.error.status, 500);
      expect(errorContext?.error.statusText, '');
      expect(onResponse, 1);
      expect(onSuccess, 0);
    });

    test('works with a relative url and a custom fetch impl', () async {
      var onRequest = 0;
      final f = createFetch(
        BetterFetchOption(
          customFetchImpl: FakeFetch(
            (_) => jsonResponse(<String, Object?>{'message': 'ok'}),
          ).call,
          onRequest: (_) {
            onRequest++;
            return null;
          },
        ),
      );
      final res = await f<Map<String, Object?>>('/ok');
      expect(res.data, {'message': 'ok'});
      expect(onRequest, 1);
    });
  });

  group('fetch-error-throw', () {
    final f = createFetch(
      BetterFetchOption(
        baseURL: 'http://localhost:4001',
        customFetchImpl: FakeFetch((request) {
          final path = request.uri.path;
          if (path.startsWith('/ok')) {
            return jsonResponse(<String, Object?>{'message': 'ok'});
          }
          if (path.startsWith('/error-json-response')) {
            return jsonResponse(<String, Object?>{
              'message': 'error',
            }, status: 400);
          }
          if (path.startsWith('/error-string-response')) {
            return textResponse('An error occurred', status: 400);
          }
          return emptyResponse(status: 500);
        }).call,
        throwOnError: true,
      ),
    );

    test('throws a BetterFetchError when the response is not ok', () {
      expect(f<Object?>('/not-ok'), throwsA(isA<BetterFetchError>()));
    });

    test('exposes the parsed JSON body on the thrown error', () async {
      await expectLater(
        f<Object?>('/error-json-response'),
        throwsA(
          isA<BetterFetchError>().having((e) => e.error, 'error', {
            'message': 'error',
          }),
        ),
      );
    });

    test('exposes the text body on the thrown error', () async {
      await expectLater(
        f<Object?>('/error-string-response'),
        throwsA(
          isA<BetterFetchError>().having(
            (e) => e.error,
            'error',
            'An error occurred',
          ),
        ),
      );
    });

    test('returns data when throw is enabled and the response is ok', () async {
      final res = await f<Map<String, Object?>>('/ok');
      expect(res.data, {'message': 'ok'});
    });
  });

  group('form data', () {
    test('encodes an object body as form-urlencoded', () async {
      Object? sentBody;
      await betterFetch<Object?>(
        '/echo',
        BetterFetchOption(
          body: <String, Object?>{'name': 'John Doe', 'age': 30},
          headers: <String, String?>{
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          customFetchImpl: FakeFetch((request) {
            sentBody = request.body;
            return emptyResponse();
          }).call,
        ),
      );
      expect(sentBody, 'name=John+Doe&age=30');
    });
  });
}
