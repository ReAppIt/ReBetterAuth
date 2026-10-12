import 'dart:async';

import 'package:re_better_auth/src/better_auth/client/equality.dart';
import 'package:re_better_auth/src/better_auth/core/plugin_client.dart';
import 'package:re_better_auth/src/better_fetch/create_fetch.dart';
import 'package:re_better_auth/src/better_fetch/error.dart';
import 'package:re_better_auth/src/nanostores/atom.dart';

/// Refetches a query, optionally with extra [query] parameters.
typedef Refetch = Future<void> Function({Map<String, Object?>? query});

/// Data, error and loading flags of an auth query such as `useSession`.
final class AuthQueryState<T> {
  /// Creates a query state.
  const AuthQueryState({
    required this.data,
    required this.error,
    required this.isPending,
    required this.isRefetching,
    required this.refetch,
  });

  /// Latest data, or `null` before the first success or after a 401.
  final T? data;

  /// Error of the latest request; status `0` marks a transport failure.
  final BetterFetchError? error;

  /// True until data exists and while a request runs without data.
  final bool isPending;

  /// True while any request is in flight.
  final bool isRefetching;

  /// Starts a new request, superseding the current one.
  final Refetch refetch;
}

/// An [Atom] holding an [AuthQueryState] (`createAuthQueryAtom`).
class AuthQueryAtom<T> extends Atom<AuthQueryState<T>> {
  /// Creates the atom with [initialValue].
  AuthQueryAtom(super.initialValue);
}

/// Creates an [AuthQueryAtom] with [initialValue].
AuthQueryAtom<T> createAuthQueryAtom<T>(AuthQueryState<T> initialValue) =>
    AuthQueryAtom<T>(initialValue);

/// Whether [store] is an auth query atom.
bool isAuthQueryStore(Atom<Object?> store) => store is AuthQueryAtom;

/// Builds per-request options from the current query state.
typedef QueryOptionsBuilder<T> =
    ClientFetchOption Function(
      ({T? data, BetterFetchError? error, bool isPending}) value,
    );

/// Wraps an error thrown by the transport so it fits [AuthQueryState.error].
BetterFetchError asFetchError(Object error) => error is BetterFetchError
    ? error
    : BetterFetchError(0, 'Fetch Error', error);

bool _isAuthQueryStateEqual<T>(AuthQueryState<T> a, AuthQueryState<T> b) =>
    isJsonEqual(a.data, b.data) &&
    identical(a.error, b.error) &&
    a.isPending == b.isPending &&
    a.isRefetching == b.isRefetching &&
    identical(a.refetch, b.refetch);

/// A query atom for [path]: fetches on mount and whenever an
/// [initializedAtom] changes; unchanged payloads keep the data reference.
AuthQueryAtom<T> useAuthQuery<T>(
  List<Atom<Object?>> initializedAtom,
  String path,
  BetterFetch $fetch, {
  ClientFetchOption? options,
  QueryOptionsBuilder<T>? optionsBuilder,
}) {
  late final AuthQueryAtom<T> value;
  var latestRequestId = 0;

  Future<void> fn({Map<String, Object?>? query}) async {
    final requestId = ++latestRequestId;
    final current = value.get();
    final opts = optionsBuilder != null
        ? optionsBuilder((
            data: current.data,
            error: current.error,
            isPending: current.isPending,
          ))
        : options;
    final callOptions = (opts ?? ClientFetchOption()).copy()
      ..query = <String, Object?>{...?opts?.query, ...?query}
      ..onSuccess = (context) async {
        if (requestId == latestRequestId) {
          final current = value.get();
          final stableData =
              current.data != null &&
                  context.data != null &&
                  isJsonEqual(current.data, context.data)
              ? current.data
              : context.data as T?;
          value.set(
            AuthQueryState<T>(
              data: stableData,
              error: null,
              isPending: false,
              isRefetching: false,
              refetch: value.value.refetch,
            ),
          );
        }
        await opts?.onSuccess?.call(context);
      }
      ..onError = (context) async {
        final request = context.request.options;
        final retryAttempts = request.retry?.attempts ?? 0;
        final retryAttempt = request.retryAttempt ?? 0;
        if (retryAttempts > 0 && retryAttempt < retryAttempts) return;
        if (requestId == latestRequestId) {
          final isUnauthorized = context.error.status == 401;
          value.set(
            AuthQueryState<T>(
              error: context.error,
              data: isUnauthorized ? null : value.get().data,
              isPending: false,
              isRefetching: false,
              refetch: value.value.refetch,
            ),
          );
        }
        await opts?.onError?.call(context);
      }
      ..onRequest = (context) async {
        if (requestId == latestRequestId) {
          final currentValue = value.get();
          value.set(
            AuthQueryState<T>(
              isPending: currentValue.data == null,
              data: currentValue.data,
              error: null,
              isRefetching: true,
              refetch: value.value.refetch,
            ),
          );
        }
        await opts?.onRequest?.call(context);
        return null;
      };
    try {
      await $fetch<Object?>(path, callOptions);
    } on Object catch (error) {
      if (requestId != latestRequestId) return;
      value.set(
        AuthQueryState<T>(
          error: asFetchError(error),
          data: value.get().data,
          isPending: false,
          isRefetching: false,
          refetch: value.value.refetch,
        ),
      );
    }
  }

  Future<void> refetch({Map<String, Object?>? query}) => fn(query: query);

  value = createAuthQueryAtom<T>(
    AuthQueryState<T>(
      data: null,
      error: null,
      isPending: true,
      isRefetching: false,
      refetch: refetch,
    ),
  );
  onMount(value, () => withEquality(value, _isAuthQueryStateEqual<T>));

  var isMountFetchPending = false;
  var isMounted = false;
  var shouldRefetchAfterPending = false;

  void fetchOnMount() {
    if (isMountFetchPending) {
      shouldRefetchAfterPending = true;
      return;
    }
    isMountFetchPending = true;
    unawaited(
      fn().whenComplete(() {
        isMountFetchPending = false;
        final shouldRefetch = shouldRefetchAfterPending && isMounted;
        shouldRefetchAfterPending = false;
        if (shouldRefetch) fetchOnMount();
      }),
    );
  }

  onMount(value, () {
    isMounted = true;
    var isInitialized = false;
    Timer? timeoutId;
    final cleanups = <void Function()>[
      for (final initAtom in initializedAtom)
        initAtom.listen((_, _) {
          if (isInitialized) {
            unawaited(fn());
          } else {
            isInitialized = true;
            timeoutId?.cancel();
            fetchOnMount();
          }
        }),
    ];
    timeoutId = Timer(Duration.zero, () {
      isInitialized = true;
      fetchOnMount();
    });
    return () {
      isMounted = false;
      for (final cleanup in cleanups) {
        cleanup();
      }
      timeoutId?.cancel();
    };
  });
  return value;
}
