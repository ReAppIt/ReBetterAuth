import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:re_better_auth/src/better_fetch/error.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';

/// Hook run before a request is sent.
typedef OnRequest = FutureOr<RequestContext?> Function(RequestContext context);

/// Hook run on every response; may return a [FetchResponse] or [ResponseContext].
typedef OnResponse = FutureOr<Object?> Function(ResponseContext context);

/// Hook run on 2xx responses.
typedef OnSuccess = FutureOr<void> Function(SuccessContext context);

/// Hook run on non-2xx responses.
typedef OnError = FutureOr<void> Function(ErrorContext context);

/// Hook run before a retry.
typedef OnRetry = FutureOr<void> Function(ResponseContext context);

/// Result of [BetterFetchPlugin.init]; a `null` `options` keeps the current ones.
typedef PluginInitResult = ({String url, BetterFetchOption? options});

/// The request as sent: resolved [url], lower-case [headers], serialized [body].
class RequestContext {
  /// Creates a context; [options] carries every other request option.
  RequestContext({
    required this.url,
    required this.headers,
    required this.body,
    required this.method,
    required this.signal,
    required this.options,
  });

  /// Absolute `Uri`, or a `String` when the base URL is relative.
  Object url;

  /// Headers to send, keyed by lower-case name.
  Map<String, String> headers;

  /// Serialized body: a JSON or form string, bytes, or `null`.
  Object? body;

  /// Upper-case HTTP method.
  String method;

  /// Cancels the request.
  CancelToken signal;

  /// The options this request was built from.
  BetterFetchOption options;

  /// Base URL the request was resolved against.
  String? get baseURL => options.baseURL;

  /// Copies every field of [other] onto this context, keeping its identity.
  void assign(RequestContext other) {
    if (identical(other, this)) return;
    url = other.url;
    headers = other.headers;
    body = other.body;
    method = other.method;
    signal = other.signal;
    options = other.options;
  }
}

/// A received response and the request that produced it.
class ResponseContext {
  /// Creates a response context.
  ResponseContext({required this.response, required this.request});

  /// The response.
  final FetchResponse response;

  /// The request.
  final RequestContext request;
}

/// A 2xx response with its parsed [data].
class SuccessContext {
  /// Creates a success context.
  SuccessContext({
    required this.data,
    required this.response,
    required this.request,
  });

  /// Parsed body: JSON value, text, or bytes for binary content.
  final Object? data;

  /// The response.
  final FetchResponse response;

  /// The request.
  final RequestContext request;
}

/// A non-2xx response with its parsed [error].
class ErrorContext {
  /// Creates an error context.
  ErrorContext({
    required this.response,
    required this.responseText,
    required this.request,
    required this.error,
  });

  /// The response.
  final FetchResponse response;

  /// The raw body text.
  final String responseText;

  /// The request.
  final RequestContext request;

  /// Status plus the parsed error body.
  final BetterFetchError error;
}

/// Request lifecycle callbacks a plugin contributes.
class FetchHooks {
  /// Creates hooks; each is optional.
  const FetchHooks({
    this.onRequest,
    this.onResponse,
    this.onSuccess,
    this.onError,
    this.onRetry,
  });

  /// Runs before sending.
  final OnRequest? onRequest;

  /// Runs on every response.
  final OnResponse? onResponse;

  /// Runs on 2xx responses.
  final OnSuccess? onSuccess;

  /// Runs on non-2xx responses.
  final OnError? onError;

  /// Runs before a retry.
  final OnRetry? onRetry;
}

/// A better-fetch plugin: [init] can rewrite the request, [hooks] observe it.
class BetterFetchPlugin {
  /// Creates a plugin.
  const BetterFetchPlugin({
    required this.id,
    required this.name,
    this.description,
    this.version,
    this.hooks,
    this.init,
  });

  /// Unique plugin id.
  final String id;

  /// Human-readable name.
  final String name;

  /// Optional description.
  final String? description;

  /// Optional version.
  final String? version;

  /// Lifecycle hooks.
  final FetchHooks? hooks;

  /// Runs before anything else; the returned options feed the next plugin.
  final FutureOr<PluginInitResult> Function(
    String url,
    BetterFetchOption options,
  )?
  init;
}

/// Hooks collected for one request, per-call hooks first.
class CollectedHooks {
  /// Creates the lists, seeded with the per-call hooks of the options.
  CollectedHooks(BetterFetchOption? options)
    : onRequest = <OnRequest?>[options?.onRequest],
      onResponse = <OnResponse?>[options?.onResponse],
      onSuccess = <OnSuccess?>[options?.onSuccess],
      onError = <OnError?>[options?.onError],
      onRetry = <OnRetry?>[options?.onRetry];

  /// Request hooks in run order.
  final List<OnRequest?> onRequest;

  /// Response hooks in run order.
  final List<OnResponse?> onResponse;

  /// Success hooks in run order.
  final List<OnSuccess?> onSuccess;

  /// Error hooks in run order.
  final List<OnError?> onError;

  /// Retry hooks in run order.
  final List<OnRetry?> onRetry;
}

/// Runs every plugin `init` in order and collects the hooks.
Future<({String url, BetterFetchOption options, CollectedHooks hooks})>
initializePlugins(String url, BetterFetchOption? options) async {
  var opts = options ?? BetterFetchOption();
  final hooks = CollectedHooks(options);
  final plugins = options?.plugins;
  if (options == null || plugins == null) {
    return (url: url, options: opts, hooks: hooks);
  }
  for (final plugin in plugins) {
    final init = plugin.init;
    if (init != null) {
      final pluginRes = await init(url, opts);
      opts = pluginRes.options ?? opts;
      url = pluginRes.url;
    }
    hooks.onRequest.add(plugin.hooks?.onRequest);
    hooks.onResponse.add(plugin.hooks?.onResponse);
    hooks.onSuccess.add(plugin.hooks?.onSuccess);
    hooks.onError.add(plugin.hooks?.onError);
    hooks.onRetry.add(plugin.hooks?.onRetry);
  }
  return (url: url, options: opts, hooks: hooks);
}
