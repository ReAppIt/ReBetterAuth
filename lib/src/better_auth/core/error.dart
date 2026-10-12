/// Configuration or usage error raised by the client itself.
class BetterAuthError implements Exception {
  /// Creates an error with [message] and an optional underlying [cause].
  BetterAuthError(this.message, {this.cause});

  /// What went wrong.
  final String message;

  /// The error that triggered this one, if any.
  final Object? cause;

  @override
  String toString() => 'BetterAuthError: $message';
}
