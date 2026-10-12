import 'dart:convert';

import 'package:re_better_auth/src/better_auth/core/logger.dart';

final RegExp _iso8601Regex = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$',
);

Object? _reviveDate(Object? value) {
  if (value is String && _iso8601Regex.hasMatch(value)) {
    return DateTime.tryParse(value) ?? value;
  }
  return value;
}

Object? _reviveDates(Object? value) {
  if (value == null || value is DateTime) return value;
  if (value is String) return _reviveDate(value);
  if (value is List<Object?>) return value.map(_reviveDates).toList();
  if (value is Map<String, Object?>) {
    return <String, Object?>{
      for (final MapEntry(:key, :value) in value.entries)
        key: _reviveDates(value),
    };
  }
  return value;
}

/// Parses JSON text (or walks a decoded value), reviving `...Z` ISO dates.
///
/// Returns `null` and logs instead of throwing when the input is invalid.
Object? safeJSONParse(Object? data) {
  try {
    if (data is! String) {
      if (data == null) return null;
      return _reviveDates(data);
    }
    return jsonDecode(data, reviver: (_, value) => _reviveDate(value));
  } on FormatException catch (error) {
    logger.severe('Error parsing JSON', error);
    return null;
  }
}
