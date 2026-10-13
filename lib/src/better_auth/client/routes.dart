import 'package:re_better_auth/src/better_auth/client/types.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_auth/utils/date.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';

/// `/sign-in/*` result: a redirect URL, or a session [token] and [user].
extension type SignInResponse(JsonMap json) {
  /// Whether the client should open [url].
  bool get redirect => json['redirect'] == true;

  /// Session token for direct sign-ins.
  String? get token => json['token'] as String?;

  /// Provider authorization URL for redirect sign-ins.
  String? get url => json['url'] as String?;

  /// The signed-in user, when returned.
  User? get user => switch (json['user']) {
    final JsonMap user => User(user),
    _ => null,
  };
}

/// Result with a session [token] and [user] (sign-up, change-password).
extension type AuthTokenResponse(JsonMap json) {
  /// Session token, or `null` when sign-up requires verification.
  String? get token => json['token'] as String?;

  /// The user.
  User? get user => switch (json['user']) {
    final JsonMap user => User(user),
    _ => null,
  };
}

/// `/sign-out` result, with a provider logout [url] when one applies.
extension type SignOutResponse(JsonMap json) {
  /// Whether sign-out succeeded.
  bool get success => json['success'] == true;

  /// Provider logout URL.
  String? get url => json['url'] as String?;

  /// Whether the client should open [url].
  bool get redirect => json['redirect'] == true;
}

/// `{status, message}` result of most mutating routes.
extension type StatusResponse(JsonMap json) {
  /// Whether the action succeeded.
  bool get status => json['status'] == true;

  /// Optional server message.
  String? get message => json['message'] as String?;

  /// Updated user, returned by `/verify-email`.
  User? get user => switch (json['user']) {
    final JsonMap user => User(user),
    _ => null,
  };
}

/// `/delete-user` result.
extension type DeleteUserResponse(JsonMap json) {
  /// Whether the request succeeded.
  bool get success => json['success'] == true;

  /// `User deleted` or `Verification email sent`.
  String? get message => json['message'] as String?;
}

/// `/link-social` result: a provider [url] to open, or [status] for ID tokens.
extension type LinkSocialResponse(JsonMap json) {
  /// Provider authorization URL.
  String? get url => json['url'] as String?;

  /// Whether the client should open [url].
  bool get redirect => json['redirect'] == true;

  /// Whether an ID-token link succeeded.
  bool get status => json['status'] == true;
}

/// `/update-session` result.
extension type UpdateSessionResponse(JsonMap json) {
  /// The updated session.
  Session? get session => switch (json['session']) {
    final JsonMap session => Session(session),
    _ => null,
  };
}

/// Provider tokens from `/get-access-token` and `/refresh-token`.
extension type OAuthTokens(JsonMap json) {
  /// Access token.
  String? get accessToken => json['accessToken'] as String?;

  /// Refresh token.
  String? get refreshToken => json['refreshToken'] as String?;

  /// Access token expiry.
  DateTime? get accessTokenExpiresAt => toDate(json['accessTokenExpiresAt']);

  /// Refresh token expiry.
  DateTime? get refreshTokenExpiresAt => toDate(json['refreshTokenExpiresAt']);

  /// OpenID ID token.
  String? get idToken => json['idToken'] as String?;

  /// Granted scopes.
  List<String> get scopes => <String>[
    for (final scope in json['scopes'] as List<Object?>? ?? const []) '$scope',
  ];
}

/// `/account-info` result: the provider's [user] profile and raw [data].
extension type AccountInfo(JsonMap json) {
  /// Normalized provider profile.
  JsonMap? get user => json['user'] as JsonMap?;

  /// Raw provider payload.
  JsonMap? get data => json['data'] as JsonMap?;
}

/// A provider ID token for native sign-in (`idToken` in the body).
class IdTokenCredential {
  /// Creates a credential from a provider-issued [token].
  const IdTokenCredential({
    required this.token,
    this.nonce,
    this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.user,
  });

  /// The ID token.
  final String token;

  /// Nonce used to request the token.
  final String? nonce;

  /// Provider access token.
  final String? accessToken;

  /// Provider refresh token.
  final String? refreshToken;

  /// Access token expiry in milliseconds since the epoch.
  final int? expiresAt;

  /// Name and email from the provider; only Apple sends them, once.
  final JsonMap? user;

