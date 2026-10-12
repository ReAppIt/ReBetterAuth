import 'package:dio/dio.dart' show CancelToken;
import 'package:re_better_auth/src/better_fetch/error.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/better_fetch/retry.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/better_fetch/url.dart';
import 'package:re_better_auth/src/better_fetch/utils.dart';

/// Sends one request through plugins and hooks; returns `{data, error}`.
/// HTTP errors land in `error` (thrown with `throwOnError`); transport errors
/// are rethrown.
Future<BetterFetchResponse<T>> betterFetch<T>(
  String url, [
  BetterFetchOption? options,
]) async {
  final initialized = await initializePlugins(url, options);
  final hooks = initialized.hooks;
  final opts = initialized.options;
  final fetch = getFetch(opts);
  final controller = CancelToken();
  final signal = opts.signal ?? controller;
  final requestUrl = getURL(initialized.url, opts);
  final headers = await getHeaders(opts);
  final body = getBody(opts, headers);
  final method = getMethod(initialized.url, opts);
  // One stable object for the whole request, even when hooks return copies.
  final context = RequestContext(
    url: requestUrl,
    headers: headers,
    body: body,
    method: method,
    signal: signal,
    options: opts,
  );
  for (final onRequest in hooks.onRequest) {
    if (onRequest == null) continue;
    final res = await onRequest(context);
    if (res != null) context.assign(res);
  }

  final timeout = getTimeout(opts, controller);
  FetchResponse response;
  try {
    response = await fetch(context.url, context);
  } finally {
    timeout.clearTimeout();
  }

  for (final onResponse in hooks.onResponse) {
    if (onResponse == null) continue;
    final r = await onResponse(
      ResponseContext(response: response, request: context),
    );
    if (r is FetchResponse) {
      response = r;
    } else if (r is ResponseContext) {
      response = r.response;
    }
  }

  if (response.ok) {
    if (context.method == 'HEAD') return (data: '' as T?, error: null);
    final responseType = detectResponseType(response);
    Object? data;
    if (responseType == 'json' || responseType == 'text') {
      final parser = context.options.jsonParser ?? jsonParse;
      data = await parser(response.text());
    } else {
      data = response.bodyBytes;
    }
    for (final onSuccess in hooks.onSuccess) {
      if (onSuccess == null) continue;
      await onSuccess(
        SuccessContext(data: data, response: response, request: context),
      );
    }
    return (data: data as T?, error: null);
  }

  final parser = options?.jsonParser ?? jsonParse;
  final responseText = response.text();
  final isJSONResponse = isJSONParsable(responseText);
  final errorObject = isJSONResponse ? await parser(responseText) : null;
  final error = BetterFetchError(
    response.status,
    response.statusText,
    errorObject,
  );
  for (final onError in hooks.onError) {
    if (onError == null) continue;
    await onError(
      ErrorContext(
        response: response,
        responseText: responseText,
        request: context,
        error: error,
      ),
    );
  }

  final retry = options?.retry;
  if (options != null && retry != null) {
    final retryStrategy = createRetryStrategy(retry);
    final retryAttempt = options.retryAttempt ?? 0;
    if (await retryStrategy.shouldAttemptRetry(retryAttempt, response)) {
      for (final onRetry in hooks.onRetry) {
        if (onRetry == null) continue;
        await onRetry(ResponseContext(response: response, request: context));
      }
      await Future<void>.delayed(retryStrategy.getDelay(retryAttempt));
      return betterFetch<T>(
        url,
        options.copy()..retryAttempt = retryAttempt + 1,
      );
    }
  }

  if (options?.throwOnError ?? false) {
    throw BetterFetchError(
      response.status,
      response.statusText,
      isJSONResponse ? errorObject : responseText,
    );
  }
  return (data: null, error: error);
}
