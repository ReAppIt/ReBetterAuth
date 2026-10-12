import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:re_better_auth/src/better_auth/core/logger.dart';
import 'package:re_better_auth/src/plugins/last_login_method.dart';

/// Storage for cookies and the cached session (`ExpoClientStorage`, async).
/// Access is serialized per instance, so share one between clients.
abstract interface class FlutterClientStorage {
  /// Reads [key], or `null` when absent.
  Future<String?> getItemAsync(String key);

  /// Writes [value] under [key].
  Future<void> setItemAsync(String key, String value);
}

/// [FlutterClientStorage] on flutter_secure_storage: Keychain on iOS,
/// Keystore-encrypted SharedPreferences on Android.
class SecureStore implements FlutterClientStorage, LastLoginMethodStorage {
  /// Wraps [storage]; pass a configured instance to change platform options.
  const SecureStore([this.storage = const FlutterSecureStorage()]);

  /// The underlying secure storage.
  final FlutterSecureStorage storage;

  @override
  Future<String?> getItemAsync(String key) => storage.read(key: key);

  @override
  Future<void> setItemAsync(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> deleteItemAsync(String key) => storage.delete(key: key);
}

/// Replaces `:` with `_`; secure-store keys allow only `[A-Za-z0-9._-]`.
String normalizeCookieName(String name) => name.replaceAll(':', '_');

/// UTF-8 byte budget per stored chunk; larger values span several keys.
const int storageValueLimit = 1800;

/// Upper bound on chunks per value.
const int maxStorageChunks = 100;

int _getUtf8ByteLength(int codePoint) {
  if (codePoint <= 0x7F) return 1;
  if (codePoint <= 0x7FF) return 2;
  if (codePoint <= 0xFFFF) return 3;
  return 4;
}

List<String> _splitStorageValue(String value) {
  final chunks = <String>[];
  var start = 0;
  var end = 0;
  var bytes = 0;
  for (final codePoint in value.runes) {
    final characterBytes = _getUtf8ByteLength(codePoint);
    if (bytes + characterBytes > storageValueLimit) {
      chunks.add(value.substring(start, end));
      start = end;
      bytes = 0;
    }
    bytes += characterBytes;
    end += codePoint > 0xFFFF ? 2 : 1;
  }
  chunks.add(value.substring(start));
  return chunks;
}

/// Marks a base key whose value is split across chunk keys.
const String chunkMarker = '\u0001ba-chunks:';

const List<int?> _chunkSlots = <int?>[null, 0, 1];

final class _ChunkMarker {
  const _ChunkMarker(this.count, this.slot, this.fallbackCount);

  final int count;
  final int? slot;
  final int? fallbackCount;
}

int? _parseChunkCount(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  final count = trimmed.isEmpty ? 0 : num.tryParse(trimmed);
  if (count == null || !count.isFinite || count != count.truncate()) {
    return null;
  }
  if (count < 1 || count > maxStorageChunks) return null;
  return count.toInt();
}

_ChunkMarker? _parseChunkMarker(String baseValue) {
  final parts = baseValue.substring(chunkMarker.length).split(':');
  if (parts.length > 3) return null;
  final count = _parseChunkCount(parts[0]);
  if (count == null) return null;
  final slotValue = parts.length > 1 ? parts[1] : null;
  final fallbackCountValue = parts.length > 2 ? parts[2] : null;
  if (slotValue == null) {
    return fallbackCountValue == null ? _ChunkMarker(count, null, null) : null;
  }
  if (slotValue != '0' && slotValue != '1') return null;
  final fallbackCount = _parseChunkCount(fallbackCountValue);
  if (fallbackCountValue != null && fallbackCount == null) return null;
  return _ChunkMarker(count, slotValue == '0' ? 0 : 1, fallbackCount);
}

String _getChunkKey(String key, _ChunkMarker marker, int index) =>
    marker.slot == null ? '$key.$index' : '$key.${marker.slot}.$index';

int _getOtherSlot(int slot) => slot == 0 ? 1 : 0;

String _serializeChunkMarker(_ChunkMarker marker) {
  if (marker.slot == null) return '$chunkMarker${marker.count}';
  final fallback = marker.fallbackCount == null
      ? ''
      : ':${marker.fallbackCount}';
  return '$chunkMarker${marker.count}:${marker.slot}$fallback';
}

Future<String?> _readChunksAsync(
  FlutterClientStorage storage,
  String key,
  _ChunkMarker marker,
) async {
  final value = StringBuffer();
  for (var i = 0; i < marker.count; i++) {
    final chunk = await storage.getItemAsync(_getChunkKey(key, marker, i));
    if (chunk == null || chunk.isEmpty) return null;
    value.write(chunk);
  }
  return value.toString();
}

Future<String?> _readStoredValueAsync(
  FlutterClientStorage storage,
  String key,
  String? baseValue,
) async {
  if (baseValue == null || !baseValue.startsWith(chunkMarker)) {
    return baseValue;
  }
  final marker = _parseChunkMarker(baseValue);
  if (marker == null) return null;
  final value = await _readChunksAsync(storage, key, marker);
  final slot = marker.slot;
  final fallbackCount = marker.fallbackCount;
  if (value != null || slot == null || fallbackCount == null) return value;
  return _readChunksAsync(
    storage,
    key,
    _ChunkMarker(fallbackCount, _getOtherSlot(slot), null),
  );
}

final class _ChunkCleanupRange {
  const _ChunkCleanupRange(this.prefix, this.start, this.end);

