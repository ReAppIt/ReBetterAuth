/// A decoded JSON object.
typedef JsonMap = Map<String, Object?>;

DateTime _date(Object? value) {
  final date = _optionalDate(value);
  if (date == null) throw FormatException('Expected a date, got $value');
  return date;
}

DateTime? _optionalDate(Object? value) => switch (value) {
  final DateTime date => date,
  final String text => DateTime.tryParse(text),
  final int millis => DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
  _ => null,
};

/// A better-auth user over its JSON map; plugin and additional fields stay in [json].
extension type User(JsonMap json) {
  /// User id.
  String get id => '${json['id']}';

  /// Lower-cased email address.
  String get email => json['email']! as String;

  /// Whether the email address is verified.
  bool get emailVerified => json['emailVerified'] as bool? ?? false;

  /// Display name.
  String get name => json['name'] as String? ?? '';

  /// Avatar URL.
  String? get image => json['image'] as String?;

  /// Creation time.
  DateTime get createdAt => _date(json['createdAt']);

  /// Last update time.
  DateTime get updatedAt => _date(json['updatedAt']);

  /// Any field, including ones added by plugins or `additionalFields`.
  Object? operator [](String key) => json[key];
}

/// A better-auth session over its JSON map; plugin fields stay in [json].
extension type Session(JsonMap json) {
  /// Session id.
  String get id => '${json['id']}';

  /// Owner's user id.
  String get userId => '${json['userId']}';

  /// When the session stops being valid.
  DateTime get expiresAt => _date(json['expiresAt']);

  /// Session token.
  String get token => json['token']! as String;

  /// IP address the session was created from.
  String? get ipAddress => json['ipAddress'] as String?;

  /// User agent the session was created from.
  String? get userAgent => json['userAgent'] as String?;

  /// Creation time.
  DateTime get createdAt => _date(json['createdAt']);

  /// Last update time.
  DateTime get updatedAt => _date(json['updatedAt']);

  /// Any field, including ones added by plugins or `additionalFields`.
  Object? operator [](String key) => json[key];
}

/// A linked account as returned by `/list-accounts`.
extension type Account(JsonMap json) {
  /// Account id.
  String get id => '${json['id']}';

  /// Provider id, such as `credential` or `google`.
  String get providerId => json['providerId']! as String;

  /// The provider's id for this account.
  String get accountId => '${json['accountId']}';

  /// Owner's user id.
  String get userId => '${json['userId']}';

  /// Granted OAuth scopes.
  List<String> get scopes => <String>[
    for (final scope in json['scopes'] as List<Object?>? ?? const []) '$scope',
  ];

  /// Access token expiry, when the provider reports one.
  DateTime? get accessTokenExpiresAt =>
      _optionalDate(json['accessTokenExpiresAt']);

  /// Creation time.
  DateTime get createdAt => _date(json['createdAt']);

  /// Last update time.
  DateTime get updatedAt => _date(json['updatedAt']);

  /// Any field, including ones added by plugins.
  Object? operator [](String key) => json[key];
}

/// The `/get-session` payload: [user], [session] and any plugin fields.
extension type SessionData(JsonMap json) {
  /// The signed-in user.
  User get user => User(json['user']! as JsonMap);

  /// The current session.
  Session get session => Session(json['session']! as JsonMap);

  /// Any top-level field, such as ones added by `customSession`.
  Object? operator [](String key) => json[key];
}
