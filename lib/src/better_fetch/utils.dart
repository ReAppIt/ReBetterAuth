import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:re_better_auth/src/better_fetch/auth.dart';
import 'package:re_better_auth/src/better_fetch/dio_fetch.dart';
import 'package:re_better_auth/src/better_fetch/method.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/better_fetch/url_search_params.dart';

final RegExp _jsonRe = RegExp(
  r'^application\/(?:[\w!#$%&*.^`~-]*\+)?json(;.+)?$',
  caseSensitive: false,
);

const Set<String> _textTypes = <String>{
  'image/svg',
  'application/xml',
  'application/xhtml',
  'application/html',
};

/// How a body is read: `json`, `text` or `blob` (bytes).
String detectResponseType(FetchResponse response) {
  final contentType = response.headers.get('content-type');
  if (contentType == null) return 'json';
  final mediaType = contentType.split(';').first;
  if (_jsonRe.hasMatch(mediaType)) return 'json';
  if (_textTypes.contains(mediaType) || mediaType.startsWith('text/')) {
    return 'text';
  }
  return 'blob';
}

/// Whether [value] is valid JSON.
bool isJSONParsable(String value) {
  try {
    jsonDecode(value);
    return true;
  } on FormatException {
    return false;
  }
}

/// Whether [value] is sent as JSON: primitives, lists and string-keyed maps.
bool isJSONSerializable(Object? value) {
  if (value == null) return false;
  if (value is String || value is num || value is bool) return true;
  if (value is TypedData) return false;
  return value is List<Object?> || value is Map<String, Object?>;
}

/// Parses [text] as JSON, returning the text itself when that fails.
Object? jsonParse(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// `Date.prototype.toISOString`: UTC with millisecond precision.
String toISOString(DateTime date) => DateTime.fromMillisecondsSinceEpoch(
  date.millisecondsSinceEpoch,
  isUtc: true,
).toIso8601String();

/// `JSON.stringify` port: `DateTime` becomes [toISOString].
String jsonStringify(Object? value) =>
    jsonEncode(value, toEncodable: _toEncodable);

Object? _toEncodable(Object? value) {
  if (value is DateTime) return toISOString(value);
  // ignore: avoid_dynamic_calls
  return (value as dynamic).toJson();
}

Dio? _defaultDio;

/// The transport for [options]: `customFetchImpl` or a shared Dio instance.
FetchEsque getFetch([BetterFetchOption? options]) =>
    options?.customFetchImpl ?? dioFetch(_defaultDio ??= Dio());

/// Whether [method] carries a body.
bool isPayloadMethod(String? method) {
  if (method == null) return false;
  return const [
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  ].contains(method.toUpperCase());
}

/// Whether [method] is a regular route method.
bool isRouteMethod(String? method) {
  if (method == null) return false;
  return const [
    'GET',
    'POST',
    'PUT',
    'PATCH',
    'DELETE',
  ].contains(method.toUpperCase());
}

/// Merges header maps left to right, dropping `null` values.
Map<String, String> mergeHeaders(List<Map<String, String?>?> sources) {
  final merged = <String, String>{};
  for (final source in sources) {
    if (source == null) continue;
    source.forEach((key, value) {
      if (value != null) merged[key] = value;
    });
  }
  return merged;
}

/// Request headers by lower-case name, with auth and JSON content type added.
Future<Map<String, String>> getHeaders([BetterFetchOption? opts]) async {
  final headers = <String, String>{
    for (final MapEntry(:key, :value) in mergeHeaders([
      opts?.headers,
      await getAuthHeader(opts),
    ]).entries)
      key.toLowerCase(): value,
  };
  if (!headers.containsKey('content-type')) {
    final contentType = detectContentType(opts?.body);
    if (contentType != null) headers['content-type'] = contentType;
  }
  return headers;
}

/// `application/json` for JSON-serializable bodies, otherwise `null`.
String? detectContentType(Object? body) =>
    isJSONSerializable(body) ? 'application/json' : null;

String? _getMediaType(Map<String, String> headers) {
  final contentType = headers['content-type'];
  return contentType?.split(';').first.trim().toLowerCase();
}

bool _isFalsy(Object? value) =>
    value == null || value == false || value == 0 || value == '';

/// Serializes the body: JSON, form-urlencoded, or passed through untouched.
Object? getBody(BetterFetchOption options, Map<String, String> headers) {
  final body = options.body;
  if (_isFalsy(body)) return null;
  if (!isJSONSerializable(body)) return body;
  if (body is String) return body;
  if (_getMediaType(headers) == 'application/x-www-form-urlencoded' &&
      body is Map<String, Object?>) {
    return UrlSearchParams.fromMap(body).toString();
  }
  return jsonStringify(body);
}

/// The upper-case method: explicit, from a `@method/` prefix, or by body.
String getMethod(String url, [BetterFetchOption? options]) {
  final method = options?.method;
  if (method != null) return method.toUpperCase();
  final modifier = parseMethodModifier(url).method;
  if (modifier != null) return modifier.toUpperCase();
  return _isFalsy(options?.body) ? 'GET' : 'POST';
}

/// Starts the `timeout` timer, which cancels [controller].
({Timer? abortTimeout, void Function() clearTimeout}) getTimeout(
  BetterFetchOption? options,
  CancelToken? controller,
) {
  Timer? abortTimeout;
  final timeout = options?.timeout;
  if (options?.signal == null && timeout != null) {
    abortTimeout = Timer(timeout, () => controller?.cancel('timeout'));
  }
  return (
    abortTimeout: abortTimeout,
    clearTimeout: () => abortTimeout?.cancel(),
  );
}
