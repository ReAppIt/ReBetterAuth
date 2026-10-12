import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

void main() {
  group('parseJSON', () {
    for (final (name, input, expected) in <(String, String, String)>[
      ('newline', r'"hello\nworld"', 'hello\nworld'),
      ('tab', r'"with\ttab"', 'with\ttab'),
      ('unicode escape', r'"café"', 'café'),
      ('backslash', r'"back\\slash"', r'back\slash'),
      ('escaped quote', r'"quote\"inside"', 'quote"inside'),
    ]) {
      test('decodes $name inside quoted strings', () {
        expect(parseJSON(input), expected);
      });
    }

    for (final value in <String>[
      'plain',
      'with\nnewline',
      'with\ttab',
      r'with \ backslash',
      'with " quote',
      'unicode: 안녕하세요',
    ]) {
      test('round-trips ${jsonEncode(value)} through jsonEncode', () {
        expect(parseJSON(jsonEncode(value)), value);
      });
    }

    test('still parses objects and arrays', () {
      expect(parseJSON('{"a":1,"b":"x"}'), {'a': 1, 'b': 'x'});
      expect(parseJSON('[1,2,3]'), [1, 2, 3]);
    });

    for (final (input, expected) in <(String, Object?)>[
      ('true', true),
      ('false', false),
      ('null', null),
      ('42', 42),
    ]) {
      test('parses primitive $input', () {
        expect(parseJSON(input), expected);
      });
    }

    test('preserves non-JSON strings as-is when not strict', () {
      expect(parseJSON('not json', strict: false), 'not json');
    });

    test('throws on non-JSON strings when strict', () {
      expect(() => parseJSON('not json'), throwsFormatException);
    });

    test('revives ISO dates, applying offsets', () {
      final parsed =
          parseJSON(
                '{"a":"2026-10-12T10:00:00.000Z","b":"2026-10-12T12:00:00+02:00"}',
              )!
              as Map<String, Object?>;
      expect(parsed['a'], DateTime.utc(2026, 10, 12, 10));
      expect(parsed['b'], DateTime.utc(2026, 10, 12, 10));
    });
  });
}
