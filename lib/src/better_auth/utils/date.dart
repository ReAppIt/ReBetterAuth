/// Reads a JSON date like JS `new Date(value)`: a [DateTime], an ISO 8601
/// string, or epoch milliseconds (the Convex adapter sends numbers).
DateTime? toDate(Object? value) => switch (value) {
  final DateTime date => date,
  final String text => DateTime.tryParse(text),
  final num millis when millis.isFinite && millis.abs() <= _maxMillis =>
    DateTime.fromMillisecondsSinceEpoch(millis.toInt(), isUtc: true),
  _ => null,
};

// The ECMAScript time value range, which DateTime shares.
const int _maxMillis = 8640000000000000;