  final String prefix;
  final int start;
  final int end;
}

int _getSlotChunkCount(_ChunkMarker? marker, int? slot) {
  if (marker == null) return 0;
  if (marker.slot == slot) return marker.count;
  if (marker.slot == null || slot == null) return 0;
  return marker.fallbackCount ?? 0;
}

List<_ChunkCleanupRange> _getUnusedChunkRanges(
  String key,
  _ChunkMarker? previousMarker,
  _ChunkMarker? marker,
) => <_ChunkCleanupRange>[
  for (final slot in _chunkSlots)
    _ChunkCleanupRange(
      slot == null ? key : '$key.$slot',
      _getSlotChunkCount(marker, slot),
      _getSlotChunkCount(previousMarker, slot),
    ),
];

({List<(String, String)> writes, List<_ChunkCleanupRange> cleanup})
_getStorageWritePlan(String key, String value, String? currentBaseValue) {
  final currentMarker = currentBaseValue?.startsWith(chunkMarker) ?? false
      ? _parseChunkMarker(currentBaseValue!)
      : null;
  final chunks = _splitStorageValue(value);
  if (chunks.length == 1) {
    return (
      writes: <(String, String)>[(key, value)],
      cleanup: _getUnusedChunkRanges(key, currentMarker, null),
    );
  }
  final count = chunks.length;
  if (count > maxStorageChunks) {
    throw StateError(
      'Storage value requires $count chunks, exceeding the limit of '
      '$maxStorageChunks',
    );
  }
  final slot = currentMarker?.slot == 0 ? 1 : 0;
  final marker = _ChunkMarker(
    count,
    slot,
    currentMarker?.slot == null ? null : currentMarker!.count,
  );
  final writes = <(String, String)>[];
  if (currentMarker?.slot != null && currentMarker!.fallbackCount != null) {
    // The fallback slot becomes the write target; disable it until complete.
    writes.add((
      key,
      _serializeChunkMarker(
        _ChunkMarker(currentMarker.count, currentMarker.slot, null),
      ),
    ));
  }
  for (final (index, chunk) in chunks.indexed) {
    writes.add((_getChunkKey(key, marker, index), chunk));
  }
  writes.add((key, _serializeChunkMarker(marker)));
  return (
    writes: writes,
    cleanup: _getUnusedChunkRanges(key, currentMarker, marker),
  );
}

final class _StorageKeyState {
  Future<Object?>? pending;
  bool cleanupComplete = false;
}

final Expando<Map<String, _StorageKeyState>> _storageStates =
    Expando<Map<String, _StorageKeyState>>();

_StorageKeyState _getStorageState(FlutterClientStorage storage, String key) {
  final states = _storageStates[storage] ??= <String, _StorageKeyState>{};
  return states[key] ??= _StorageKeyState();
}

Future<R> _enqueueStorageOperation<R>(
  _StorageKeyState state,
  Future<R> Function() operation,
) {
  final previous = state.pending ?? Future<void>.value();
  final queued = previous.then<R>(
    (_) => operation(),
    onError: (Object _) => operation(),
  );
  state.pending = queued;
  void cleanup() {
    if (identical(state.pending, queued)) state.pending = null;
  }

  unawaited(queued.then((_) => cleanup(), onError: (Object _) => cleanup()));
  return queued;
}

/// Result of an atomic read-modify-write.
final class StoredUpdate {
  /// Creates an update record.
  const StoredUpdate(this.previousValue, this.value);

  /// Value before the update.
  final String? previousValue;

