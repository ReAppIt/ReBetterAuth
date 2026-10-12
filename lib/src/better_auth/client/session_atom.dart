import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:re_better_auth/src/better_auth/client/equality.dart';
import 'package:re_better_auth/src/better_auth/client/query.dart';
import 'package:re_better_auth/src/better_auth/client/session_refresh.dart';
import 'package:re_better_auth/src/better_auth/core/db.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/error.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// The `useSession` atom.
typedef SessionAtom = AuthQueryAtom<SessionData>;

/// Seeds [sessionAtom] with [session] unless it already holds data.
void hydrateSessionAtom(SessionAtom sessionAtom, SessionData? session) {
  final currentSession = sessionAtom.get();
  if (currentSession.data != null || session == null) return;
  sessionAtom.set(
    AuthQueryState<SessionData>(
      data: session,
      error: null,
      isPending: false,
      isRefetching: currentSession.isRefetching,
      refetch: currentSession.refetch,
    ),
  );
}

enum _SessionFetchOutcome { aborted, failed, stale, fresh }

final class _SessionFlight {
  _SessionFlight(this.cancel, this.promise, this.revision);

  final void Function() cancel;
  final Future<_SessionFetchOutcome> promise;
  final int revision;
}

SessionData? _normalizeSessionData(Object? data) {
  if (data is! Map<String, Object?>) return null;
  final empty =
      data.containsKey('session') &&
      data['session'] == null &&
      data.containsKey('user') &&
      data['user'] == null;
  return empty ? null : SessionData(data);
}

bool _isSessionAtomEqual(
  AuthQueryState<SessionData> a,
  AuthQueryState<SessionData> b,
) =>
    isJsonEqual(a.data, b.data) &&
    identical(a.error, b.error) &&
    a.isPending == b.isPending &&
    a.isRefetching == b.isRefetching &&
    identical(a.refetch, b.refetch);

int _nowMs() => clock.now().millisecondsSinceEpoch;

const int _unbounded = 1 << 53;

/// Session atom, its signal, and the broadcast hook (`getSessionAtom`).
typedef SessionAtomBundle = ({
  SessionAtom session,
  Atom<bool> $sessionSignal,
  void Function(String trigger) broadcastSessionUpdate,
});