  /// The credential as a request body field.
  JsonMap toJson() => <String, Object?>{
    'token': token,
    'nonce': ?nonce,
    'accessToken': ?accessToken,
    'refreshToken': ?refreshToken,
    'expiresAt': ?expiresAt,
    'user': ?user,
  };
}

BetterFetchResponse<R> _map<R>(
  BetterFetchResponse<JsonMap> res,
  R Function(JsonMap json) convert,
) {
  final data = res.data;
  return (data: data == null ? null : convert(data), error: res.error);
}

BetterFetchResponse<List<R>> _mapList<R>(
  BetterFetchResponse<List<Object?>> res,
  R Function(JsonMap json) convert,
) {
  final data = res.data;
  return (
    data: data == null
        ? null
        : <R>[for (final item in data) convert(item! as JsonMap)],
    error: res.error,
  );
}

/// Typed core endpoints, each mirroring its zod schema at better-auth v1.7.7.
/// The account routes also accept the v1.6 fields.
abstract class AuthRoutes {
  /// Calls any endpoint with the JS proxy semantics; see `callDynamicPath`.
  Future<BetterFetchResponse<T>> call<T>(
    String path, {
    Map<String, Object?>? body,
    Map<String, Object?>? query,
    ClientFetchOption? fetchOptions,
  });

  /// Plugin actions (nested maps of functions), read by typed extensions.
  Map<String, Object?> get pluginsActions;

  /// `/sign-in/*` endpoints.
  late final SignIn signIn = SignIn(this);

  /// `/sign-up/*` endpoints.
  late final SignUp signUp = SignUp(this);

  /// Signs out; with a provider logout configured it may return a redirect.
  Future<BetterFetchResponse<SignOutResponse>> signOut({
    String? callbackURL,
    bool? disableRedirect,
    String? state,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/sign-out',
      body: <String, Object?>{
        'callbackURL': ?callbackURL,
        'disableRedirect': ?disableRedirect,
        'state': ?state,
      },
      fetchOptions: fetchOptions,
    ),
    SignOutResponse.new,
  );

  /// Fetches the current session; `data` is `null` when signed out.
  Future<BetterFetchResponse<SessionData>> getSession({
    SessionQueryParams? query,
    ClientFetchOption? fetchOptions,
  }) async {
    final res = await call<Object?>(
      '/get-session',
      query: query?.toQuery(),
      fetchOptions: fetchOptions,
    );
    final data = res.data;
    return (data: data is JsonMap ? SessionData(data) : null, error: res.error);
  }

  /// Lists the user's active sessions.
  Future<BetterFetchResponse<List<Session>>> listSessions({
    ClientFetchOption? fetchOptions,
  }) async => _mapList(
    await call<List<Object?>>('/list-sessions', fetchOptions: fetchOptions),
    Session.new,
  );

