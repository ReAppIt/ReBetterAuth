import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/plugins.dart';
import 'package:re_better_auth/vanilla.dart';

import '../support/fake_auth_server.dart';
import '../support/fakes.dart';

void main() {
  setUp(resetGlobals);

  group('last-login-method expo', () {
    AuthClient makeClient(LastLoginMethodClientPlugin plugin) =>
        createAuthClient(
          baseURL: 'http://localhost:3000',
          plugins: [plugin],
          fetchOptions: ClientFetchOption(
            customFetchImpl: FakeAuthServer().fetch.call,
          ),
        );

    test('should resolve the email method and allow clearing it', () async {
      final storage = MemoryStorage();
      final client = makeClient(lastLoginMethodClient(storage: storage));

      await client.signIn.email(email: 'test@test.com', password: 'password');
      expect(await client.getLastUsedLoginMethod(), 'email');
      expect(await client.isLastUsedLoginMethod('email'), isTrue);

      await client.clearLastUsedLoginMethod();
      expect(await client.getLastUsedLoginMethod(), isNull);
    });

    test('should allow custom provider tracking', () async {
      final storage = MemoryStorage();
      final client = makeClient(
        lastLoginMethodClient(
          storage: storage,
          customResolveMethod: (_) => 'custom',
        ),
      );
      await client.signIn.email(email: 'test@test.com', password: 'password');
      expect(await client.getLastUsedLoginMethod(), 'custom');
    });

    test('should allow a custom storage prefix', () async {
      final storage = MemoryStorage();
      final client = makeClient(
        lastLoginMethodClient(storage: storage, storagePrefix: 'myapp'),
      );
      await client.signIn.email(email: 'test@test.com', password: 'password');
      expect(storage.map['myapp_last_login_method'], 'email');
    });

    test('resolves social callbacks and ignores other paths', () async {
      final storage = MemoryStorage();
      final plugin = lastLoginMethodClient(storage: storage);
      expect(await plugin.resolveMethod('/api/auth/callback/google'), 'google');
      expect(
        await plugin.resolveMethod('/api/auth/passkey/verify-authentication'),
        'passkey',
      );
      expect(await plugin.resolveMethod('/api/auth/get-session'), isNull);
    });
  });
}
