/// Lower-case HTTP methods accepted in `@method/` URL prefixes.
const List<String> methods = <String>['get', 'post', 'put', 'patch', 'delete'];

/// Splits a `@post/path` prefix into its method and the remaining path.
({String? method, String path}) parseMethodModifier(String path) {
  if (!path.startsWith('@')) return (method: null, path: path);
  final separator = path.indexOf('/');
  final method = path.substring(1, separator == -1 ? null : separator);
  if (!methods.contains(method)) return (method: null, path: path);
  return (
    method: method,
    path: separator == -1 ? path : path.substring(separator + 1),
  );
}
