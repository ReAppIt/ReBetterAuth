# re_better_auth

> [!NOTE]
> **AI-written, human-reviewed.** Every line of this package was written by AI
> (Claude, by Anthropic) as a port of the official
> [`@better-auth/expo`](https://github.com/better-auth/better-auth/tree/v1.7.7/packages/expo)
> client and the better-auth core client it plugs into, and the port has been
> fully reviewed by a human. It is not affiliated with Better Auth.

A Flutter port of the [Better Auth Expo integration](https://www.better-auth.com/docs/integrations/expo).
It keeps the upstream structure and behaviour and swaps the React Native pieces
for Flutter ones:

| Expo | Flutter |
|---|---|
| `expo-secure-store` | `flutter_secure_storage` |
| `expo-web-browser` (`openAuthSessionAsync`) | `flutter_web_auth_2` |
| `expo-network` | `connectivity_plus` |
| `AppState` | `AppLifecycleListener` |
| `fetch` | `dio` |

Because the client speaks the same protocol as `@better-auth/expo`, your server
uses the stock `expo()` plugin; there is no server code to port. Supported
platforms: **iOS and Android**.

## Installation

### 1. Configure a Better Auth backend

Before using Better Auth with Flutter, make sure you have a Better Auth backend
set up. Follow the [installation guide](https://www.better-auth.com/docs/installation).

### 2. Install server dependencies

Install both the Better Auth package and the Expo plugin on your server:

```bash
npm install better-auth @better-auth/expo
```

### 3. Add the Expo plugin on your server

```ts
// lib/auth.ts
import { betterAuth } from "better-auth";
import { expo } from "@better-auth/expo";

export const auth = betterAuth({
  plugins: [expo()],
  emailAndPassword: {
    enabled: true,
  },
});
```

### 4. Install the Flutter package

```bash
flutter pub add re_better_auth
```

It needs Android `minSdk` 24 and iOS 13.

### 5. Initialize the client

Create the client with the base URL of your Better Auth backend and the
`flutterClient` plugin. It stores cookies and the session securely and handles
social sign-in in an in-app browser session.

```dart
// lib/auth_client.dart
import 'package:re_better_auth/re_better_auth.dart';

final authClient = createAuthClient(
  baseURL: 'http://localhost:8081', // Base URL of your Better Auth backend.
  plugins: [
    flutterClient(
      scheme: 'myapp',
      storagePrefix: 'myapp',
      storage: const SecureStore(),
    ),
  ],
);
```

`/api/auth` is appended when the base URL has no path. Include the full path if
you changed it on the server.

### 6. Scheme and trusted origins

Better Auth redirects back to your app through a deep link with your app's
scheme, so add the scheme to `trustedOrigins` in your Better Auth config:

```ts
export const auth = betterAuth({
  trustedOrigins: ["myapp://"],
});
```

Several schemes and wildcards work as well:

```ts
export const auth = betterAuth({
  trustedOrigins: [
    "myapp://",
    "myapp-prod://",
    "myapp-staging://",
    "myapp://*",
  ],
});
```

There is no Expo Go `exp://` scheme in Flutter: development builds use your own
scheme too.

### 7. Register the callback on Android

`flutter_web_auth_2` needs its callback activity in
`android/app/src/main/AndroidManifest.xml`, with your scheme:

```xml
<manifest>
  <application>
    <activity
      android:name="com.linusu.flutter_web_auth_2.CallbackActivity"
      android:exported="true"
      android:taskAffinity="">
      <intent-filter android:label="flutter_web_auth_2">
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="myapp" />
      </intent-filter>
    </activity>
  </application>
</manifest>
```

iOS needs nothing extra for a custom scheme. See the
[flutter_web_auth_2 setup](https://pub.dev/packages/flutter_web_auth_2#setup)
for HTTPS callbacks.

### 8. Keep secure storage out of Android backups

Android Auto Backup cannot restore the Keystore-encrypted values, so disable it
or exclude flutter_secure_storage's preferences
([details](https://pub.dev/packages/flutter_secure_storage#disabling-auto-backup)):

```xml
<application android:allowBackup="false" ...>
```

`expo-secure-store` configures this automatically; Flutter apps must do it by
hand.

## Usage

### Authenticating users

```dart
final (:data, :error) = await authClient.signIn.email(
  email: email,
  password: password,
);
if (error != null) {
  // error.code, such as INVALID_EMAIL_OR_PASSWORD, and error.message
}
```

```dart
await authClient.signUp.email(email: email, password: password, name: name);
```

Every call returns a `({data, error})` record: HTTP errors are returned, not
thrown. Transport failures (no network) throw a `DioException`.

### Social sign-in

`signIn.social` opens the provider in an in-app browser session
(ASWebAuthenticationSession on iOS, Chrome Auth Tab on Android). A relative
`callbackURL` such as `/dashboard` becomes the deep link `myapp:///dashboard`.

```dart
final (:data, :error) = await authClient.signIn.social(
  provider: 'google',
  callbackURL: '/dashboard',
);
if (error == null) {
  // Navigate yourself: the session cookie is stored when the browser returns.
}
```

Closing the browser returns normally without signing in.

### ID token sign-in

Sign in with a provider SDK on the device, then let the server verify the ID
token. Google, Apple and Facebook support this.

```dart
import 'package:google_sign_in/google_sign_in.dart';

final account = await GoogleSignIn.instance.authenticate();
final idToken = account.authentication.idToken;
if (idToken != null) {
  await authClient.signIn.social(
    provider: 'google',
    idToken: IdTokenCredential(token: idToken),
  );
}
```

### Session

`authClient.useSession` is a `ValueListenable`. Listening to it fetches the
session and keeps it fresh: after sign-in and sign-out, when the app returns to
the foreground, and when the device comes back online.

```dart
ValueListenableBuilder(
  valueListenable: authClient.useSession,
  builder: (context, session, _) {
    if (session.isPending) return const CircularProgressIndicator();
    final user = session.data?.user;
    return Text(user == null ? 'Signed out' : 'Welcome, ${user.name}');
  },
);
```

It also works with `useValueListenable(authClient.useSession)` from
flutter_hooks and `authClient.useSession.toSignal()` from signals.

The session is cached in secure storage, so a restarted app shows the user
without a loading spinner while it revalidates. Pass `disableCache: true` to
`flutterClient` to turn that off. Plugin and `additionalFields` values stay
available: `session.data?.user['favoriteColor']`.

### Making authenticated requests to your server

Read the stored cookies and send them yourself:

```dart
final cookie = await authClient.getCookie();
final response = await dio.get<Object?>(
  'http://localhost:8081/api/secure-endpoint',
  options: Options(headers: {'Cookie': cookie}),
);
```

### Linked accounts

`getAccessToken`, `refreshToken`, `accountInfo` and `unlinkAccount` take the
same fields as the JS client. Pass the ones your server's Better Auth version
expects:

```dart
// Better Auth 1.6: select the account by provider.
await authClient.getAccessToken(providerId: 'google');

// Better Auth 1.7: select it by its Better Auth id, from listAccounts().
final (:data, error: _) = await authClient.listAccounts();
final google = data?.where((a) => a.providerId == 'google').firstOrNull;
if (google != null) await authClient.getAccessToken(accountId: google.id);
```

When the server moves from 1.6 to 1.7, update these calls: a 1.6-style call
to a 1.7 server returns an error. TypeScript points them out after the upgrade;
Dart cannot.

### Other endpoints

Typed methods cover the core API (sessions, accounts, passwords, email
verification and more). Call any other endpoint, such as a plugin's, by path:

```dart
await authClient('/two-factor/enable', body: {'password': password});

// Convex: exchange the Better Auth session for a Convex JWT.
final (:data, error: _) = await authClient<Map<String, Object?>>('/convex/token');
final convexToken = data?['token'];
```

A body makes the call a POST, otherwise it is a GET; force a method with
`fetchOptions: ClientFetchOption(method: 'POST')`.

## Options

### Flutter client

**storage**: where cookies and the cached session live. `SecureStore` wraps
`flutter_secure_storage`; pass `SecureStore(FlutterSecureStorage(...))` to set
platform options. Reuse one instance across clients that share keys.

**scheme**: your app's URL scheme, used for deep links back into the app. It must
match the Android intent filter and the server's `trustedOrigins`.

**storagePrefix**: prefix of the storage keys (`<prefix>_cookie`,
`<prefix>_session_data`). Defaults to `better-auth`.

**disableCache**: stops caching the session in secure storage.

**cookiePrefix**: prefixes that identify better-auth cookies, so third-party
cookies do not trigger session refetches. Defaults to `['better-auth']`.

```dart
flutterClient(
  scheme: 'myapp',
  storage: const SecureStore(),
  cookiePrefix: ['better-auth', 'my-app', 'custom-auth'],
);
```

If you use plugins like passkey with a custom `webAuthnChallengeCookie` (for
example `my-app-passkey`), include its prefix (`my-app`).

**webAuthOptions**: `FlutterWebAuth2Options` for the browser session, such as
`preferEphemeral: true` so it does not share cookies with the system browser.

### Client

`createAuthClient` also takes `fetchOptions` (defaults and hooks for every
request), `sessionOptions` (`RevalidateOptions`: `refetchInterval`,
`refetchOnWindowFocus`, `refetchWhenOffline`), `dio` (your own Dio instance as
the transport) and other `plugins`.

### Server

**disableOriginOverride**: set on the server's `expo()` plugin to stop it from
copying the `expo-origin` header into `Origin`.

## Differences from `@better-auth/expo`

- `expoClient` is `flutterClient`, and `webBrowserOptions` is `webAuthOptions`.
- `scheme` is required: Flutter has no `app.json` to read it from.
- Storage is async-only, because `flutter_secure_storage` has no synchronous API.
- TypeScript infers every endpoint from the server; Dart has typed methods for
  the core API and `authClient(path)` for everything else.
- The account methods accept the fields of Better Auth 1.6 and 1.7; TypeScript
  allows only those of the installed version.
- Web is not supported yet.

[PORTING.md](PORTING.md) maps every Dart file to its upstream source and lists
each deviation.

## License

MIT. Includes code ported from Better Auth, better-fetch and Nano Stores (all
MIT); see [LICENSE](LICENSE).
