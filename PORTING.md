# Porting notes

`re_better_auth` is a port, so reviewing it means comparing each Dart file with
its upstream source. This file is the map.

## Upstream pins

| Project | Version | Source |
|---|---|---|
| `@better-auth/expo` | 1.7.7 | [`packages/expo`](https://github.com/better-auth/better-auth/tree/v1.7.7/packages/expo) |
| `better-auth` client | 1.7.7 | [`packages/better-auth/src/client`](https://github.com/better-auth/better-auth/tree/v1.7.7/packages/better-auth/src/client) |
| `@better-auth/core` | 1.7.7 | [`packages/core/src`](https://github.com/better-auth/better-auth/tree/v1.7.7/packages/core/src) |
| `@better-fetch/fetch` | 1.3.2 | [`packages/better-fetch/src`](https://github.com/better-auth/better-fetch/tree/v1.3.2/packages/better-fetch/src) |
| `nanostores` | 1.3.0 | [`atom`, `lifecycle`](https://github.com/nanostores/nanostores/tree/1.3.0) |
| `@convex-dev/better-auth` | 0.12.5 | [`src`](https://github.com/get-convex/better-auth/tree/v0.12.5/src) |
| `convex` | 1.46.0 | [`src`](https://github.com/get-convex/convex-js/tree/npm/1.46.0/src) |

## File map

| Dart | Upstream |
|---|---|
| `lib/src/client.dart` | `expo/src/client.ts` |
| `lib/src/client_storage.dart` | `expo/src/client-storage.ts` |
| `lib/src/focus_manager.dart` | `expo/src/focus-manager.ts` |
| `lib/src/online_manager.dart` | `expo/src/online-manager.ts` |
| `lib/src/version.dart` | `expo/src/version.ts` |
| `lib/src/plugins/last_login_method.dart` | `expo/src/plugins/last-login-method.ts` |
| `lib/src/better_auth/client/vanilla.dart` | `better-auth/src/client/vanilla.ts` |
| `lib/src/better_auth/client/flutter/index.dart` | `better-auth/src/client/react/index.ts` |
| `lib/src/better_auth/client/flutter/flutter_store.dart` | `better-auth/src/client/react/react-store.ts` |
| `lib/src/better_auth/client/config.dart` | `better-auth/src/client/config.ts` |
| `lib/src/better_auth/client/proxy.dart` | `better-auth/src/client/proxy.ts` |
| `lib/src/better_auth/client/routes.dart` | route types inferred via `path-to-object.ts` from `better-auth/src/api/routes/*.ts` |
| `lib/src/better_auth/client/query.dart` | `better-auth/src/client/query.ts`, `query-atom.ts` |
| `lib/src/better_auth/client/session_atom.dart` | `better-auth/src/client/session-atom.ts` |
| `lib/src/better_auth/client/session_refresh.dart` | `better-auth/src/client/session-refresh.ts` |
| `lib/src/better_auth/client/equality.dart` | `better-auth/src/client/equality.ts` |
| `lib/src/better_auth/client/parser.dart` | `better-auth/src/client/parser.ts` |
| `lib/src/better_auth/client/focus_manager.dart` | `better-auth/src/client/focus-manager.ts` |
| `lib/src/better_auth/client/online_manager.dart` | `better-auth/src/client/online-manager.ts` |
| `lib/src/better_auth/client/broadcast_channel.dart` | `better-auth/src/client/broadcast-channel.ts` |
| `lib/src/better_auth/client/fetch_plugins.dart` | `better-auth/src/client/fetch-plugins.ts` |
| `lib/src/better_auth/client/types.dart` | `better-auth/src/client/types.ts` (`SessionQueryParams`) |
| `lib/src/better_auth/cookies/cookie_utils.dart` | `better-auth/src/cookies/cookie-utils.ts` |
| `lib/src/better_auth/utils/url.dart` | `better-auth/src/utils/url.ts` (client branch of `getBaseURL`) |
| `lib/src/better_auth/utils/defu.dart` | the `defu` package used by `config.ts` |
| `lib/src/better_auth/utils/date.dart` | new: JS `new Date(value)` for JSON dates |
| `lib/src/better_auth/core/plugin_client.dart` | `core/src/types/plugin-client.ts` |
| `lib/src/better_auth/core/db.dart` | `core/src/db/schema/{user,session,account}.ts` |
| `lib/src/better_auth/core/error_codes.dart` | `core/src/error/codes.ts`, `core/src/utils/error-codes.ts` |
| `lib/src/better_auth/core/error.dart` | `core/src/error/index.ts` (`BetterAuthError`) |
| `lib/src/better_auth/core/json.dart` | `core/src/utils/json.ts` |
| `lib/src/better_auth/core/logger.dart` | `core/src/env` logger |
| `lib/src/better_auth/plugins/email_otp/client.dart` | `better-auth/src/plugins/email-otp/client.ts`, `error-codes.ts`; route types from `routes.ts` |
| `lib/src/better_fetch/fetch.dart` | `better-fetch/src/fetch.ts` |
| `lib/src/better_fetch/create_fetch.dart` | `better-fetch/src/create-fetch/index.ts` |
| `lib/src/better_fetch/plugins.dart` | `better-fetch/src/plugins.ts` |
| `lib/src/better_fetch/types.dart` | `better-fetch/src/types.ts` |
| `lib/src/better_fetch/url.dart` | `better-fetch/src/url.ts` |
| `lib/src/better_fetch/utils.dart` | `better-fetch/src/utils.ts` |
| `lib/src/better_fetch/retry.dart` | `better-fetch/src/retry.ts` |
| `lib/src/better_fetch/auth.dart` | `better-fetch/src/auth.ts` |
| `lib/src/better_fetch/method.dart` | `better-fetch/src/method.ts` |
| `lib/src/better_fetch/error.dart` | `better-fetch/src/error.ts` |
| `lib/src/better_fetch/dio_fetch.dart` | new: the Dio transport that replaces `globalThis.fetch` |
| `lib/src/better_fetch/url_search_params.dart` | new: the WHATWG `URLSearchParams` subset |
| `lib/src/nanostores/atom.dart` | `nanostores/atom/index.js`, `nanostores/lifecycle/index.js` |
| `lib/src/convex_better_auth/plugins/convex/client.dart` | `@convex-dev/better-auth` `src/plugins/convex/client.ts` |
| `lib/src/convex_better_auth/flutter/index.dart` | `@convex-dev/better-auth` `src/react/index.tsx` |
| `lib/src/convex/flutter/convex_auth_state.dart` | `convex` `src/react/ConvexAuthState.tsx` |
| `lib/src/convex/flutter/auth_helpers.dart` | `convex` `src/react/auth_helpers.tsx` |
| `lib/src/convex/browser/sync/authentication_manager.dart` | `convex` `src/browser/sync/authentication_manager.ts` (token refetching) |

Tests mirror the same layout: `test/expo/*` ports `expo/test/*.test.ts`,
`test/better_auth/client/*` ports `better-auth/src/client/*.test.ts`, and
`test/better_fetch/*` ports `better-fetch/src/test/*.test.ts`. The Convex
packages have no client tests upstream; `test/convex/*` and
`test/convex_better_auth/*` are new. Upstream tests the email OTP plugin only
against a server, so `test/better_auth/plugins/*` is new too.

## Deviations

### Language and runtime gaps

- **No `Proxy` or route inference.** `client.a.bC(args)` becomes
  `client('/a/b-c', body: ..., query: ...)` with the same method inference,
  `pathMethods` and signal flips (`proxy.ts`). Typed methods for the core
  endpoints sit on top; their parameters follow each endpoint's zod schema.
  A `noSuchMethod` proxy was rejected because `--obfuscate` mangles names.
- **Account routes take Better Auth 1.6 and 1.7 fields.** TS types follow the
  installed `better-auth`: 1.6 selects an account by `providerId` (and the
  provider's `accountId`), 1.7 by the Better Auth `accountId` or
  `useAccountCookie`. `unlinkAccount`, `getAccessToken`, `refreshToken` and
  `accountInfo` accept both (checked against v1.6.33) and send only the fields
  given, so one package works with either server.
- **Types.** TS structural types over JSON become Dart extension types over the
  decoded map (`User`, `Session`, `Account`, `SessionData`), so plugin fields
  survive and no code generation is needed. `$Infer` and `InferPlugin` are not
  ported.
- **Plugin actions** are nested maps of closures, deep-merged like `defu`;
  typed Dart extensions expose them (`getCookie()`, `getLastUsedLoginMethod()`).
- **`throw` option** is `throwOnError`, because `throw` is a Dart keyword. Calls
  always return a record; with it, errors are thrown instead.
- **Durations.** Millisecond and second numbers (`timeout`, retry delays,
  `refetchInterval`) are `Duration`s.
- **Constant names** are lowerCamelCase (`STORE_UNMOUNT_DELAY` →
  `storeUnmountDelay`, `BASE_ERROR_CODES` → `baseErrorCodes`,
  `$ERROR_CODES` → `$errorCodes`), following Dart style.
- **Email OTP plugin.** `emailOTPClient` is `emailOtpClient` and
  `EMAIL_OTP_ERROR_CODES` is `emailOtpErrorCodes`, following Dart's acronym
  style. Its routes are typed methods like the core ones (`emailOtp.*`,
  `signIn.emailOtp`, the deprecated `forgetPassword.emailOtp`), and the OTP
  `type` union is the `EmailOtpType` enum.
- **Dates.** The session-cache restore and the typed date getters accept a
  `DateTime`, an ISO string or epoch milliseconds, as JS `new Date(value)`
  does: the Convex adapter sends dates as numbers.
- **`isJsonEqual`** compares `DateTime` by value; JS compares `Date` objects by
  reference, which defeats its own data-reference reuse.
- **`parser.ts`** has no prototype-pollution guards: `jsonDecode` has no
  prototype to pollute.
- **Errors.** A returned error is a `BetterFetchError` with `status`,
  `statusText` and the body in `error` (`message`, `code` getters), instead of
  the spread `{...body, status, statusText}` object. Session and query atoms
  wrap thrown transport errors as status `0`.
- **Unparseable `Expires`** is treated as a session cookie instead of throwing
  on `toISOString()`.
- **Listener queue.** A throwing atom listener no longer leaves nanostores'
  global queue stuck.
- **nanostores** `computed`, `map` and the other lifecycle hooks are not ported;
  only plugins use them.
- **better-fetch** StandardSchema `output`/`errorSchema` validation,
  `createSchema` and `hookOptions.cloneResponse` are not ported. Responses are
  buffered, so they can be read more than once.

### Not applicable on iOS and Android

- Browser-only code: `window`/`localStorage`, SSR checks, the cross-tab
  broadcast channel (kept as an interface with a no-op default), and
  `redirectPlugin` navigation (kept as an empty plugin).
- `baseURL` from environment variables, and `credentials: include`.
- React's Suspense-specific tests became listener re-subscribe tests.

### Expo-specific

- `expoClient` → `flutterClient`; `webBrowserOptions` → `webAuthOptions`
  (`FlutterWebAuth2Options`). The plugin id stays `expo`.
- `scheme` is required: there is no `expo-constants` app config to read.
- The synchronous storage API (`getItem`/`setItem`) is dropped because
  `flutter_secure_storage` is async-only. With every access queued per key, the
  read-snapshot logic that guarded sync writes is not needed.
  `lastLoginMethodClient` getters return futures.
- `cookiePrefix` is a `List<String>`; use `['']` for suffix matching.
- The focus and online managers are installed when `flutterClient()` runs, not
  on import.
- `FocusManager` is `AuthFocusManager`, because Flutter already has a
  `FocusManager`.
- The browser session is opened with the app `scheme` (what
  `flutter_web_auth_2` matches), not the full callback URL.
- Android's `dismissAuthSession()` maps to `clearAllDanglingCalls()`.
- Web throws `UnsupportedError`; Expo's web branches are not ported yet.

### Convex

- **`client` is a `ConvexAuthClient`.** Dart Convex clients share no type, so
  the provider takes the two calls it makes (`IConvexReactClient`).
- **`ConvexTokenAuth`** brings the token refetching of `AuthenticationManager`
  to clients that take a fixed token. With no server confirmation, it treats
  an applied token as accepted: it never re-authenticates after a rejection,
  and `isRefreshing` stays false. It also refetches on app resume when the
  refetch time passed while the device slept, and `clearAuth` cancels the
  scheduled refetch.
- **Effects run after the next frame**, so `Authenticated` subtrees are gone
  before Convex auth is cleared, the order React's effects guarantee.
- **`useConvexAuth` takes the `BuildContext`.**
- **Token cache.** The cached and in-flight tokens are dropped when the session
  id changes; React's callback could return the previous session's token.
  After a token fetch fails, the next successful session refresh makes a new
  fetcher, so an app that starts offline authenticates once it is back online;
  React stays unauthenticated until the session changes.
- **Not ported:** `initialToken` (server rendering), the `ott` cross-domain
  handoff and `crossDomainClient` (web), and `AuthBoundary` (experimental).

### Not ported

- The server plugin (`expo/src/index.ts`, `routes.ts`): keep using
  `@better-auth/expo` on the server.
- The other 17 plugin clients in `better-auth/client/plugins` (two-factor,
  organization, ...). Their endpoints work through `client(path)`.
- The Vue, Svelte, Solid and Lynx bindings.
- Server-side and TypeScript type tests.

## Updating to a new upstream release

1. Diff the upstream files in the map between the pinned tag and the new one.
2. Apply the same change to the matching Dart file and test.
3. Update the pins above and the README disclosure link.
