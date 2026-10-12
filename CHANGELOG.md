## 0.1.0

- Initial release: a port of `@better-auth/expo` 1.7.7 (`flutterClient`,
  secure cookie storage, social sign-in through an auth session, session cache,
  `lastLoginMethodClient`) and the better-auth 1.7.7 core client it plugs into
  (`createAuthClient`, typed core routes, `useSession`), on a better-fetch 1.3.2
  port over Dio.
- The account routes (`getAccessToken`, `refreshToken`, `accountInfo`,
  `unlinkAccount`) also accept the Better Auth 1.6 fields, for 1.6 servers.
