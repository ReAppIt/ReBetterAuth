import 'package:re_better_auth/src/better_auth/core/error.dart';

/// Removes every trailing `/` from [value].
String trimTrailingSlashes(String value) {
  var end = value.length;
  while (end > 0 && value.codeUnitAt(end - 1) == 0x2F) {
    end--;
  }
  return end == value.length ? value : value.substring(0, end);
}

bool _checkHasPath(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    throw BetterAuthError(
      'Invalid base URL: $url. Please provide a valid base URL.',
    );
  }
  final pathname = trimTrailingSlashes(uri.path);
  return pathname.isNotEmpty && pathname != '/';
}

void _assertHasProtocol(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    throw BetterAuthError(
      'Invalid base URL: $url. Please provide a valid base URL.',
    );
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw BetterAuthError(
      "Invalid base URL: $url. URL must include 'http://' or 'https://'",
    );
  }
}

/// Appends [path] (default `/api/auth`) unless [url] already has a path.
String withPath(String url, [String? path]) {
  _assertHasProtocol(url);
  if (_checkHasPath(url)) return url;
  final trimmedUrl = trimTrailingSlashes(url);
  final authPath = path ?? '/api/auth';
  if (authPath.isEmpty || authPath == '/') return trimmedUrl;
  return '$trimmedUrl${authPath.startsWith('/') ? authPath : '/$authPath'}';
}

/// The auth base URL for [url] and [path], or `null` without a [url].
String? getBaseURL(String? url, [String? path]) {
  if (url != null && url.isNotEmpty) return withPath(url, path);
  return null;
}