/// Creates the `useSession` atom: one request at a time, superseded requests
/// cancelled, 401 clears data, other failures keep it, and remounts reuse a
/// fresh result for up to [storeUnmountDelay].
SessionAtomBundle getSessionAtom(
  BetterFetch $fetch, [
  BetterAuthClientOptions? options,
]) {
  final $signal = Atom<bool>(false);
  _SessionFlight? flight;
  var freshUntil = 0;
  var sessionRevision = 0;
  $signal.listen((_, _) {
    sessionRevision++;
    freshUntil = 0;
  });

  late final SessionAtom session;
  late final Future<void> Function({Map<String, Object?>? query}) fetchSession;
  Future<void> refetch({Map<String, Object?>? query}) =>
      fetchSession(query: query);

  session = createAuthQueryAtom<SessionData>(
    AuthQueryState<SessionData>(
      data: null,
      error: null,
      isPending: true,
      isRefetching: false,
      refetch: refetch,
    ),
  );
  withEquality(session, _isSessionAtomEqual);

  Future<_SessionFetchOutcome> executeSessionFetch(
    CancelToken signal,
    Map<String, Object?>? query,
  ) async {
    final current = session.value;
    session.set(
      AuthQueryState<SessionData>(
        data: current.data,
        error: null,
        isPending: current.data == null,
        isRefetching: true,
        refetch: refetch,
      ),
    );
    if (signal.isCancelled) return _SessionFetchOutcome.aborted;

    try {
      final res = await $fetch<Object?>(
        '/get-session',
        ClientFetchOption(method: 'GET', query: query, signal: signal),
      );
      if (signal.isCancelled) return _SessionFetchOutcome.aborted;

      var data = res.data;
      BetterFetchError? error = res.error;
      var outcome = _SessionFetchOutcome.fresh;

      if (data is Map<String, Object?> && data['needsRefresh'] == true) {
        try {
          final refreshRes = await $fetch<Object?>(
            '/get-session',
            ClientFetchOption(method: 'POST', signal: signal),
          );
          if (signal.isCancelled) return _SessionFetchOutcome.aborted;
          data = refreshRes.data;
          error = refreshRes.error;
        } on Object {
          if (signal.isCancelled) return _SessionFetchOutcome.aborted;
          outcome = _SessionFetchOutcome.stale;
        }
      }

      if (error != null) {
        final latest = session.value;
        final isUnauthorized = error.status == 401;
        session.set(
          AuthQueryState<SessionData>(
            data: isUnauthorized ? null : latest.data,
            error: error,
            isPending: false,
            isRefetching: false,
            refetch: refetch,
          ),
        );
        return _SessionFetchOutcome.failed;
      }

      final sessionData = _normalizeSessionData(data);
      final latest = session.value;
      final stableData =
          latest.data != null &&
              sessionData != null &&
              isJsonEqual(latest.data, sessionData)
          ? latest.data
          : sessionData;
      session.set(
        AuthQueryState<SessionData>(
          data: stableData,
          error: null,
          isPending: false,
          isRefetching: false,
          refetch: refetch,
        ),
      );
      return outcome;
    } on Object catch (fetchError) {
      if (signal.isCancelled) return _SessionFetchOutcome.aborted;
      final latest = session.value;
      session.set(
        AuthQueryState<SessionData>(
          data: latest.data,
          error: asFetchError(fetchError),
          isPending: false,
          isRefetching: false,
          refetch: refetch,
        ),
      );
      return _SessionFetchOutcome.failed;
    }
  }

  int getFreshUntil() {
    final sessionJson = session.value.data?.json['session'];
    final expiresAt = sessionJson is Map<String, Object?>
        ? sessionJson['expiresAt']
        : null;
    final sessionExpiresAt = expiresAt is DateTime
        ? expiresAt.millisecondsSinceEpoch
        : _unbounded;
    return min(_nowMs() + storeUnmountDelay.inMilliseconds, sessionExpiresAt);
  }

  fetchSession = ({Map<String, Object?>? query}) {
    freshUntil = 0;
    flight?.cancel();
    final controller = CancelToken();
    final promise = Future<_SessionFetchOutcome>.microtask(
      () => controller.isCancelled
          ? _SessionFetchOutcome.aborted
          : executeSessionFetch(controller, query),
    );
    final request = _SessionFlight(controller.cancel, promise, sessionRevision);
    flight = request;
    void settleFlight(_SessionFetchOutcome outcome) {
      if (!identical(flight, request)) return;
      flight = null;
      if (outcome == _SessionFetchOutcome.fresh &&
          request.revision == sessionRevision) {
        freshUntil = getFreshUntil();
      }
    }

    unawaited(
      request.promise.then(
        settleFlight,
        onError: (Object _) => settleFlight(_SessionFetchOutcome.failed),
      ),
    );
    return request.promise.then((_) {});
  };

  Future<void> fetchSessionOnMount() {
    final current = flight;
    if (current != null && current.revision == sessionRevision) {
      return current.promise.then((_) {});
    }
    if (_nowMs() < freshUntil) return Future<void>.value();
    return fetchSession();
  }

  void Function(String trigger) broadcastSessionUpdate = (_) {};

  onMount(session, () {
    final timeoutId = Timer(
      Duration.zero,
      () => unawaited(fetchSessionOnMount()),
    );
    final refreshManager = createSessionRefreshManager(
      fetchSession: fetchSession,
      shouldPollSession: () => session.value.data != null,
      sessionSignal: $signal,
      options: options,
    )..init();
    broadcastSessionUpdate = refreshManager.broadcastSessionUpdate;
    return () {
      timeoutId.cancel();
      refreshManager.cleanup();
    };
  });

  return (
    session: session,
    $sessionSignal: $signal,
    broadcastSessionUpdate: (trigger) => broadcastSessionUpdate(trigger),
  );
}
