# re_better_auth

> [!NOTE]
> **AI-written, human-reviewed.** Every line of this package was written by AI
> (Claude, by Anthropic) as a port of the official
> [`@better-auth/expo`](https://github.com/better-auth/better-auth/tree/v1.7.7/packages/expo)
> client, the better-auth core client it plugs into and Convex's Better Auth
> provider, and the port has been fully reviewed by a human. It is not
> affiliated with Better Auth or Convex.

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
platforms: **iOS and Android**. Apps on Convex can also use the port of Convex's
Better Auth provider; see [Convex](#convex).

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
// lib/auth.ts
export const auth = betterAuth({
  trustedOrigins: ["myapp://"],
});
```

Several schemes and wildcards work as well:

```ts
// lib/auth.ts
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
<!-- android/app/src/main/AndroidManifest.xml -->
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
<!-- android/app/src/main/AndroidManifest.xml -->
<application android:allowBackup="false" ...>
```

`expo-secure-store` configures this automatically; Flutter apps must do it by
hand.

## Usage

### Authenticating users

```dart
// lib/sign_in.dart
final (:data, :error) = await authClient.signIn.email(
  email: email,
  password: password,
);
if (error != null) {
  // error.code, such as INVALID_EMAIL_OR_PASSWORD, and error.message
}
```

```dart
// lib/sign_up.dart
await authClient.signUp.email(email: email, password: password, name: name);
```

Every call returns a `({data, error})` record: HTTP errors are returned, not
thrown. Transport failures (no network) throw a `DioException`.

### Social sign-in

`signIn.social` opens the provider in an in-app browser session
(ASWebAuthenticationSession on iOS, Chrome Auth Tab on Android). A relative
`callbackURL` such as `/dashboard` becomes the deep link `myapp:///dashboard`.

```dart
// lib/social_sign_in.dart
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
// lib/social_sign_in.dart
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
// lib/home.dart
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
// lib/api_client.dart
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
// lib/linked_accounts.dart

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

### Email OTP

With the server's [`emailOTP()`](https://www.better-auth.com/docs/plugins/email-otp)
plugin, add `emailOtpClient()` to the client's plugins:

```dart
// lib/auth_client.dart
import 'package:re_better_auth/plugins.dart';
import 'package:re_better_auth/re_better_auth.dart';

final authClient = createAuthClient(
  baseURL: 'http://localhost:8081',
  plugins: [
    flutterClient(
      scheme: 'myapp',
      storagePrefix: 'myapp',
      storage: const SecureStore(),
    ),
    emailOtpClient(),
  ],
);
```

```dart
// lib/email_otp_sign_in.dart
await authClient.emailOtp.sendVerificationOtp(
  email: email,
  type: EmailOtpType.signIn,
);
final (:data, :error) = await authClient.signIn.emailOtp(
  email: email,
  otp: code,
);
if (error?.code == 'INVALID_OTP') {
  // Ask for the code again.
}
```

The other routes are on `authClient.emailOtp`: `checkVerificationOtp`,
`verifyEmail`, `requestPasswordReset`, `resetPassword`, `requestEmailChange`
and `changeEmail`.

### Other endpoints

Typed methods cover the core API (sessions, accounts, passwords, email
verification and more) and the email OTP plugin. Call any other endpoint, such
as another plugin's, by path:

```dart
// lib/two_factor.dart
await authClient('/two-factor/enable', body: {'password': password});
```

A body makes the call a POST, otherwise it is a GET; force a method with
`fetchOptions: ClientFetchOption(method: 'POST')`.

## Convex

With [Convex](https://convex.dev), Better Auth runs inside your Convex
deployment through the [Convex Better Auth component](https://labs.convex.dev/better-auth).
These steps follow its
[Expo guide](https://labs.convex.dev/better-auth/framework-guides/expo), with
this package as the client. `package:re_better_auth/convex.dart` ports the
component's client plugin and `ConvexBetterAuthProvider`.

### 1. Install the server packages

In your Convex project, install the component and Better Auth 1.6, the version
the component requires:

```bash
npm install convex@latest @convex-dev/better-auth
npm install better-auth@~1.6.15 @better-auth/expo@~1.6.15
```

### 2. Register the component

```ts
// convex/convex.config.ts
import { defineApp } from "convex/server";
import betterAuth from "@convex-dev/better-auth/convex.config";

const app = defineApp();
app.use(betterAuth);

export default app;
```

### 3. Add the Convex auth config

```ts
// convex/auth.config.ts
import { getAuthConfigProvider } from "@convex-dev/better-auth/auth-config";
import type { AuthConfig } from "convex/server";

export default {
  providers: [getAuthConfigProvider()],
} satisfies AuthConfig;
```

### 4. Set the secret

```bash
npx convex env set BETTER_AUTH_SECRET=$(openssl rand -base64 32)
```

Your app uses both deployment URLs: `https://<deployment>.convex.cloud` for the
Convex client and `https://<deployment>.convex.site` for Better Auth.

### 5. Create the Better Auth instance

The `expo()` and `convex()` plugins are both required:

```ts
// convex/auth.ts
import { createClient, type GenericCtx } from "@convex-dev/better-auth";
import { convex } from "@convex-dev/better-auth/plugins";
import { betterAuth } from "better-auth/minimal";
import { expo } from "@better-auth/expo";
import { components } from "./_generated/api";
import type { DataModel } from "./_generated/dataModel";
import authConfig from "./auth.config";

export const authComponent = createClient<DataModel>(components.betterAuth);

export const createAuth = (ctx: GenericCtx<DataModel>) =>
  betterAuth({
    trustedOrigins: ["myapp://"],
    database: authComponent.adapter(ctx),
    emailAndPassword: { enabled: true, requireEmailVerification: false },
    plugins: [expo(), convex({ authConfig })],
  });
```

### 6. Mount the handlers

```ts
// convex/http.ts
import { httpRouter } from "convex/server";
import { authComponent, createAuth } from "./auth";

const http = httpRouter();

authComponent.registerRoutes(http, createAuth);

export default http;
```

### 7. Create the auth client

Point the client at your `.convex.site` URL and add `convexClient()`:

```dart
// lib/auth_client.dart
import 'package:re_better_auth/convex.dart';
import 'package:re_better_auth/re_better_auth.dart';

final authClient = createAuthClient(
  baseURL: 'https://adjective-animal-123.convex.site',
  plugins: [
    flutterClient(
      scheme: 'myapp',
      storagePrefix: 'myapp',
      storage: const SecureStore(),
    ),
    convexClient(),
  ],
);
```

### 8. Set up the Convex provider

Wrap your app in `ConvexBetterAuthProvider`. It gives your Convex client a token
while a user is signed in and clears it after sign-out. Dart Convex clients
take a fixed token (`setAuth(token: ...)`), so pass yours through
`ConvexTokenAuth`, which also refetches the token 10 seconds before it expires:

```dart
// lib/main.dart
final convex = ...; // Your Convex client for https://adjective-animal-123.convex.cloud

runApp(
  ConvexBetterAuthProvider(
    client: ConvexTokenAuth((token) => convex.setAuth(token: token)),
    authClient: authClient,
    child: const MyApp(),
  ),
);
```

### 9. Finish the Flutter setup

Steps 7 and 8 of [Installation](#installation) apply as written: the Android
callback activity and the backup rules. Your scheme is already in
`trustedOrigins` from step 5.

### Usage

Sign users in and out with `authClient` as usual. Below the provider,
`useConvexAuth(context)` returns `isLoading`, `isAuthenticated` and
`isRefreshing`, and these widgets show their child only in the matching state:

```dart
// lib/home.dart
const Column(
  children: [
    AuthLoading(child: CircularProgressIndicator()),
    Unauthenticated(child: SignInScreen()),
    Authenticated(child: HomeScreen()),
  ],
)
```

On sign-out, `Authenticated` children are removed before the Convex token is
cleared, so their queries do not re-run signed out. To manage auth outside the
widget tree, `ConvexAuthController(client: ..., auth: AuthFromBetterAuth(authClient))`
runs the same logic and exposes its `state` as a `ValueListenable`.

For social sign-in, the authorized origin and redirect URI use your Convex site
URL. For Google:

```text
https://adjective-animal-123.convex.site
https://adjective-animal-123.convex.site/api/auth/callback/google
```

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
// lib/auth_client.dart
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
  the core API and the email OTP plugin, and `authClient(path)` for everything
  else.
- `emailOTPClient` is `emailOtpClient`, following Dart's acronym style.
- The account methods accept the fields of Better Auth 1.6 and 1.7; TypeScript
  allows only those of the installed version.
- Web is not supported yet.

[PORTING.md](PORTING.md) maps every Dart file to its upstream source and lists
each deviation.

## License

MIT. Includes code ported from Better Auth, better-fetch and Nano Stores (all
MIT); see [LICENSE](LICENSE).
