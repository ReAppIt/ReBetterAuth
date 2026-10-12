import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_better_auth/src/client_storage.dart';

import '../support/fakes.dart';

const String key = 'scenecutai_cookie';
final String previousValue = jsonEncode(<String, Object?>{
  'better-auth.session_token': <String, Object?>{'value': 'old-session-token'},
  'better-auth.session_data': <String, Object?>{'value': 'x' * 2000},
});

/// Pauses the first read of [chunkKey] until `resume` is called.
({Future<void> reading, void Function() resume}) pauseNextStorageRead(
  MemoryStorage backing,
  String chunkKey,
) {
  final paused = Completer<void>();
  final started = Completer<void>();
  var pauseRead = true;
  backing.onGet = (name) async {
    if (name == chunkKey && pauseRead) {
      pauseRead = false;
      started.complete();
      await paused.future;
    }
    return backing.map[name];
  };
  return (reading: started.future, resume: paused.complete);
}

void main() {
  test('normalizes colons in names via the storage adapter', () async {
    final backing = MemoryStorage();
    final storage = storageAdapter(backing);
    await storage.setItemAsync('better-auth:session_token', '456');
    expect(backing.map.containsKey('better-auth_session_token'), isTrue);
    expect(backing.map.containsKey('better-auth:session_token'), isFalse);
    expect(backing.setCalls.last, ('better-auth_session_token', '456'));
  });

  test('round-trips a value larger than the per-write storage limit', () async {
    const writeLimit = 2048;
    final backing = MemoryStorage();
    backing.onSet = (name, value) async {
      if (value.length > writeLimit) {
        throw StateError('value exceeds storage limit');
      }
      backing.map[name] = value;
    };
    final storage = storageAdapter(backing);
    final large = 'x' * 10000;

    await storage.setItemAsync('better-auth_cookie', large);
    for (final value in backing.map.values) {
      expect(value.length, lessThanOrEqualTo(writeLimit));
    }
    expect(backing.map.length, greaterThan(1));
    expect(await storage.getItemAsync('better-auth_cookie'), large);
  });

  test('keeps Unicode chunks within the storage byte limit', () async {
    final backing = MemoryStorage();
    final storage = storageAdapter(backing);
    final value = '${'x' * 1799}🔐${'🙂' * 1000}';

    await storage.setItemAsync('better-auth_cookie', value);
    for (final chunk in backing.map.values) {
      expect(utf8.encode(chunk).length, lessThanOrEqualTo(1800));
    }
    expect(await storage.getItemAsync('better-auth_cookie'), value);
  });

  test(
    'stops when a multibyte value needs chunks and the base read fails',
    () async {
      final logs = captureSevereLogs();
      final backing = MemoryStorage()
        ..onGet = (_) async => throw StateError('read unavailable');
      final storage = storageAdapter(backing);

      await storage.setItemAsync('better-auth_cookie', '한' * 700);
      expect(backing.setCalls, isEmpty);
      expect(logs, hasLength(1));
    },
  );

  test(
    'stores a value within the limit under the base key unchanged',
    () async {
      final backing = MemoryStorage();
      final storage = storageAdapter(backing);
      final small = jsonEncode(<String, Object?>{'token': 'abc'});

      await storage.setItemAsync('better-auth_cookie', small);
      expect(backing.map['better-auth_cookie'], small);
      expect(backing.map.length, 1);
      expect(await storage.getItemAsync('better-auth_cookie'), small);
    },
  );

  test('reads back a value written before chunking existed', () async {
    final legacy = jsonEncode(<String, Object?>{'legacy': true});
    final storage = storageAdapter(
      MemoryStorage({'better-auth_cookie': legacy}),
    );
    expect(await storage.getItemAsync('better-auth_cookie'), legacy);
  });

  test('reads values written with the legacy chunk marker', () async {
    final storage = storageAdapter(
      MemoryStorage({
        'better-auth_cookie': '${chunkMarker}2',
        'better-auth_cookie.0': 'legacy-',
        'better-auth_cookie.1': 'value',
      }),
    );
    expect(await storage.getItemAsync('better-auth_cookie'), 'legacy-value');
  });

  test('fails closed when a chunk is missing', () async {
    final storage = storageAdapter(
      MemoryStorage({
        'better-auth_cookie': '${chunkMarker}2:0',
        'better-auth_cookie.0.0': 'first chunk',
      }),
    );
    expect(await storage.getItemAsync('better-auth_cookie'), isNull);
  });

  group('chunked storage consistency', () {
    MemoryStorage slowBacking() {
      final backing = MemoryStorage();
      backing
        ..onGet = (name) async {
          await Future<void>.delayed(Duration.zero);
          return backing.map[name];
        }
        ..onSet = (name, value) async {
          await Future<void>.delayed(Duration.zero);
          backing.map[name] = value;
        };
      return backing;
    }

    for (final failedWrite in <int>[1, 2, 3, 4, 5]) {
      test(
        'preserves the previous value when async write $failedWrite fails',
        () async {
          final backing = MemoryStorage();
          var writeIndex = 0;
          var failing = false;
          backing.onSet = (name, value) async {
            if (failing && ++writeIndex == failedWrite) {
              throw StateError('interrupted');
            }
            backing.map[name] = value;
          };
          final storage = storageAdapter(backing);
          await storage.setItemAsync('better-auth_cookie', 'a' * 3000);
          final previous = 'b' * 5000;
          await storage.setItemAsync('better-auth_cookie', previous);
          writeIndex = 0;
          failing = true;
          final logs = captureSevereLogs();

          await storage.setItemAsync('better-auth_cookie', 'c' * 5000);
          expect(logs, hasLength(1));
          failing = false;
          expect(await storage.getItemAsync('better-auth_cookie'), previous);
        },
      );
    }

    test('disables fallback while its slot is being overwritten', () async {
      final backing = MemoryStorage();
      var writeIndex = 0;
      var failing = false;
      backing.onSet = (name, value) async {
        if (failing && ++writeIndex == 3) throw StateError('interrupted');
        backing.map[name] = value;
      };
      final storage = storageAdapter(backing);
      await storage.setItemAsync('better-auth_cookie', 'a' * 3000);
      await storage.setItemAsync('better-auth_cookie', 'b' * 5000);
      writeIndex = 0;
      failing = true;
      captureSevereLogs();

      await storage.setItemAsync('better-auth_cookie', 'c' * 5000);
      backing.map.remove('better-auth_cookie.1.1');
      expect(await storage.getItemAsync('better-auth_cookie'), isNull);
    });

    test('falls back when the active slot is incomplete', () async {
      final backing = MemoryStorage();
      final storage = storageAdapter(backing);
      final previous = 'a' * 3000;
      await storage.setItemAsync('better-auth_cookie', previous);
      await storage.setItemAsync('better-auth_cookie', 'b' * 5000);
      backing.map.remove('better-auth_cookie.1.1');
      expect(await storage.getItemAsync('better-auth_cookie'), previous);
    });

    test('finishes an earlier read before a chunked overwrite', () async {
      final storage = storageAdapter(slowBacking());
      await storage.setItemAsync('better-auth_cookie', 'a' * 3000);
      final previous = 'b' * 5000;
      await storage.setItemAsync('better-auth_cookie', previous);

      final read = storage.getItemAsync('better-auth_cookie');
      final write = storage.setItemAsync('better-auth_cookie', 'c' * 5000);
      final stored = await read;
      await write;
      expect(stored, previous);
    });

    test('serializes concurrent chunked overwrites', () async {
      final storage = storageAdapter(slowBacking());
      final third = 'c' * 5000;
      await Future.wait(<Future<void>>[
        storage.setItemAsync('better-auth_cookie', 'a' * 5000),
        storage.setItemAsync('better-auth_cookie', 'b' * 5000),
        storage.setItemAsync('better-auth_cookie', third),
      ]);
      expect(await storage.getItemAsync('better-auth_cookie'), third);
    });

    test('serializes writes across adapters sharing storage', () async {
      final backing = MemoryStorage();
      var activeWrites = 0;
      var peakWrites = 0;
      backing.onSet = (name, value) async {
        activeWrites++;
        if (activeWrites > peakWrites) peakWrites = activeWrites;
        await Future<void>.delayed(Duration.zero);
        backing.map[name] = value;
        activeWrites--;
      };
      final first = storageAdapter(backing);
      final second = storageAdapter(backing);

      await Future.wait(<Future<void>>[
        first.setItemAsync('better-auth_cookie', 'a' * 5000),
        second.setItemAsync('better-auth_cookie', 'b' * 5000),
      ]);
      expect(peakWrites, 1);

      peakWrites = 0;
      await Future.wait(<Future<void>>[
        first.setItemAsync('first_cookie', 'a' * 5000),
        second.setItemAsync('second_cookie', 'b' * 5000),
      ]);
      expect(peakWrites, 2);
    });

    test('does not coordinate independent storage backends', () async {
      final logs = captureSevereLogs();
      final firstBacking = slowBacking();
      final secondBacking = MemoryStorage();
      final first = storageAdapter(firstBacking);
      final second = storageAdapter(secondBacking);

      final write = first.setItemAsync('better-auth_cookie', 'a' * 5000);
      await second.setItemAsync('better-auth_cookie', 'independent');
      await write;
      expect(logs, isEmpty);
      expect(await second.getItemAsync('better-auth_cookie'), 'independent');
    });

    test('keeps atomic updates internal to the client', () {
      final storage = storageAdapter(MemoryStorage());
      expect(storage, isNot(isA<ManagedStorage>()));
    });

    test('rejects excessive chunk counts', () async {
      final logs = captureSevereLogs();
      final backing = MemoryStorage({'better-auth_cookie': 'previous'});
      final storage = storageAdapter(backing);

      await storage.setItemAsync('better-auth_cookie', 'x' * 180001);
      expect(logs, hasLength(1));
      expect(await storage.getItemAsync('better-auth_cookie'), 'previous');

      backing.map['better-auth_cookie'] = '${chunkMarker}101:0';
      backing.getCalls.clear();
      expect(await storage.getItemAsync('better-auth_cookie'), isNull);
      expect(backing.getCalls, hasLength(1));
    });
  });

  group('obsolete storage chunks', () {
    test('retries orphan cleanup without leaving an unscannable gap', () async {
      final backing = MemoryStorage({
        key: '${chunkMarker}2:0',
        '$key.0.0': 'first',
        '$key.0.1': 'second',
        '$key.0.2': 'old-secret',
      });
      var failing = true;
      backing.onSet = (name, value) async {
        if (failing && name == '$key.0.2') throw StateError('cleanup failed');
        backing.map[name] = value;
      };
      final storage = storageAdapter(backing);
      final logs = captureSevereLogs();

      await storage.setItemAsync(key, '{}');
      expect(backing.map[key], '{}');
      expect(backing.map['$key.0.0'], 'first');
      expect(backing.map['$key.0.1'], 'second');
      expect(backing.map['$key.0.2'], 'old-secret');
      expect(logs, hasLength(1));

      failing = false;
      await storage.setItemAsync(key, '{}');
      expect(backing.map['$key.0.0'], '');
      expect(backing.map['$key.0.1'], '');
      expect(backing.map['$key.0.2'], '');
    });

    test(
      'persists a short value when reading the previous marker fails',
      () async {
        final backing = MemoryStorage()
          ..onGet = (_) async => throw StateError('read unavailable');
        final storage = storageAdapter(backing);
        final logs = captureSevereLogs();

        await storage.setItemAsync(key, '{}');
        expect(backing.map[key], '{}');
        expect(logs, hasLength(1));
      },
    );

    test('clears known chunks beyond a missing chunk', () async {
      final backing = MemoryStorage({
        key: '${chunkMarker}3',
        '$key.0': 'old-first',
        '$key.2': 'old-secret',
      });
      await storageAdapter(backing).setItemAsync(key, '{}');
      expect(backing.map['$key.2'] ?? '', '');
    });

    test(
      'uses the marker to clear incomplete chunks after the sweep',
      () async {
        final backing = MemoryStorage();
        final storage = storageAdapter(backing);
        await storage.setItemAsync(key, 'a' * 5000);
        backing.map.remove('$key.0.1');
        backing.getCalls.clear();

        await storage.setItemAsync(key, '{}');
        expect(backing.getCalls, hasLength(1));
        expect(backing.map['$key.0.0'], '');
        expect(backing.map['$key.0.2'], '');
      },
    );

    for (final (name, marker, initialValue, chunkKeys, value)
        in <(String, String, String, List<String>, String)>[
          (
            'legacy migration',
            '${chunkMarker}2',
            previousValue,
            ['$key.0', '$key.1'],
            previousValue.replaceFirst(
              'old-session-token',
              'new-session-token',
            ),
          ),
          (
            'legacy clear',
            '${chunkMarker}2',
            previousValue,
            ['$key.0', '$key.1'],
            '{}',
          ),
          (
            'slotted clear with fallback',
            '${chunkMarker}2:1:2',
            previousValue,
            ['$key.1.0', '$key.1.1', '$key.0.0', '$key.0.1'],
            '{}',
          ),
          ('a lost legacy marker', '{}', '{}', ['$key.0', '$key.1'], '{}'),
          (
            'a lost slotted marker',
            '{}',
            '{}',
            ['$key.1.0', '$key.1.1', '$key.0.0', '$key.0.1'],
            '{}',
          ),
        ]) {
      test('clears obsolete bytes after $name', () async {
        final backing = MemoryStorage({key: marker});
        for (final (index, chunkKey) in chunkKeys.indexed) {
          final start = (index % 2) * 1800;
          final end = start + 1800 > previousValue.length
              ? previousValue.length
              : start + 1800;
          backing.map[chunkKey] = previousValue.substring(start, end);
        }
        final storage = storageAdapter(backing);

        expect(await storage.getItemAsync(key), initialValue);
        await storage.setItemAsync(key, value);
        expect(await storage.getItemAsync(key), value);
        expect(
          chunkKeys.map((chunkKey) => backing.map[chunkKey] ?? '').toList(),
          chunkKeys.map((_) => '').toList(),
        );
      });
    }

    test("clears a reused slot's tail while preserving recovery", () async {
      final backing = MemoryStorage();
      final storage = storageAdapter(backing);
      await storage.setItemAsync(key, 'a' * 5000);
      await storage.setItemAsync(key, previousValue);
      final nextValue = 'b' * 2000;
      await storage.setItemAsync(key, nextValue);

      expect(await storage.getItemAsync(key), nextValue);
      expect(backing.map['$key.0.2'], '');
      backing.map.remove('$key.0.0');
      expect(await storage.getItemAsync(key), previousValue);
    });

    test(
      'preserves legacy chunks when the replacement cannot be committed',
      () async {
        final backing = MemoryStorage({
          key: '${chunkMarker}2',
          '$key.0': previousValue.substring(0, 1800),
          '$key.1': previousValue.substring(1800),
        });
        backing.onSet = (name, value) async {
          if (name == key) throw StateError('interrupted commit');
          backing.map[name] = value;
        };
        final storage = storageAdapter(backing);
        final logs = captureSevereLogs();

        await storage.setItemAsync(key, 'b' * 3000);
        expect(logs, hasLength(1));
        expect(await storage.getItemAsync(key), previousValue);
      },
    );

    test(
      'retries interrupted cleanup without losing the committed value',
      () async {
        final backing = MemoryStorage({
          key: '${chunkMarker}2',
          '$key.0': previousValue.substring(0, 1800),
          '$key.1': previousValue.substring(1800),
        });
        var interrupted = false;
        backing.onSet = (name, value) async {
          if (name == '$key.0' && !interrupted) {
            interrupted = true;
            throw StateError('interrupted cleanup');
          }
          backing.map[name] = value;
        };
        final storage = storageAdapter(backing);
        final logs = captureSevereLogs();

        await storage.setItemAsync(key, '{}');
        expect(logs, hasLength(1));
        expect(await storage.getItemAsync(key), '{}');
        expect(backing.map['$key.1'], '');

        await storage.setItemAsync(key, '{}');
        expect(backing.map['$key.0'], '');
        expect(backing.map['$key.1'], '');
      },
    );

    test('stops orphan probing at the first empty chunk', () async {
      final backing = MemoryStorage();
      await storageAdapter(backing).setItemAsync(key, '{}');
      expect(backing.getCalls, hasLength(4));

      backing.getCalls.clear();
      await storageAdapter(backing).setItemAsync(key, '{}');
      expect(backing.getCalls, hasLength(1));

      final nextBacking = MemoryStorage(backing.map);
      await storageAdapter(nextBacking).setItemAsync(key, '{}');
      expect(nextBacking.getCalls, hasLength(4));
    });

    test('retries partially cleared orphan chunks on the next write', () async {
      final backing = MemoryStorage({
        '$key.0': 'first',
        '$key.1': 'second',
        '$key.2': 'third',
      });
      var failing = true;
      backing.onSet = (name, value) async {
        if (name == '$key.1' && failing) throw StateError('cleanup failed');
        backing.map[name] = value;
      };
      final storage = storageAdapter(backing);
      final logs = captureSevereLogs();

      await storage.setItemAsync(key, '{}');
      expect(backing.map['$key.0'], 'first');
      expect(backing.map['$key.1'], 'second');
      expect(backing.map['$key.2'], '');
      expect(logs, hasLength(1));

      failing = false;
      await storage.setItemAsync(key, 'next');
      expect(backing.map['$key.0'], '');
      expect(backing.map['$key.1'], '');
      expect(backing.map[key], 'next');
    });

    test('continues queued writes after a read fails', () async {
      final backing = MemoryStorage();
      var failOnce = true;
      backing.onGet = (name) async {
        if (failOnce) {
          failOnce = false;
          throw StateError('read failed');
        }
        return backing.map[name];
      };
      final storage = storageAdapter(backing);
      final read = storage.getItemAsync(key);
      final write = storage.setItemAsync(key, 'next');
      await expectLater(read, throwsStateError);
      await write;
      expect(await storage.getItemAsync(key), 'next');
    });

    test(
      'finishes reading before another adapter can reuse its slot',
      () async {
        final backing = MemoryStorage();
        final storage = storageAdapter(backing);
        final other = storageAdapter(backing);
        await storage.setItemAsync(key, previousValue);
        final pause = pauseNextStorageRead(backing, '$key.0.1');
        backing.setCalls.clear();

        final read = storage.getItemAsync(key);
        await pause.reading;
        final firstWrite = other.setItemAsync(key, 'b' * 3000);
        final secondWrite = other.setItemAsync(key, 'c' * 3000);
        await other.setItemAsync('independent_cookie', '{}');
        final overlappingWrites = backing.setCalls
            .where((call) => call.$1.startsWith(key))
            .length;
        pause.resume();

        final value = await read;
        await Future.wait(<Future<void>>[firstWrite, secondWrite]);
        expect(overlappingWrites, 0);
        expect(value, previousValue);
      },
    );

    for (final (name, marker, prefix) in <(String, String, String)>[
      ('legacy', '${chunkMarker}2', key),
      ('active', '${chunkMarker}2:0', '$key.0'),
      ('fallback', '${chunkMarker}2:1:2', '$key.0'),
    ]) {
      test('finishes a $name read before cleanup', () async {
        final backing = MemoryStorage({
          key: marker,
          '$prefix.0': previousValue.substring(0, 1800),
          '$prefix.1': previousValue.substring(1800),
        });
        final pause = pauseNextStorageRead(backing, '$prefix.1');
        final storage = storageAdapter(backing);

        final read = storage.getItemAsync(key);
        await pause.reading;
        final write = storage.setItemAsync(key, '{}');
        pause.resume();
        expect(await read, previousValue);
        await write;
        expect(await storage.getItemAsync(key), '{}');
      });
    }
  });

  test('shrinks from chunked to a single value without stale chunks', () async {
    final storage = storageAdapter(MemoryStorage());
    await storage.setItemAsync('better-auth_cookie', 'z' * 5000);
    await storage.setItemAsync('better-auth_cookie', 'small');
    expect(await storage.getItemAsync('better-auth_cookie'), 'small');
  });

  test('logs instead of throwing when the backend rejects a write', () async {
    final logs = captureSevereLogs();
    final storage = storageAdapter(
      MemoryStorage()
        ..onSet = (_, _) async => throw StateError('keychain rejected write'),
    );
    await expectLater(
      storage.setItemAsync('better-auth_cookie', 'value'),
      completes,
    );
    expect(logs, hasLength(1));
  });
}
