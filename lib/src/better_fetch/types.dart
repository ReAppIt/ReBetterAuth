import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:re_better_auth/src/better_fetch/auth.dart';
import 'package:re_better_auth/src/better_fetch/error.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/better_fetch/retry.dart';

/// `{data, error}` result of a call; destructure with `final (:data, :error)`.
typedef BetterFetchResponse<T> = ({T? data, BetterFetchError? error});

/// Parses a response body; the better-auth client revives ISO dates.
typedef JsonParser = FutureOr<Object?> Function(String text);

/// Transport used for each request, the stand-in for `customFetchImpl`.
typedef FetchEsque =
    Future<FetchResponse> Function(Object url, RequestContext init);

/// Options for one request or, via `createFetch`, defaults for every request.
class BetterFetchOption {
  /// Creates request options; every field is optional.
  BetterFetchOption({
    this.method,
    this.headers,
    this.body,
    this.query,
    this.params,
    this.baseURL,
    this.timeout,
    this.retry,
    this.retryAttempt,
    this.auth,
    this.throwOnError,
    this.jsonParser,
    this.plugins,
    this.onRequest,
    this.onResponse,
    this.onSuccess,
    this.onError,
    this.onRetry,
    this.signal,
    this.customFetchImpl,
    this.catchAllError,
    this.disableSignal,
    Map<String, Object?>? extra,
  }) : extra = extra ?? <String, Object?>{};

  /// HTTP method; defaults to POST with a body and GET without.
  String? method;

  /// Request headers; `null` values are dropped.
  Map<String, String?>? headers;

  /// Body: maps and lists are sent as JSON, strings and bytes as-is.
  Object? body;

  /// Query parameters; lists repeat the key, other non-strings become JSON.
  Map<String, Object?>? query;

  /// Values for `:name` path segments, as a map or a positional list.
  Object? params;

  /// Prefix for relative URLs.
  String? baseURL;

  /// Cancels the request after this long, unless [signal] is set.
  Duration? timeout;

  /// Retry policy for non-2xx responses.
  RetryOptions? retry;

  /// How many retries already happened for this request.
  int? retryAttempt;

  /// Source of the `authorization` header.
  Auth? auth;

  /// Throws [BetterFetchError] instead of returning it (JS `throw: true`).
  bool? throwOnError;

  /// Parser for JSON and text bodies.
  JsonParser? jsonParser;

  /// Plugins that can rewrite the request and observe the response.
  List<BetterFetchPlugin>? plugins;

  /// Runs before sending; a returned context replaces fields of the current one.
  OnRequest? onRequest;

  /// Runs on every response; may return a replacement [FetchResponse].
  OnResponse? onResponse;

  /// Runs on 2xx responses with the parsed data.
  OnSuccess? onSuccess;

  /// Runs on non-2xx responses.
  OnError? onError;

  /// Runs before each retry.
  OnRetry? onRetry;

  /// Cancels the request (JS `AbortSignal`).
  CancelToken? signal;

  /// Transport override; defaults to a shared Dio instance.
  FetchEsque? customFetchImpl;

  /// Turns thrown errors into a returned status-500 error (`createFetch` only).
  bool? catchAllError;

  /// Skips the better-auth atom signals for this call (`ClientFetchOption`).
  bool? disableSignal;

  /// Extra keys plugins may read, like extra fields on a JS options object.
  Map<String, Object?> extra;

  /// Returns a shallow copy whose maps and lists can be changed independently.
  BetterFetchOption copy() => BetterFetchOption(
    method: method,
    headers: headers == null ? null : Map<String, String?>.of(headers!),
    body: _copyBody(body),
    query: query == null ? null : Map<String, Object?>.of(query!),
    params: params,
    baseURL: baseURL,
    timeout: timeout,
    retry: retry,
    retryAttempt: retryAttempt,
    auth: auth,
    throwOnError: throwOnError,
    jsonParser: jsonParser,
    plugins: plugins == null ? null : List<BetterFetchPlugin>.of(plugins!),
    onRequest: onRequest,
    onResponse: onResponse,
    onSuccess: onSuccess,
    onError: onError,
    onRetry: onRetry,
    signal: signal,
    customFetchImpl: customFetchImpl,
    catchAllError: catchAllError,
    disableSignal: disableSignal,
    extra: Map<String, Object?>.of(extra),
  );

