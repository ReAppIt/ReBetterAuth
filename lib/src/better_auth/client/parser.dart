import 'dart:convert';

final RegExp _jsonSignature = RegExp(
  r'^\s*["[{]|^\s*-?\d{1,16}(\.\d{1,17})?([Ee][+-]?\d+)?\s*$',
);

const Map<String, Object?> _specialValues = <String, Object?>{
  'true': true,
  'false': false,
  'null': null,
  'undefined': null,
  'nan': double.nan,
  'infinity': double.infinity,
  '-infinity': double.negativeInfinity,
};

final RegExp _isoDateRegex = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?(?:Z|([+-])(\d{2}):(\d{2}))$',
);

DateTime? _parseISODate(String value) {
  final match = _isoDateRegex.firstMatch(value);
  if (match == null) return null;
  int part(int index) => int.parse(match.group(index)!);
  final ms = match.group(7);
  var date = DateTime.utc(
    part(1),
    part(2),
    part(3),
    part(4),
    part(5),
    part(6),
    ms == null ? 0 : int.parse(ms.padRight(3, '0')),
  );
  final offsetSign = match.group(8);
  if (offsetSign != null) {
    final offset = (part(9) * 60 + part(10)) * (offsetSign == '+' ? -1 : 1);
    date = date.add(Duration(minutes: offset));
  }
  return date;
}

/// Reviver hook for [parseJSON]: receives each key and decoded value.
typedef JsonReviver = Object? Function(Object? key, Object? value);

/// Parses better-auth JSON, reviving ISO dates into UTC `DateTime`s.
///
/// With [strict] it throws on invalid input; otherwise it returns [value].
Object? parseJSON(
  Object? value, {
  bool strict = true,
  JsonReviver? reviver,
  bool parseDates = true,
}) {
  if (value is! String) return value;
  final trimmed = value.trim();
  final lowerValue = trimmed.toLowerCase();
  if (lowerValue.length <= 9 && _specialValues.containsKey(lowerValue)) {
    return _specialValues[lowerValue];
  }
  if (!_jsonSignature.hasMatch(trimmed)) {
    if (strict) throw const FormatException('[better-json] Invalid JSON');
    return value;
  }
  try {
    return jsonDecode(
      trimmed,
      reviver: (key, decoded) {
        if (parseDates && decoded is String) {
          final date = _parseISODate(decoded);
          if (date != null) return date;
        }
        return reviver == null ? decoded : reviver(key, decoded);
      },
    );
  } on FormatException {
    if (strict) rethrow;
    return value;
  }
}
