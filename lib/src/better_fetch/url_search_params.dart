import 'dart:convert';

/// Minimal port of the WHATWG `URLSearchParams` used to build query strings.
class UrlSearchParams {
  /// Creates an empty parameter list.
  UrlSearchParams();

  /// Parses `a=1&b=2`, with or without a leading `?`.
  factory UrlSearchParams.parse(String query) {
    final params = UrlSearchParams();
    final input = query.startsWith('?') ? query.substring(1) : query;
    for (final pair in input.split('&')) {
      if (pair.isEmpty) continue;
      final index = pair.indexOf('=');
      final name = index == -1 ? pair : pair.substring(0, index);
      final value = index == -1 ? '' : pair.substring(index + 1);
      params.append(_decode(name), _decode(value));
    }
    return params;
  }

  /// Creates parameters from [map]; values go through `toString()`.
  factory UrlSearchParams.fromMap(Map<String, Object?> map) {
    final params = UrlSearchParams();
    map.forEach((name, value) => params.append(name, '$value'));
    return params;
  }

  final List<(String, String)> _entries = <(String, String)>[];

  /// Adds a pair, keeping existing ones with the same [name].
  void append(String name, String value) => _entries.add((name, value));

  /// Replaces the first pair named [name] and drops the rest, or appends one.
  void set(String name, String value) {
    final index = _entries.indexWhere((entry) => entry.$1 == name);
    if (index == -1) {
      append(name, value);
      return;
    }
    _entries[index] = (name, value);
    for (var i = _entries.length - 1; i > index; i--) {
      if (_entries[i].$1 == name) _entries.removeAt(i);
    }
  }

  /// The first value for [name].
  String? get(String name) {
    for (final (key, value) in _entries) {
      if (key == name) return value;
    }
    return null;
  }

  /// Whether a pair named [name] exists.
  bool has(String name) => _entries.any((entry) => entry.$1 == name);

  @override
  String toString() =>
      _entries.map((e) => '${_encode(e.$1)}=${_encode(e.$2)}').join('&');

  static String _encode(String value) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(value)) {
      if (byte == 0x20) {
        buffer.write('+');
      } else if (_isUnescaped(byte)) {
        buffer.writeCharCode(byte);
      } else {
        buffer
          ..write('%')
          ..write(byte.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return buffer.toString();
  }

  static bool _isUnescaped(int byte) =>
      (byte >= 0x30 && byte <= 0x39) ||
      (byte >= 0x41 && byte <= 0x5A) ||
      (byte >= 0x61 && byte <= 0x7A) ||
      byte == 0x2A ||
      byte == 0x2D ||
      byte == 0x2E ||
      byte == 0x5F;

  static final RegExp _hexPair = RegExp(r'^[0-9A-Fa-f]{2}$');

  static String _decode(String value) {
    final runes = value.replaceAll('+', ' ').runes.toList();
    final bytes = <int>[];
    for (var i = 0; i < runes.length; i++) {
      final rune = runes[i];
      if (rune == 0x25 && i + 2 < runes.length) {
        final hex = String.fromCharCodes(runes, i + 1, i + 3);
        if (_hexPair.hasMatch(hex)) {
          bytes.add(int.parse(hex, radix: 16));
          i += 2;
          continue;
        }
      }
      bytes.addAll(utf8.encode(String.fromCharCode(rune)));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}
