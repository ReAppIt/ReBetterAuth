import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/vanilla.dart';

import '../../support/fakes.dart';
import '../../support/test_plugin.dart';

void main() {
  setUp(resetGlobals);

  group('url', () {
    FetchEsque echoUrl() => FakeFetch(
      (request) => jsonResponse(<String, Object?>{'url': '${request.url}'}),
    ).call;

    test('should not require base url', () async {
      final client = createAuthClient(
        plugins: [TestClientPlugin()],
        baseURL: '',
        fetchOptions: ClientFetchOption(
          customFetchImpl: FakeFetch(
            (_) => jsonResponse(<String, Object?>{'hello': 'world'}),
          ).call,
        ),
      );
      final response = await client<Object?>('/test');
      expect(response.data, {'hello': 'world'});
    });

    test('should use base url and append `/api/auth` by default', () async {
      final client = createAuthClient(
        plugins: [TestClientPlugin()],
        baseURL: 'http://localhost:3000',
        fetchOptions: ClientFetchOption(customFetchImpl: echoUrl()),
      );
      final response = await client<Object?>('/test');
      expect(response.data, {'url': 'http://localhost:3000/api/auth/test'});
    });

    test('should use base url and use the provided path', () async {
      final client = createAuthClient(
        plugins: [TestClientPlugin()],
        baseURL: 'http://localhost:3000/auth',
        fetchOptions: ClientFetchOption(customFetchImpl: echoUrl()),
      );
      final response = await client<Object?>('/test');
      expect(response.data, {'url': 'http://localhost:3000/auth/test'});
    });

    test('should be able to detect `/` in the base url', () async {
      final client = createAuthClient(
        plugins: [TestClientPlugin()],
        baseURL: 'http://localhost:3000',
        basePath: '/',
        fetchOptions: ClientFetchOption(customFetchImpl: echoUrl()),
      );
      final response = await client<Object?>('/test');
      expect(response.data, {'url': 'http://localhost:3000/test'});
    });

    test('rejects a base url without http(s)', () {
      expect(
        () => createAuthClient(baseURL: 'myapp://host'),
        throwsA(isA<BetterAuthError>()),
      );
    });
  });
}
