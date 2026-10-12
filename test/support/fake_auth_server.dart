import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:re_better_auth/re_better_auth.dart';

import 'fakes.dart';

const String googleAuthorizationURL =
    'https://accounts.google.com/o/oauth2/v2/auth?client_id=test&state=state-123';

/// Plays a better-auth server with the `expo()` plugin for the client tests.
class FakeAuthServer {
  FakeAuthServer({
    this.cookieCache = false,
    this.cookieStateStrategy = false,
    this.userFields = const <String, Object?>{},
    this.sessionFields = const <String, Object?>{},
  });

  final bool cookieCache;
  final bool cookieStateStrategy;
  final Map<String, Object?> userFields;
  final Map<String, Object?> sessionFields;
  final List<RecordedRequest> requests = <RecordedRequest>[];
  String token = 'session-token-1.signature';
  bool sessionValid = true;

  /// Re-issues `session_data` on the next `/get-session`, like an expired cache.
  bool rotateSessionData = false;

  late final FakeFetch fetch = FakeFetch(handle);

  Map<String, Object?> get user => <String, Object?>{
    'id': 'user-1',
    'name': 'Test User',
    'email': 'test@test.com',
    'emailVerified': false,
    'image': null,
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
    ...userFields,
  };

  Map<String, Object?> get session => <String, Object?>{
    'id': 'session-1',
    'userId': 'user-1',
    'token': token.split('.').first,
    'expiresAt': DateTime.now()
        .toUtc()
        .add(const Duration(days: 7))
        .toIso8601String(),
    'createdAt': '2026-01-01T00:00:00.000Z',
    'updatedAt': '2026-01-01T00:00:00.000Z',
    ...sessionFields,
  };

  List<String> sessionCookies() => <String>[
    'better-auth.session_token=$token; Max-Age=604800; Path=/; HttpOnly; SameSite=Lax',
    if (cookieCache)
      'better-auth.session_data=cached-${DateTime.now().microsecondsSinceEpoch}; Max-Age=300; Path=/; HttpOnly; SameSite=Lax',
  ];

  bool hasSessionCookie(RecordedRequest request) =>
      (request.headers['cookie'] ?? '').contains(
        'better-auth.session_token=$token',
      );

  FetchResponse handle(RecordedRequest request) {
    requests.add(request);
    final path = request.uri.path.replaceFirst('/api/auth', '');
    final body = request.json ?? const <String, Object?>{};
    switch (path) {
      case '/sign-in/email':
      case '/sign-up/email':
        return jsonResponse(
          <String, Object?>{'redirect': false, 'token': token, 'user': user},
          headers: <String, List<String>>{'set-cookie': sessionCookies()},
        );
      case '/get-session':
        if (!sessionValid || !hasSessionCookie(request)) {
          return jsonResponse(null);
        }
        final rotate = cookieCache && rotateSessionData;
        rotateSessionData = false;
        return jsonResponse(
          <String, Object?>{'session': session, 'user': user},
          headers: rotate
              ? <String, List<String>>{
                  'set-cookie': sessionCookies().sublist(1),
                }
              : const <String, List<String>>{},
        );
      case '/sign-in/social':
      case '/link-social':
        if (body.containsKey('idToken')) {
          return jsonResponse(
            <String, Object?>{'redirect': false, 'token': token, 'user': user},
            headers: <String, List<String>>{'set-cookie': sessionCookies()},
          );
        }
        return jsonResponse(
          <String, Object?>{'url': googleAuthorizationURL, 'redirect': true},
          headers: cookieStateStrategy
              ? <String, List<String>>{
                  'set-cookie': <String>[
                    'better-auth.oauth_state=oauth-state-value; Max-Age=600; Path=/; HttpOnly',
                  ],
                }
              : const <String, List<String>>{},
        );
      case '/sign-out':
        return jsonResponse(
          <String, Object?>{'success': true},
          headers: <String, List<String>>{
            'set-cookie': <String>[
              'better-auth.session_token=; Max-Age=0; Path=/',
              'better-auth.session_data=; Max-Age=0; Path=/',
            ],
          },
        );
    }
    return jsonResponse(<String, Object?>{}, status: 404);
  }
}

/// Stands in for `FlutterWebAuth2.authenticate` and records each call.
class FakeBrowser {
  final List<
    ({String url, String callbackUrlScheme, FlutterWebAuth2Options options})
  >
  calls =
      <
        ({String url, String callbackUrlScheme, FlutterWebAuth2Options options})
      >[];

  /// Result for the next call only; falls back to [defaultResult].
  Future<String> Function(String url)? next;

  String defaultResult =
      'better-auth://?cookie=better-auth.session_token=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjYxMzQwZj';

  Future<String> call({
    required String url,
    required String callbackUrlScheme,
    required FlutterWebAuth2Options options,
  }) async {
    calls.add((
      url: url,
      callbackUrlScheme: callbackUrlScheme,
      options: options,
    ));
    final handler = next;
    next = null;
    if (handler != null) return handler(url);
    return defaultResult;
  }
}
