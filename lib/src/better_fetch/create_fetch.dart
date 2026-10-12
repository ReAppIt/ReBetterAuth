import 'package:re_better_auth/src/better_fetch/error.dart';
import 'package:re_better_auth/src/better_fetch/fetch.dart';
import 'package:re_better_auth/src/better_fetch/plugins.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/better_fetch/utils.dart';

/// Merges the instance `query` into each request (schema validation not ported).
BetterFetchPlugin applySchemaPlugin(BetterFetchOption config) =>
    BetterFetchPlugin(
      id: 'apply-schema',
      name: 'Apply Schema',
      version: '1.0.0',
      init: (url, options) {
        final defaults = config.query;
        if (defaults == null) return (url: url, options: options);
        final opts = options.copy()
          ..query = <String, Object?>{...defaults, ...?options.query};
        return (url: url, options: opts);
      },
    );

/// A configured `$fetch`: call it like a function with a URL and options.
class BetterFetch {
  BetterFetch._(this.config);

  /// Defaults merged under every call's options.
  final BetterFetchOption config;

  /// Sends [url] with [options] merged over [config]; see [betterFetch].
  Future<BetterFetchResponse<T>> call<T>(
    String url, [
    BetterFetchOption? options,
  ]) async {
    final opts = config.merge(options)
      ..headers = mergeHeaders([config.headers, options?.headers])
      ..plugins = <BetterFetchPlugin>[
        ...?config.plugins,
        applySchemaPlugin(config),
        ...?options?.plugins,
      ];
    if (config.catchAllError ?? false) {
      try {
        return await betterFetch<T>(url, opts);
      } on Object catch (error) {
        return (
          data: null,
          error: BetterFetchError(500, 'Fetch Error', <String, Object?>{
            'message':
                'Fetch related error. Captured by catchAllError option. See error property for more details.',
            'error': error,
          }),
        );
      }
    }
    return betterFetch<T>(url, opts);
  }
}

/// Creates a `$fetch` with [config] applied to every request.
BetterFetch createFetch([BetterFetchOption? config]) =>
    BetterFetch._(config ?? BetterFetchOption());
