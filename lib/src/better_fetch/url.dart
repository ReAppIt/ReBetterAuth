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

/// The scheme, `//` and host at the start of a URL that names its own host.
final RegExp _originRe = RegExp(
  r'^[a-z][a-z\d+.-]*://[^/?#]+',
  caseSensitive: false,
);

String _withoutTrailingSlashes(String value) {
  var end = value.length;
  while (end > 0 && value[end - 1] == '/') {
    end--;
  }
  return value.substring(0, end);
}

/// Splits at the first [separator]; the remainder keeps any later ones.
(String, String?) _splitOnce(String value, String separator) {
  final index = value.indexOf(separator);
  if (index == -1) return (value, null);
  return (value.substring(0, index), value.substring(index + 1));
}

Map<String, String> _getPathParams(String path, Object? params) {
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
  return pathParams;
}

String _fillPath(String path, Object? params) {
  final pathParams = _getPathParams(path, params);
  return path
      .split('/')
      .map((segment) => _resolvePathSegment(segment, pathParams))
      .join('/');
}

String _serializeQuery(String? urlQuery, Map<String, Object?>? query) {
  final queryParams = UrlSearchParams.parse(urlQuery ?? '');
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
  final queryParamString = queryParams.toString();
  return queryParamString.isNotEmpty
      ? '?$queryParamString'.replaceAll('+', '%20')
      : '';
}

String _withoutBase(String input, String? baseURL) {
  if (baseURL == null || baseURL.isEmpty) return input;
  final basePath = '${_withoutTrailingSlashes(baseURL)}/';
  return input.startsWith(basePath) ? input.substring(basePath.length) : input;
}

/// Appends [path] and the query to [base] with one slash between them; the
/// base's query comes first and its fragment is dropped.
Object _joinURL(
  String base,
  String path,
  String? urlQuery,
  Map<String, Object?>? query,
) {
  final (baseWithoutHash, _) = _splitOnce(base, '#');
  final (basePath, baseQuery) = _splitOnce(baseWithoutHash, '?');
  final relativePath = path.replaceFirst(RegExp('^/+'), '');
  final search = _serializeQuery('${baseQuery ?? ''}&${urlQuery ?? ''}', query);
  final href = '${_withoutTrailingSlashes(basePath)}/$relativePath$search';
  return _originRe.hasMatch(href) ? Uri.parse(href) : href;
}

/// Resolves [url] against `baseURL` with `params` and `query` applied.
///
/// A [url] that names its own host keeps it; anything else is a path under
/// `baseURL`. Returns a `Uri` for absolute results, else a `String`.
Object getURL(String url, [BetterFetchOption? option]) {
  final baseURL = option?.baseURL;
  final requestPath = parseMethodModifier(url).path;
  final input = requestPath == url ? url : '/$requestPath';

  final origin = _originRe.firstMatch(input)?.group(0);
  final relative = origin != null
      ? input.substring(origin.length)
      : _withoutBase(input, baseURL);
  final (path, urlQuery) = _splitOnce(relative, '?');
  final filledPath = _fillPath(path, option?.params);
  return _joinURL(origin ?? baseURL ?? '', filledPath, urlQuery, option?.query);
}
