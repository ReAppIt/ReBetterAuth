import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/re_better_auth.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final version = pubspec
        .firstWhere((line) => line.startsWith('version:'))
        .split(':')
        .last
        .trim();
    expect(packageVersion, version);
  });
}