  /// Returns `{...this, ...other}`: every non-null field of [other] wins.
  BetterFetchOption merge(BetterFetchOption? other) {
    final merged = copy();
    if (other == null) return merged;
    merged
      ..method = other.method ?? method
      ..headers = other.headers == null
          ? merged.headers
          : Map<String, String?>.of(other.headers!)
      ..body = other.body == null ? merged.body : _copyBody(other.body)
      ..query = other.query == null
          ? merged.query
          : Map<String, Object?>.of(other.query!)
      ..params = other.params ?? params
      ..baseURL = other.baseURL ?? baseURL
      ..timeout = other.timeout ?? timeout
      ..retry = other.retry ?? retry
      ..retryAttempt = other.retryAttempt ?? retryAttempt
      ..auth = other.auth ?? auth
      ..throwOnError = other.throwOnError ?? throwOnError
      ..jsonParser = other.jsonParser ?? jsonParser
      ..plugins = other.plugins == null
          ? merged.plugins
          : List<BetterFetchPlugin>.of(other.plugins!)
      ..onRequest = other.onRequest ?? onRequest
      ..onResponse = other.onResponse ?? onResponse
      ..onSuccess = other.onSuccess ?? onSuccess
      ..onError = other.onError ?? onError
      ..onRetry = other.onRetry ?? onRetry
      ..signal = other.signal ?? signal
      ..customFetchImpl = other.customFetchImpl ?? customFetchImpl
      ..catchAllError = other.catchAllError ?? catchAllError
      ..disableSignal = other.disableSignal ?? disableSignal
      ..extra = <String, Object?>{...extra, ...other.extra};
    return merged;
  }

  static Object? _copyBody(Object? body) =>
      body is Map<String, Object?> ? Map<String, Object?>.of(body) : body;
}

/// Case-insensitive response headers; repeated values join with `, `.
class FetchHeaders {
  /// Wraps [headers], whose names are matched case-insensitively.
  FetchHeaders([Map<String, List<String>>? headers])
    : _headers = <String, List<String>>{
        for (final MapEntry(:key, :value) in (headers ?? const {}).entries)
          key.toLowerCase(): List<String>.of(value),
      };

  final Map<String, List<String>> _headers;

  /// The value of [name], or `null`; repeated values are comma-joined.
  String? get(String name) {
    final values = _headers[name.toLowerCase()];
    return values == null || values.isEmpty ? null : values.join(', ');
  }

  /// Every value of [name], in order.
  List<String> getAll(String name) =>
      List<String>.unmodifiable(_headers[name.toLowerCase()] ?? const []);

  /// Whether [name] is present.
  bool has(String name) => _headers.containsKey(name.toLowerCase());

  /// All headers keyed by lower-case name.
  Map<String, List<String>> toMap() => <String, List<String>>{
    for (final MapEntry(:key, :value) in _headers.entries)
      key: List<String>.unmodifiable(value),
  };
}

/// A fully buffered HTTP response, the stand-in for the JS `Response`.
class FetchResponse {
  /// Creates a response with raw [bodyBytes].
  FetchResponse({
    required this.status,
    required this.bodyBytes,
    this.statusText = '',
    FetchHeaders? headers,
    this.url,
  }) : headers = headers ?? FetchHeaders();

  /// Creates a response whose body is [body] encoded as UTF-8.
  factory FetchResponse.text(
    String body, {
    int status = 200,
    String statusText = '',
    Map<String, String>? headers,
  }) => FetchResponse(
    status: status,
    statusText: statusText,
    bodyBytes: Uint8List.fromList(utf8.encode(body)),
    headers: FetchHeaders(<String, List<String>>{
      for (final MapEntry(:key, :value) in (headers ?? const {}).entries)
        key: <String>[value],
    }),
  );

  /// HTTP status code.
  final int status;

  /// HTTP reason phrase.
  final String statusText;

  /// Response headers.
  final FetchHeaders headers;

  /// Raw response body.
  final Uint8List bodyBytes;

  /// Final URL after redirects, when the transport reports it.
  final Uri? url;

  /// Whether [status] is in the 2xx range.
  bool get ok => status >= 200 && status < 300;

  /// The body decoded as UTF-8.
  String text() => utf8.decode(bodyBytes, allowMalformed: true);
}
