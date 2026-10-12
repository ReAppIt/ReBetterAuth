/// Failed response: [status], [statusText] and the parsed body in [error].
class BetterFetchError implements Exception {
  /// Creates an error for a response with [status] and [statusText].
  BetterFetchError(this.status, this.statusText, [this.error]);

  /// HTTP status code; `0` marks a transport failure caught by the client.
  final int status;

  /// HTTP reason phrase, often empty over HTTP/2.
  final String statusText;

  /// Parsed JSON body, raw text, or the thrown transport error.
  final Object? error;

  /// The body's `message` field, when the body is a JSON object.
  String? get message => _field('message');

  /// The body's `code` field (a better-auth error code such as `INVALID_EMAIL`).
  String? get code => _field('code');

  /// Reads [key] like the JS error object `{...body, status, statusText}`.
  Object? operator [](String key) {
    if (key == 'status') return status;
    if (key == 'statusText') return statusText;
    final body = error;
    return body is Map<String, Object?> ? body[key] : null;
  }

  String? _field(String key) {
    final value = this[key];
    return value is String ? value : null;
  }

  @override
  String toString() {
    final detail = message ?? (statusText.isEmpty ? null : statusText);
    return 'BetterFetchError($status${detail == null ? '' : ', $detail'})';
  }
}
