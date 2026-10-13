import 'package:re_better_auth/src/better_auth/client/routes.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/error_codes.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/version.dart';

/// Error codes of the server's `emailOTP()` plugin (`EMAIL_OTP_ERROR_CODES`).
final Map<String, RawError> emailOtpErrorCodes = defineErrorCodes(const {
  'OTP_EXPIRED': 'OTP expired',
  'INVALID_OTP': 'Invalid OTP',
  'TOO_MANY_ATTEMPTS': 'Too many attempts',
});

/// What an OTP is for: the `type` the OTP routes take.
enum EmailOtpType {
  /// Verifies the address.
  emailVerification('email-verification'),

  /// Signs in.
  signIn('sign-in'),

  /// Resets the password.
  forgetPassword('forget-password'),

  /// Changes the address.
  changeEmail('change-email');

  const EmailOtpType(this.value);

  /// The value sent to the server.
  final String value;
}

/// `{success}` result of the OTP routes that only send or check a code.
extension type SuccessResponse(JsonMap json) {
  /// Whether the request succeeded.
  bool get success => json['success'] == true;
}

/// `/email-otp/verify-email` result; [token] is set only when the server
/// signs the user in after verification.
extension type VerifyEmailOtpResponse(JsonMap json) {
  /// Whether the address is verified.
  bool get status => json['status'] == true;

  /// Session token, or `null` without `autoSignInAfterVerification`.
  String? get token => json['token'] as String?;

  /// The verified user.
  User? get user => switch (json['user']) {
    final JsonMap user => User(user),
    _ => null,
  };
}

const Set<String> _sessionSignalPaths = <String>{
  '/email-otp/verify-email',
  '/sign-in/email-otp',
  '/email-otp/request-email-change',
};

bool _matchesSessionSignal(String path) => _sessionSignalPaths.contains(path);

/// Client side of the server's `emailOTP()` plugin; see [emailOtpClient].
class EmailOtpClientPlugin extends BetterAuthClientPlugin {
  /// Creates the plugin.
  const EmailOtpClientPlugin();

  @override
  String get id => 'email-otp';

  @override
  String get version => packageVersion;

  @override
  List<ClientAtomListener> get atomListeners => const <ClientAtomListener>[
    ClientAtomListener(
      matcher: _matchesSessionSignal,
      signal: r'$sessionSignal',
    ),
  ];

  @override
  Map<String, RawError> get errorCodes => emailOtpErrorCodes;
}

/// The client plugin for Better Auth's server `emailOTP()` plugin
/// (`emailOTPClient`); its endpoints are on `authClient.emailOtp` and
/// `authClient.signIn.emailOtp`.
EmailOtpClientPlugin emailOtpClient() => const EmailOtpClientPlugin();

BetterFetchResponse<R> _map<R>(
  BetterFetchResponse<JsonMap> res,
  R Function(JsonMap json) convert,
) {
  final data = res.data;
  return (data: data == null ? null : convert(data), error: res.error);
}

/// `/email-otp/*` endpoints of the server's `emailOTP()` plugin.
class EmailOtpRoutes {
  /// Creates the namespace for [client].
  const EmailOtpRoutes(this.client);

  /// The client this namespace calls through.
  final AuthRoutes client;

  /// Emails an OTP of [type] to [email].
  Future<BetterFetchResponse<SuccessResponse>> sendVerificationOtp({
    required String email,
    required EmailOtpType type,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/send-verification-otp',
      body: <String, Object?>{'email': email, 'type': type.value},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );

  /// Checks [otp] without using it up; a wrong code counts as an attempt.
  Future<BetterFetchResponse<SuccessResponse>> checkVerificationOtp({
    required String email,
    required EmailOtpType type,
    required String otp,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/check-verification-otp',
      body: <String, Object?>{'email': email, 'type': type.value, 'otp': otp},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );

  /// Verifies [email] with its [otp].
  Future<BetterFetchResponse<VerifyEmailOtpResponse>> verifyEmail({
    required String email,
    required String otp,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/verify-email',
      body: <String, Object?>{'email': email, 'otp': otp},
      fetchOptions: fetchOptions,
    ),
    VerifyEmailOtpResponse.new,
  );

  /// Emails a password-reset OTP to [email]; succeeds for unknown addresses
  /// too, without sending anything.
  Future<BetterFetchResponse<SuccessResponse>> requestPasswordReset({
    required String email,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/request-password-reset',
      body: <String, Object?>{'email': email},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );

  /// Sets [password] for [email] with its password-reset [otp].
  Future<BetterFetchResponse<SuccessResponse>> resetPassword({
    required String email,
    required String otp,
    required String password,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/reset-password',
      body: <String, Object?>{'email': email, 'otp': otp, 'password': password},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );

  /// Emails an OTP to [newEmail]; needs a fresh session. [otp] is the current
  /// address's code when the server sets `changeEmail.verifyCurrentEmail`.
  Future<BetterFetchResponse<SuccessResponse>> requestEmailChange({
    required String newEmail,
    String? otp,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/request-email-change',
      body: <String, Object?>{'newEmail': newEmail, 'otp': ?otp},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );

  /// Changes the address to [newEmail] with the [otp] sent there; needs a
  /// fresh session.
  Future<BetterFetchResponse<SuccessResponse>> changeEmail({
    required String newEmail,
    required String otp,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/email-otp/change-email',
      body: <String, Object?>{'newEmail': newEmail, 'otp': otp},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );
}

/// `/forget-password/email-otp`, the server's older password-reset route.
class ForgetPasswordRoutes {
  /// Creates the namespace for [client].
  const ForgetPasswordRoutes(this.client);

  /// The client this namespace calls through.
  final AuthRoutes client;

  /// Emails a password-reset OTP to [email].
  @Deprecated(
    'Use emailOtp.requestPasswordReset; the server drops this route in its '
    'next major version.',
  )
  Future<BetterFetchResponse<SuccessResponse>> emailOtp({
    required String email,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/forget-password/email-otp',
      body: <String, Object?>{'email': email},
      fetchOptions: fetchOptions,
    ),
    SuccessResponse.new,
  );
}

/// Typed access to the server's `emailOTP()` plugin.
extension EmailOtpAuthRoutes on AuthRoutes {
  /// `/email-otp/*` endpoints.
  EmailOtpRoutes get emailOtp => EmailOtpRoutes(this);

  /// `/forget-password/email-otp`.
  ForgetPasswordRoutes get forgetPassword => ForgetPasswordRoutes(this);
}

/// `/sign-in/email-otp`.
extension EmailOtpSignIn on SignIn {
  /// Signs in with [email] and its sign-in [otp]. An unknown address becomes
  /// a new user with [name], [image] and [additionalFields], unless the
  /// server sets `disableSignUp`.
  Future<BetterFetchResponse<SignInResponse>> emailOtp({
    required String email,
    required String otp,
    String? name,
    String? image,
    Map<String, Object?>? additionalFields,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/sign-in/email-otp',
      body: <String, Object?>{
        ...?additionalFields,
        'email': email,
        'otp': otp,
        'name': ?name,
        'image': ?image,
      },
      fetchOptions: fetchOptions,
    ),
    SignInResponse.new,
  );
}