  /// Value written.
  final String value;
}

/// Chunking, crash-safe, per-key serialized view over a [FlutterClientStorage].
class ManagedStorage {
  /// Wraps [storage].
  ManagedStorage(this.storage);

  /// The backing storage.
  final FlutterClientStorage storage;

  void _logWriteError(String key, Object error) => logger.severe(
    '[better-auth/expo] failed to persist "$key" to storage',
    error,
  );

  void _logCleanupError(String key, Object error) => logger.severe(
    '[better-auth/expo] failed to clear unused chunks for "$key"',
    error,
  );

  /// Reads [name], reassembling chunks; `null` when a chunk is missing.
  Future<String?> getItemAsync(String name) {
    final key = normalizeCookieName(name);
    final state = _getStorageState(storage, key);
    return _enqueueStorageOperation(state, () async {
      final baseValue = await storage.getItemAsync(key);
      return _readStoredValueAsync(storage, key, baseValue);
    });
  }

  Future<void> _writeItemAsync(
    String key,
    String value,
    String? currentBaseValue,
  ) async {
    final state = _getStorageState(storage, key);
    final plan = _getStorageWritePlan(key, value, currentBaseValue);
    for (final (writeKey, writeValue) in plan.writes) {
      await storage.setItemAsync(writeKey, writeValue);
    }
    try {
      final scanContiguousOrphans = !state.cleanupComplete;
      for (final range in plan.cleanup) {
        if (scanContiguousOrphans) {
          final orphanStart = range.start > range.end ? range.start : range.end;
          var orphanEnd = orphanStart;
          for (; orphanEnd < maxStorageChunks; orphanEnd++) {
            final chunk = await storage.getItemAsync(
              '${range.prefix}.$orphanEnd',
            );
            if (chunk == null || chunk.isEmpty) break;
          }
          for (var i = orphanEnd - 1; i >= orphanStart; i--) {
            await storage.setItemAsync('${range.prefix}.$i', '');
          }
        }
        for (var i = range.end - 1; i >= range.start; i--) {
          await storage.setItemAsync('${range.prefix}.$i', '');
        }
      }
      state.cleanupComplete = true;
    } on Object catch (error) {
      state.cleanupComplete = false;
      _logCleanupError(key, error);
    }
  }

  /// Writes [value] under [name]; failures are logged, never thrown.
  Future<void> setItemAsync(String name, String value) {
    final key = normalizeCookieName(name);
    final state = _getStorageState(storage, key);
    return _enqueueStorageOperation(state, () async {
      String? currentBaseValue;
      try {
        currentBaseValue = await storage.getItemAsync(key);
      } on Object catch (error) {
        state.cleanupComplete = false;
        if (_splitStorageValue(value).length > 1) {
          _logWriteError(key, error);
          return;
        }
      }
      try {
        await _writeItemAsync(key, value, currentBaseValue);
      } on Object catch (error) {
        state.cleanupComplete = false;
        _logWriteError(key, error);
      }
    });
  }

  /// Atomically replaces [name] with `update(currentValue)`.
  ///
  /// Returns `null` (and logs) when the value could not be read or written.
  Future<StoredUpdate?> updateItemAsync(
    String name,
    String Function(String? currentValue) update,
  ) {
    final key = normalizeCookieName(name);
    final state = _getStorageState(storage, key);
    return _enqueueStorageOperation(state, () async {
      try {
        final currentBaseValue = await storage.getItemAsync(key);
        final previousValue = await _readStoredValueAsync(
          storage,
          key,
          currentBaseValue,
        );
        final value = update(previousValue);
        await _writeItemAsync(key, value, currentBaseValue);
        return StoredUpdate(previousValue, value);
      } on Object catch (error) {
        state.cleanupComplete = false;
        _logWriteError(key, error);
        return null;
      }
    });
  }
}

/// Creates the managed view the Flutter client uses internally.
ManagedStorage createManagedStorage(FlutterClientStorage storage) =>
    ManagedStorage(storage);

final class _StorageAdapter implements FlutterClientStorage {
  _StorageAdapter(this._managed);

  final ManagedStorage _managed;

  @override
  Future<String?> getItemAsync(String key) => _managed.getItemAsync(key);

  @override
  Future<void> setItemAsync(String key, String value) =>
      _managed.setItemAsync(key, value);
}

/// Wraps [storage] with chunking, recoverable writes and serialized access.
FlutterClientStorage storageAdapter(FlutterClientStorage storage) =>
    _StorageAdapter(createManagedStorage(storage));
