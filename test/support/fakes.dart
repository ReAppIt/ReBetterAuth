import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:re_better_auth/plugins.dart';
import 'package:re_better_auth/re_better_auth.dart';

/// One request seen by [FakeFetch].
class RecordedRequest {
  RecordedRequest(this.url, this.init);

  final Object url;
  final RequestContext init;

  Uri get uri => url is Uri ? url as Uri : Uri.parse('$url');
  String get method => init.method;
  Map<String, String> get headers => init.headers;
  Object? get body => init.body;
  CancelToken get signal => init.signal;

  Map<String, Object?>? get json {
    final raw = body;
    if (raw is! String || raw.isEmpty) return null;
    return jsonDecode(raw) as Map<String, Object?>;
  }
}

typedef FakeHandler = FutureOr<FetchResponse> Function(RecordedRequest request);

/// A `customFetchImpl` that records requests and answers through [handler].
class FakeFetch {
  FakeFetch(this.handler);

  FakeHandler handler;
  final List<RecordedRequest> requests = <RecordedRequest>[];

  Future<FetchResponse> call(Object url, RequestContext init) async {
    final request = RecordedRequest(url, init);
    requests.add(request);
    return handler(request);
  }
}

FetchResponse jsonResponse(
  Object? body, {
  int status = 200,
  String statusText = '',
  Map<String, List<String>> headers = const <String, List<String>>{},
}) => FetchResponse(
  status: status,
  statusText: statusText,
  bodyBytes: Uint8List.fromList(utf8.encode(jsonEncode(body))),
  headers: FetchHeaders(<String, List<String>>{
    'content-type': <String>['application/json'],
    ...headers,
  }),
);

FetchResponse textResponse(
  String body, {
  int status = 200,
  String contentType = 'text/plain',
}) => FetchResponse(
  status: status,
  bodyBytes: Uint8List.fromList(utf8.encode(body)),
  headers: FetchHeaders(<String, List<String>>{
    'content-type': <String>[contentType],
  }),
);

FetchResponse emptyResponse({int status = 200}) =>
    FetchResponse(status: status, bodyBytes: Uint8List(0));

/// In-memory storage with hooks to slow down or fail operations.
class MemoryStorage implements FlutterClientStorage, LastLoginMethodStorage {
  MemoryStorage([Map<String, String>? initial])
    : map = <String, String>{...?initial};

  final Map<String, String> map;
  Future<String?> Function(String key)? onGet;
  Future<void> Function(String key, String value)? onSet;
  final List<String> getCalls = <String>[];
  final List<(String, String)> setCalls = <(String, String)>[];

  @override
  Future<String?> getItemAsync(String key) async {
    getCalls.add(key);
    final override = onGet;
    if (override != null) return override(key);
    return map[key];
  }

  @override
  Future<void> setItemAsync(String key, String value) async {
    setCalls.add((key, value));
    final override = onSet;
    if (override != null) return override(key, value);
    map[key] = value;
  }

  @override
  Future<void> deleteItemAsync(String key) async {
    map.remove(key);
  }
}

/// Collects severe records logged during the current test.
List<LogRecord> captureSevereLogs() {
  final records = <LogRecord>[];
  final subscription = Logger.root.onRecord.listen((record) {
    if (record.level >= Level.SEVERE) records.add(record);
  });
  addTearDown(subscription.cancel);
  return records;
}

/// Lets queued microtasks and zero-duration timers run.
Future<void> settle([int rounds = 5]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Resets the process-wide managers the client installs.
void resetGlobals() {
  globalFocusManager = null;
  globalOnlineManager = null;
  globalBroadcastChannel = null;
}

/// Records posts and delivers messages to subscribers on demand.
class FakeBroadcastChannel implements AuthBroadcastChannel {
  final List<BroadcastMessage> posts = <BroadcastMessage>[];
  final Set<BroadcastListener> _listeners = <BroadcastListener>{};
  bool _active = false;

  void deliver(BroadcastMessage message) {
    if (!_active) return;
    for (final listener in _listeners.toList()) {
      listener(message);
    }
  }

  @override
  void post(BroadcastMessage message) => posts.add(message);

  @override
  void Function() subscribe(BroadcastListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void Function() setup() {
    _active = true;
    return () => _active = false;
  }
}
