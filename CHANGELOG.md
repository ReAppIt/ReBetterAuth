## 0.3.0

- Tracks better-auth and `@better-auth/expo` 1.7.25, better-fetch 1.3.3 and
  `@convex-dev/better-auth` 0.13.0, the component's first Better Auth 1.7
  release.
- `linkSocial` with an `idToken` sends `expo-origin`, so the server's origin
  check accepts the session cookie it carries instead of failing with
  `MISSING_OR_NULL_ORIGIN`.
- The deferred session refresh (`POST /get-session`) sends a JSON `{}` body,
  for servers that reject a bodyless POST with 415.
- URLs: a path no longer replaces the base URL's host
  (`/https://other.example/x` stays under `baseURL`); relative paths that start
  with `http` or contain a colon resolve under `baseURL`; the base URL's query
  is kept, and a second `?` stays in the query.
- `authClient(path)` sends a body only for POST, PUT, PATCH and DELETE.
- `ConvexBetterAuthProvider`: a non-forced token request joins a refresh in
  flight instead of returning the cached token, and `isLoading` ends once the
  session loads.

## 0.2.0

- Adds `emailOtpClient()` (`package:re_better_auth/plugins.dart`), the client
  plugin for Better Auth's `emailOTP()` server plugin: typed methods for its
  routes, its error codes, and the session refresh upstream runs after an OTP
  sign-in, email verification or email-change request.

## 0.1.1

- The cached session is restored when `session.expiresAt` is epoch
  milliseconds, as the Convex adapter sends it; the typed date getters accept
  epoch milliseconds too.

## 0.1.0

- Initial release: a port of `@better-auth/expo` 1.7.7 (`flutterClient`,
  secure cookie storage, social sign-in through an auth session, session cache,
  `lastLoginMethodClient`) and the better-auth 1.7.7 core client it plugs into
  (`createAuthClient`, typed core routes, `useSession`), on a better-fetch 1.3.2
  port over Dio.
- The account routes (`getAccessToken`, `refreshToken`, `accountInfo`,
  `unlinkAccount`) also accept the Better Auth 1.6 fields, for 1.6 servers.
- Convex (`package:re_better_auth/convex.dart`): `convexClient()` and
  `ConvexBetterAuthProvider` from `@convex-dev/better-auth` 0.12.5;
  `useConvexAuth`, `Authenticated`, `Unauthenticated`, `AuthLoading` and
  `AuthRefreshing` from `convex` 1.46.0; and `ConvexTokenAuth` for Dart Convex
  clients that take a fixed token.
