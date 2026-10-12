import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

/// Serves canned responses to Dio and records what it was asked.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options, String body) respond;
  final List<(RequestOptions, String)> requests = <(RequestOptions, String)>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    final body = utf8.decode(bytes);
    requests.add((options, body));
    return respond(options, body);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('sends the request and keeps every Set-Cookie value', () async {
    final adapter = _FakeAdapter(
      (options, body) => ResponseBody.fromString(
        '{"ok":true}',
        200,
        headers: <String, List<String>>{
          'content-type': <String>['application/json'],
          'set-cookie': <String>[
            'better-auth.session_token=abc; Path=/',
            'better-auth.session_data=xyz; Path=/',
          ],
        },
      ),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final $fetch = createFetch(
      BetterFetchOption(
        baseURL: 'https://api.example.com/api/auth',
        customFetchImpl: dioFetch(dio),
      ),
    );

    FetchResponse? response;
    final (:data, error: _) = await $fetch<Map<String, Object?>>(
      '/sign-in/email',
      BetterFetchOption(
        body: <String, Object?>{'email': 'a@b.c'},
        onSuccess: (context) => response = context.response,
      ),
    );

    expect(data, {'ok': true});
    final (options, body) = adapter.requests.single;
    expect(options.method, 'POST');
    expect('${options.uri}', 'https://api.example.com/api/auth/sign-in/email');
    expect(jsonDecode(body), {'email': 'a@b.c'});
    expect(
      response?.headers.get('set-cookie'),
      'better-auth.session_token=abc; Path=/, better-auth.session_data=xyz; Path=/',
    );
  });

  test('returns HTTP errors instead of throwing', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (_, _) => ResponseBody.fromString(
          '{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid email or password"}',
          401,
          headers: <String, List<String>>{
            'content-type': <String>['application/json'],
          },
        ),
      );
    final (:data, :error) = await betterFetch<Object?>(
      'https://api.example.com/api/auth/sign-in/email',
      BetterFetchOption(customFetchImpl: dioFetch(dio)),
    );
    expect(data, isNull);
    expect(error?.status, 401);
    expect(error?.code, 'INVALID_EMAIL_OR_PASSWORD');
  });

  test('rejects when an already-cancelled signal is passed', () async {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter(
        (_, _) => ResponseBody.fromString('ok', 200),
      );
    final signal = CancelToken()..cancel();
    await expectLater(
      betterFetch<Object?>(
        'https://api.example.com/ok',
        BetterFetchOption(
          customFetchImpl: dioFetch(dio),
          retry: const RetryOptions.count(3),
          signal: signal,
        ),
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
  });
}