  /// Revokes the session with [token].
  Future<BetterFetchResponse<StatusResponse>> revokeSession({
    required String token,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/revoke-session',
      body: <String, Object?>{'token': token},
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Revokes every session of the user.
  Future<BetterFetchResponse<StatusResponse>> revokeSessions({
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>('/revoke-sessions', fetchOptions: fetchOptions),
    StatusResponse.new,
  );

  /// Revokes every session except the current one.
  Future<BetterFetchResponse<StatusResponse>> revokeOtherSessions({
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>('/revoke-other-sessions', fetchOptions: fetchOptions),
    StatusResponse.new,
  );

  /// Updates the user's [name], [image] and any [additionalFields].
  Future<BetterFetchResponse<StatusResponse>> updateUser({
    String? name,
    String? image,
    Map<String, Object?>? additionalFields,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/update-user',
      body: <String, Object?>{
        ...?additionalFields,
        'name': ?name,
        'image': ?image,
      },
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Updates additional fields of the current session.
  Future<BetterFetchResponse<UpdateSessionResponse>> updateSession({
    Map<String, Object?>? additionalFields,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/update-session',
      body: <String, Object?>{...?additionalFields},
      fetchOptions: fetchOptions,
    ),
    UpdateSessionResponse.new,
  );

  /// Starts an email change to [newEmail].
  Future<BetterFetchResponse<StatusResponse>> changeEmail({
    required String newEmail,
    String? callbackURL,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/change-email',
      body: <String, Object?>{
        'newEmail': newEmail,
        'callbackURL': ?callbackURL,
      },
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Changes the password; returns a new token when sessions are revoked.
  Future<BetterFetchResponse<AuthTokenResponse>> changePassword({
    required String newPassword,
    required String currentPassword,
    bool? revokeOtherSessions,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/change-password',
      body: <String, Object?>{
        'newPassword': newPassword,
        'currentPassword': currentPassword,
        'revokeOtherSessions': ?revokeOtherSessions,
      },
      fetchOptions: fetchOptions,
    ),
    AuthTokenResponse.new,
  );

  /// Deletes the user, or emails a confirmation when the server requires one.
  Future<BetterFetchResponse<DeleteUserResponse>> deleteUser({
    String? callbackURL,
    String? password,
    String? token,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/delete-user',
      body: <String, Object?>{
        'callbackURL': ?callbackURL,
        'password': ?password,
        'token': ?token,
      },
      fetchOptions: fetchOptions,
    ),
    DeleteUserResponse.new,
  );

  /// Confirms a deletion requested by email.
  Future<BetterFetchResponse<DeleteUserResponse>> deleteUserCallback({
    required String token,
    String? callbackURL,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/delete-user/callback',
      query: <String, Object?>{'token': token, 'callbackURL': ?callbackURL},
      fetchOptions: fetchOptions,
    ),
    DeleteUserResponse.new,
  );

  /// Emails a password-reset link that redirects to [redirectTo].
  Future<BetterFetchResponse<StatusResponse>> requestPasswordReset({
    required String email,
    String? redirectTo,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/request-password-reset',
      body: <String, Object?>{'email': email, 'redirectTo': ?redirectTo},
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Sets [newPassword] using the reset [token].
  Future<BetterFetchResponse<StatusResponse>> resetPassword({
    required String newPassword,
    String? token,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/reset-password',
      body: <String, Object?>{'newPassword': newPassword, 'token': ?token},
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Sends a verification email to [email].
  Future<BetterFetchResponse<StatusResponse>> sendVerificationEmail({
    required String email,
    String? callbackURL,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/send-verification-email',
      body: <String, Object?>{'email': email, 'callbackURL': ?callbackURL},
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Verifies an email with the emailed [token].
  Future<BetterFetchResponse<StatusResponse>> verifyEmail({
    required String token,
    String? callbackURL,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/verify-email',
      query: <String, Object?>{'token': token, 'callbackURL': ?callbackURL},
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Links a social account; a redirect result opens the provider.
  Future<BetterFetchResponse<LinkSocialResponse>> linkSocial({
    required String provider,
    String? callbackURL,
    IdTokenCredential? idToken,
    bool? requestSignUp,
    List<String>? scopes,
    String? errorCallbackURL,
    bool? disableRedirect,
    String? loginHint,
    Map<String, String>? additionalParams,
    Map<String, Object?>? additionalData,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/link-social',
      body: <String, Object?>{
        'provider': provider,
        'callbackURL': ?callbackURL,
        'idToken': ?idToken?.toJson(),
        'requestSignUp': ?requestSignUp,
        'scopes': ?scopes,
        'errorCallbackURL': ?errorCallbackURL,
        'disableRedirect': ?disableRedirect,
        'loginHint': ?loginHint,
        'additionalParams': ?additionalParams,
        'additionalData': ?additionalData,
      },
      fetchOptions: fetchOptions,
    ),
    LinkSocialResponse.new,
  );

  /// Lists the user's linked accounts.
  Future<BetterFetchResponse<List<Account>>> listAccounts({
    ClientFetchOption? fetchOptions,
  }) async => _mapList(
    await call<List<Object?>>('/list-accounts', fetchOptions: fetchOptions),
    Account.new,
  );

  /// Unlinks an account. Better Auth 1.6 takes [providerId] (and the
  /// provider's account id); 1.7+ takes [Account.id] as [accountId].
  Future<BetterFetchResponse<StatusResponse>> unlinkAccount({
    String? providerId,
    String? accountId,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/unlink-account',
      body: <String, Object?>{
        'providerId': ?providerId,
        'accountId': ?accountId,
      },
      fetchOptions: fetchOptions,
    ),
    StatusResponse.new,
  );

  /// Returns a valid provider access token, refreshing it when needed.
  /// Better Auth 1.6 takes [providerId] (and the provider's account id);
  /// 1.7+ takes [Account.id] as [accountId], or [useAccountCookie].
  Future<BetterFetchResponse<OAuthTokens>> getAccessToken({
    String? providerId,
    String? accountId,
    bool useAccountCookie = false,
    String? userId,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/get-access-token',
      body: <String, Object?>{
        'providerId': ?providerId,
        'accountId': ?accountId,
        if (useAccountCookie) 'useAccountCookie': true,
        'userId': ?userId,
      },
      fetchOptions: fetchOptions,
    ),
    OAuthTokens.new,
  );

  /// Refreshes the provider tokens; selects the account as [getAccessToken].
  Future<BetterFetchResponse<OAuthTokens>> refreshToken({
    String? providerId,
    String? accountId,
    bool useAccountCookie = false,
    String? userId,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/refresh-token',
      body: <String, Object?>{
        'providerId': ?providerId,
        'accountId': ?accountId,
        if (useAccountCookie) 'useAccountCookie': true,
        'userId': ?userId,
      },
      fetchOptions: fetchOptions,
    ),
    OAuthTokens.new,
  );

  /// Returns an account's provider profile. Better Auth 1.6 takes the
  /// provider's [accountId] ([providerId] disambiguates) or falls back to the
  /// account cookie; 1.7+ selects the account as [getAccessToken].
  Future<BetterFetchResponse<AccountInfo>> accountInfo({
    String? providerId,
    String? accountId,
    bool useAccountCookie = false,
    String? userId,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await call<JsonMap>(
      '/account-info',
      query: <String, Object?>{
        'providerId': ?providerId,
        'accountId': ?accountId,
        if (useAccountCookie) 'useAccountCookie': true,
        'userId': ?userId,
      },
      fetchOptions: fetchOptions,
    ),
    AccountInfo.new,
  );
}

/// `/sign-in/*` endpoints; plugins add more through extensions.
class SignIn {
  /// Creates the namespace for [client].
  SignIn(this.client);

  /// The client this namespace calls through.
  final AuthRoutes client;

  /// Signs in with email and password.
  Future<BetterFetchResponse<SignInResponse>> email({
    required String email,
    required String password,
    String? callbackURL,
    bool? rememberMe,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/sign-in/email',
      body: <String, Object?>{
        'email': email,
        'password': password,
        'callbackURL': ?callbackURL,
        'rememberMe': ?rememberMe,
      },
      fetchOptions: fetchOptions,
    ),
    SignInResponse.new,
  );

  /// Signs in with a provider: a browser flow, or native with [idToken].
  Future<BetterFetchResponse<SignInResponse>> social({
    required String provider,
    String? callbackURL,
    String? newUserCallbackURL,
    String? errorCallbackURL,
    bool? disableRedirect,
    IdTokenCredential? idToken,
    List<String>? scopes,
    bool? requestSignUp,
    String? loginHint,
    Map<String, String>? additionalParams,
    Map<String, Object?>? additionalData,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/sign-in/social',
      body: <String, Object?>{
        'provider': provider,
        'callbackURL': ?callbackURL,
        'newUserCallbackURL': ?newUserCallbackURL,
        'errorCallbackURL': ?errorCallbackURL,
        'disableRedirect': ?disableRedirect,
        'idToken': ?idToken?.toJson(),
        'scopes': ?scopes,
        'requestSignUp': ?requestSignUp,
        'loginHint': ?loginHint,
        'additionalParams': ?additionalParams,
        'additionalData': ?additionalData,
      },
      fetchOptions: fetchOptions,
    ),
    SignInResponse.new,
  );
}

/// `/sign-up/*` endpoints; plugins add more through extensions.
class SignUp {
  /// Creates the namespace for [client].
  SignUp(this.client);

  /// The client this namespace calls through.
  final AuthRoutes client;

  /// Creates an account; [additionalFields] carries custom user fields.
  Future<BetterFetchResponse<AuthTokenResponse>> email({
    required String name,
    required String email,
    required String password,
    String? image,
    String? callbackURL,
    bool? rememberMe,
    Map<String, Object?>? additionalFields,
    ClientFetchOption? fetchOptions,
  }) async => _map(
    await client.call<JsonMap>(
      '/sign-up/email',
      body: <String, Object?>{
        ...?additionalFields,
        'name': name,
        'email': email,
        'password': password,
        'image': ?image,
        'callbackURL': ?callbackURL,
        'rememberMe': ?rememberMe,
      },
      fetchOptions: fetchOptions,
    ),
    AuthTokenResponse.new,
  );
}
