import 'package:http_parser/http_parser.dart' show parseHttpDate;

/// Prefix of cookies limited to HTTPS (`__Secure-`).
const String secureCookiePrefix = '__Secure-';

/// Prefix of host-only HTTPS cookies (`__Host-`).
const String hostCookiePrefix = '__Host-';

String _tryDecode(String value) {
  if (!value.contains('%')) return value;
  try {
    return Uri.decodeComponent(value);
  } on Object {
    return value;
  }
}

String _unquoteCookieValue(String value) {
  if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
    return value;
  }
  return value.substring(1, value.length - 1);
}

/// Parsed attributes of one `Set-Cookie` entry.
class CookieAttributes {
  /// Creates attributes for a cookie [value].
  CookieAttributes(this.value);

  /// Decoded cookie value.
  final String value;

  /// `Max-Age` in seconds, when present and numeric.
  int? maxAge;

  /// `Expires` date, when present and parseable.
  DateTime? expires;

  /// `Domain` attribute.
  String? domain;

  /// `Path` attribute.
  String? path;

  /// `Secure` flag.
  bool? secure;

  /// `HttpOnly` flag.
  bool? httponly;

  /// `Partitioned` flag.
  bool? partitioned;

  /// `SameSite`: `strict`, `lax` or `none`.
  String? samesite;

  /// Unrecognized attributes by lower-case name (`true` for bare flags).
  final Map<String, Object> other = <String, Object>{};
}

/// Removes a `__Secure-` or `__Host-` prefix from [cookieName].
String stripSecureCookiePrefix(String cookieName) {
  if (cookieName.startsWith(secureCookiePrefix)) {
    return cookieName.substring(secureCookiePrefix.length);
  }
  if (cookieName.startsWith(hostCookiePrefix)) {
    return cookieName.substring(hostCookiePrefix.length);
  }
  return cookieName;
}

/// Splits a comma-joined `Set-Cookie` value, keeping commas inside `Expires`.
List<String> splitSetCookieHeader(String setCookie) {
  if (setCookie.isEmpty) return <String>[];
  final result = <String>[];
  var start = 0;
  var i = 0;
  while (i < setCookie.length) {
    if (setCookie[i] == ',') {
      var j = i + 1;
      while (j < setCookie.length && setCookie[j] == ' ') {
        j++;
      }
      while (j < setCookie.length &&
          setCookie[j] != '=' &&
          setCookie[j] != ';' &&
          setCookie[j] != ',') {
        j++;
      }
      if (j < setCookie.length && setCookie[j] == '=') {
        final part = setCookie.substring(start, i).trim();
        if (part.isNotEmpty) result.add(part);
        start = i + 1;
        while (start < setCookie.length && setCookie[start] == ' ') {
          start++;
        }
        i = start;
        continue;
      }
    }
    i++;
  }
  final last = setCookie.substring(start).trim();
  if (last.isNotEmpty) result.add(last);
  return result;
}

final RegExp _leadingInt = RegExp(r'^\s*([+-]?\d+)');

int? _parseInt(String value) {
  final match = _leadingInt.firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}

DateTime? _parseDate(String value) {
  try {
    return parseHttpDate(value);
  } on FormatException {
    return DateTime.tryParse(value);
  }
}

/// Parses a `Set-Cookie` header into attributes keyed by cookie name.
///
/// Entries without a name are skipped; later entries replace earlier ones.
Map<String, CookieAttributes> parseSetCookieHeader(String setCookie) {
  final cookies = <String, CookieAttributes>{};
  for (final cookieString in splitSetCookieHeader(setCookie)) {
    final parts = cookieString.split(';').map((part) => part.trim()).toList();
    final nameValue = parts.first;
    final attributes = parts.skip(1);
    final nameParts = nameValue.split('=');
    final name = nameParts.first;
    if (name.isEmpty) continue;
    final value = _unquoteCookieValue(nameParts.skip(1).join('='));
    final attr = CookieAttributes(_tryDecode(value));
    for (final attribute in attributes) {
      final attrParts = attribute.split('=');
      final attrValue = attrParts.skip(1).join('=');
      final hasValue = attrValue.isNotEmpty;
      final normalizedName = attrParts.first.trim().toLowerCase();
      switch (normalizedName) {
        case 'max-age':
          attr.maxAge = hasValue ? _parseInt(attrValue.trim()) : null;
        case 'expires':
          attr.expires = hasValue ? _parseDate(attrValue.trim()) : null;
        case 'domain':
          attr.domain = hasValue ? attrValue.trim() : null;
        case 'path':
          attr.path = hasValue ? attrValue.trim() : null;
        case 'secure':
          attr.secure = true;
        case 'httponly':
          attr.httponly = true;
        case 'samesite':
          attr.samesite = hasValue ? attrValue.trim().toLowerCase() : null;
        case 'partitioned':
          attr.partitioned = true;
        default:
          attr.other[normalizedName] = hasValue ? attrValue.trim() : true;
      }
    }
    cookies[name] = attr;
  }
  return cookies;
}
