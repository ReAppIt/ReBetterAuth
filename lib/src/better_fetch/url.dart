import 'package:re_better_auth/src/better_fetch/method.dart';
import 'package:re_better_auth/src/better_fetch/types.dart';
import 'package:re_better_auth/src/better_fetch/url_search_params.dart';
import 'package:re_better_auth/src/better_fetch/utils.dart';

bool _isReservedPathSegment(String value) => value == '.' || value == '..';

String _encodeLiteralPathSegment(String segment) =>
    segment.split(':').map(Uri.encodeComponent).join(':');

String _resolvePathSegment(String segment, Map<String, String> pathParams) {
  final pathParam = pathParams[segment];
  if (pathParam == null) return _encodeLiteralPathSegment(segment);
  if (_isReservedPathSegment(pathParam)) {
    throw ArgumentError('Path parameters cannot be reserved path segments');
  }
  return Uri.encodeComponent(pathParam);
}

/// Resolves [url] against `baseURL` with `params` and `query` applied.
///
/// Returns a `Uri` for absolute bases and a `String` for relative ones.
Object getURL(String url, [BetterFetchOption? option]) {
  final baseURL = option?.baseURL;
  final params = option?.params;
  final query = option?.query;
  var basePath = url.startsWith('http')
      ? url.split('/').take(3).join('/')
      : (baseURL == null || baseURL.isEmpty ? '' : baseURL);

  final requestPath = parseMethodModifier(url).path;
  if (requestPath != url) url = '/$requestPath';

  if (!basePath.endsWith('/')) basePath += '/';
  final parts = url.replaceFirst(basePath, '').split('?');
  var path = parts[0];
  final queryParams = UrlSearchParams.parse(parts.length > 1 ? parts[1] : '');
  query?.forEach((key, value) {
    if (value == null) return;
    if (value is String) {
      queryParams.set(key, value);
    } else if (value is List<Object?>) {
      for (final item in value) {
        queryParams.append(key, '$item');
      }
    } else {
      queryParams.set(key, jsonStringify(value));
    }
  });

  final pathParams = <String, String>{};
  if (params is List<Object?>) {
    final paramPaths = path.split('/').where((p) => p.startsWith(':')).toList();
    for (final (index, key) in paramPaths.indexed) {
      pathParams[key] = index < params.length
          ? '${params[index]}'
          : 'undefined';
    }
  } else if (params is Map<String, Object?>) {
    params.forEach((key, value) => pathParams[':$key'] = '$value');
  }

  path = path
      .split('/')
      .map((segment) => _resolvePathSegment(segment, pathParams))
      .join('/')
      .replaceFirst(RegExp('^/+'), '');
  var queryParamString = queryParams.toString();
  queryParamString = queryParamString.isNotEmpty
      ? '?$queryParamString'.replaceAll('+', '%20')
      : '';
  if (!basePath.startsWith('http')) {
    return '$basePath$path$queryParamString';
  }
  return Uri.parse(basePath).resolve('$path$queryParamString');
}
