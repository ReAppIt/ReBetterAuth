/// Query flags for `/get-session`.
class SessionQueryParams {
  /// Creates session query flags.
  const SessionQueryParams({this.disableCookieCache, this.disableRefresh});

  /// Bypass the signed session-data cookie and read the database.
  final bool? disableCookieCache;

  /// Do not extend the session's expiry on this read.
  final bool? disableRefresh;

  /// The flags as query parameters, omitting unset ones.
  Map<String, Object?> toQuery() => <String, Object?>{
    'disableCookieCache': ?disableCookieCache,
    'disableRefresh': ?disableRefresh,
  };
}
