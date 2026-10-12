import 'dart:async';
import 'dart:math' as math;

import 'package:re_better_auth/src/better_fetch/types.dart';

/// Decides whether a failed [response] should be retried.
typedef RetryCondition = FutureOr<bool> Function(FetchResponse? response);

/// Retry policy for non-2xx responses: [LinearRetry] or [ExponentialRetry].
sealed class RetryOptions {
  const RetryOptions();

  /// Shorthand for the JS `retry: number`: [attempts] tries, 1 s apart.
  const factory RetryOptions.count(int attempts) = LinearRetry;

  /// Maximum number of retries after the first request.
  int get attempts;

  /// Optional extra check run before each retry.
  RetryCondition? get shouldRetry;
}

/// Retries with the same [delay] between attempts.
final class LinearRetry extends RetryOptions {
  /// Creates a linear policy.
  const LinearRetry(
    this.attempts, {
    this.delay = const Duration(seconds: 1),
    this.shouldRetry,
  });

  @override
  final int attempts;

  /// Pause before every retry.
  final Duration delay;

  @override
  final RetryCondition? shouldRetry;
}

/// Retries with `baseDelay * 2^attempt`, capped at [maxDelay].
final class ExponentialRetry extends RetryOptions {
  /// Creates an exponential policy.
  const ExponentialRetry(
    this.attempts, {
    required this.baseDelay,
    required this.maxDelay,
    this.shouldRetry,
  });

  @override
  final int attempts;

  /// Delay before the first retry.
  final Duration baseDelay;

  /// Upper bound for any delay.
  final Duration maxDelay;

  @override
  final RetryCondition? shouldRetry;
}

/// Runtime form of a [RetryOptions] policy.
abstract interface class RetryStrategy {
  /// Whether retry number [attempt] (0-based) should run for [response].
  Future<bool> shouldAttemptRetry(int attempt, FetchResponse? response);

  /// Pause before retry number [attempt].
  Duration getDelay(int attempt);
}

final class _LinearRetryStrategy implements RetryStrategy {
  _LinearRetryStrategy(this.options);

  final LinearRetry options;

  @override
  Future<bool> shouldAttemptRetry(int attempt, FetchResponse? response) async {
    final shouldRetry = options.shouldRetry;
    if (shouldRetry != null) {
      return attempt < options.attempts && await shouldRetry(response);
    }
    return attempt < options.attempts;
  }

  @override
  Duration getDelay(int attempt) => options.delay;
}

final class _ExponentialRetryStrategy implements RetryStrategy {
  _ExponentialRetryStrategy(this.options);

  final ExponentialRetry options;

  @override
  Future<bool> shouldAttemptRetry(int attempt, FetchResponse? response) async {
    final shouldRetry = options.shouldRetry;
    if (shouldRetry != null) {
      return attempt < options.attempts && await shouldRetry(response);
    }
    return attempt < options.attempts;
  }

  @override
  Duration getDelay(int attempt) {
    final delay = options.baseDelay * math.pow(2, attempt).toInt();
    return delay < options.maxDelay ? delay : options.maxDelay;
  }
}

/// Builds the [RetryStrategy] for [options].
RetryStrategy createRetryStrategy(RetryOptions options) => switch (options) {
  final LinearRetry linear => _LinearRetryStrategy(linear),
  final ExponentialRetry exponential => _ExponentialRetryStrategy(exponential),
};
