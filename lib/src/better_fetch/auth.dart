import 'dart:async';
import 'dart:convert';

import 'package:re_better_auth/src/better_fetch/types.dart';

/// Resolves an auth value lazily, possibly asynchronously.
typedef AuthValue = FutureOr<String?> Function();

/// `authorization` header source: [Bearer], [Basic] or [Custom].
sealed class Auth {
  const Auth();
}

/// Sends `authorization: Bearer <token>`; nothing when the token is empty.
final class Bearer extends Auth {
  /// Creates a bearer source with a lazily resolved [token].
  const Bearer(this.token);

  /// Creates a bearer source with a fixed [value].
  Bearer.value(String value) : token = (() => value);

  /// Resolves the token for each request.
  final AuthValue token;
}

/// Sends `authorization: Basic base64(username:password)`.
final class Basic extends Auth {
  /// Creates a basic-auth source from lazily resolved credentials.
  const Basic({required this.username, required this.password});

  /// Resolves the username.
  final AuthValue username;

  /// Resolves the password.
  final AuthValue password;
}

/// Sends `authorization: <prefix> <value>`.
final class Custom extends Auth {
  /// Creates a custom source.
  const Custom({required this.prefix, required this.value});

  /// Resolves the scheme prefix, such as `Token`.
  final AuthValue prefix;

  /// Resolves the credential.
  final AuthValue value;
}

/// Builds the `authorization` header for `options.auth`, if any.
Future<Map<String, String>> getAuthHeader(BetterFetchOption? options) async {
  final headers = <String, String>{};
  final auth = options?.auth;
  switch (auth) {
    case null:
      break;
    case Bearer(:final token):
      final value = await token();
      if (value == null || value.isEmpty) return headers;
      headers['authorization'] = 'Bearer $value';
    case Basic(:final username, :final password):
      final user = await username();
      final pass = await password();
      if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
        return headers;
      }
      headers['authorization'] =
          'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
    case Custom(:final prefix, :final value):
      final resolvedPrefix = await prefix();
      final resolvedValue = await value();
      if (resolvedValue == null || resolvedValue.isEmpty) return headers;
      headers['authorization'] = '${resolvedPrefix ?? ''} $resolvedValue';
  }
  return headers;
}
