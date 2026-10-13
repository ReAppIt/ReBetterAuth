import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/plugins.dart';
import 'package:re_better_auth/vanilla.dart';

import '../../support/fakes.dart';

AuthClient _client(FakeFetch fake) => createAuthClient(
  baseURL: 'http://localhost:3000',
  plugins: [emailOtpClient()],
  fetchOptions: ClientFetchOption(customFetchImpl: fake.call),
);

void main() {
  setUp(resetGlobals);
  tearDown(resetGlobals);

  test('emailOtpClient has the upstream id and error codes', () {
    expect(emailOtpClient().id, 'email-otp');
    final client = createAuthClient(plugins: [emailOtpClient()]);
    expect(client.$errorCodes['INVALID_OTP']?.message, 'Invalid OTP');
    expect(client.$errorCodes['OTP_EXPIRED']?.message, 'OTP expired');
    expect(
      client.$errorCodes['TOO_MANY_ATTEMPTS']?.message,
      'Too many attempts',
    );
  });

  test('sends the documented paths and bodies', () async {
    final fake = FakeFetch(
      (_) => jsonResponse(<String, Object?>{'success': true}),
    );
    final client = _client(fake);
    await client.emailOtp.sendVerificationOtp(
      email: 'a@b.c',
      type: EmailOtpType.signIn,
    );
    await client.emailOtp.checkVerificationOtp(
      email: 'a@b.c',
      type: EmailOtpType.forgetPassword,
      otp: '111111',
    );
    await client.emailOtp.verifyEmail(email: 'a@b.c', otp: '222222');
    await client.signIn.emailOtp(
      email: 'a@b.c',
      otp: '333333',
      name: 'Ada',
      additionalFields: <String, Object?>{'locale': 'en'},
    );
    await client.emailOtp.requestPasswordReset(email: 'a@b.c');
    // ignore: deprecated_member_use_from_same_package
    await client.forgetPassword.emailOtp(email: 'a@b.c');
    await client.emailOtp.resetPassword(
      email: 'a@b.c',
      otp: '444444',
      password: 'new-password',
    );
    await client.emailOtp.requestEmailChange(newEmail: 'n@b.c');
    await client.emailOtp.changeEmail(newEmail: 'n@b.c', otp: '555555');

    expect(
      <String>[for (final r in fake.requests) '${r.method} ${r.uri.path}'],
      [
        'POST /api/auth/email-otp/send-verification-otp',
        'POST /api/auth/email-otp/check-verification-otp',
        'POST /api/auth/email-otp/verify-email',
        'POST /api/auth/sign-in/email-otp',
        'POST /api/auth/email-otp/request-password-reset',
        'POST /api/auth/forget-password/email-otp',
        'POST /api/auth/email-otp/reset-password',
        'POST /api/auth/email-otp/request-email-change',
        'POST /api/auth/email-otp/change-email',
      ],
    );
    expect(
      <Object?>[for (final r in fake.requests) r.json],
      [
        {'email': 'a@b.c', 'type': 'sign-in'},
        {'email': 'a@b.c', 'type': 'forget-password', 'otp': '111111'},
        {'email': 'a@b.c', 'otp': '222222'},
        {'locale': 'en', 'email': 'a@b.c', 'otp': '333333', 'name': 'Ada'},
        {'email': 'a@b.c'},
        {'email': 'a@b.c'},
        {'email': 'a@b.c', 'otp': '444444', 'password': 'new-password'},
        {'newEmail': 'n@b.c'},
        {'newEmail': 'n@b.c', 'otp': '555555'},
      ],
    );
  });

  test('refetches the session after the routes upstream listens to', () {
    fakeAsync((async) {
      final client = _client(
        FakeFetch((_) => jsonResponse(<String, Object?>{'success': true})),
      );
      var flips = 0;
      client.$store.atoms[r'$sessionSignal']!.listen((_, _) => flips++);
      final flipped = <String>[];
      void run(String name, Future<Object?> Function() request) {
        final before = flips;
        request().ignore();
        async.elapse(const Duration(milliseconds: 100));
        if (flips > before) flipped.add(name);
      }

      run(
        'sendVerificationOtp',
        () => client.emailOtp.sendVerificationOtp(
          email: 'a@b.c',
          type: EmailOtpType.emailVerification,
        ),
      );
      run(
        'verifyEmail',
        () => client.emailOtp.verifyEmail(email: 'a@b.c', otp: '1'),
      );
      run('signIn', () => client.signIn.emailOtp(email: 'a@b.c', otp: '1'));
      run(
        'requestPasswordReset',
        () => client.emailOtp.requestPasswordReset(email: 'a@b.c'),
      );
      run(
        'resetPassword',
        () => client.emailOtp.resetPassword(
          email: 'a@b.c',
          otp: '1',
          password: 'pw',
        ),
      );
      run(
        'requestEmailChange',
        () => client.emailOtp.requestEmailChange(newEmail: 'n@b.c'),
      );
      run(
        'changeEmail',
        () => client.emailOtp.changeEmail(newEmail: 'n@b.c', otp: '1'),
      );

      expect(flipped, ['verifyEmail', 'signIn', 'requestEmailChange']);
    });
  });

  test('a rejected code returns its error and leaves the session alone', () {
    fakeAsync((async) {
      final client = _client(
        FakeFetch(
          (_) => jsonResponse(<String, Object?>{
            'code': 'INVALID_OTP',
            'message': 'Invalid OTP',
          }, status: 400),
        ),
      );
      var flips = 0;
      client.$store.atoms[r'$sessionSignal']!.listen((_, _) => flips++);
      BetterFetchResponse<SignInResponse>? res;
      client.signIn
          .emailOtp(email: 'a@b.c', otp: '000000')
          .then((value) => res = value);
      async.elapse(const Duration(milliseconds: 100));

      expect(res?.error?.status, 400);
      expect(res?.error?.code, emailOtpErrorCodes['INVALID_OTP']?.code);
      expect(flips, 0);
    });
  });

  test('wraps responses in typed views', () async {
    final client = _client(
      FakeFetch((request) {
        final path = request.uri.path;
        if (path.endsWith('/sign-in/email-otp')) {
          return jsonResponse(<String, Object?>{
            'token': 'tok',
            'user': <String, Object?>{'id': 'u1', 'email': 'a@b.c'},
          });
        }
        if (path.endsWith('/email-otp/verify-email')) {
          return jsonResponse(<String, Object?>{
            'status': true,
            'token': null,
            'user': <String, Object?>{'id': 'u1', 'emailVerified': true},
          });
        }
        return jsonResponse(<String, Object?>{'success': true});
      }),
    );

    final signIn = await client.signIn.emailOtp(email: 'a@b.c', otp: '1');
    expect(signIn.data?.token, 'tok');
    expect(signIn.data?.user?.email, 'a@b.c');

    final verified = await client.emailOtp.verifyEmail(
      email: 'a@b.c',
      otp: '1',
    );
    expect(verified.data?.status, isTrue);
    expect(verified.data?.token, isNull);
    expect(verified.data?.user?.emailVerified, isTrue);

    final sent = await client.emailOtp.requestPasswordReset(email: 'a@b.c');
    expect(sent.data?.success, isTrue);
  });
}
