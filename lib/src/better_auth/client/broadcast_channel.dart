/// A cross-client session message (`{event, data: {trigger}, clientId}`).
class BroadcastMessage {
  /// Creates a message.
  const BroadcastMessage({
    required this.clientId,
    required this.timestamp,
    this.event,
    this.trigger,
  });

  /// Always `session` for session updates.
  final String? event;

  /// `signout`, `getSession` or `updateUser`.
  final String? trigger;

  /// Random id of the sending client.
  final String clientId;

  /// Send time in seconds since the epoch.
  final int timestamp;
}

/// Receives broadcast session messages.
typedef BroadcastListener = void Function(BroadcastMessage message);

/// Channel that tells other clients about session changes.
abstract interface class AuthBroadcastChannel {
  /// Sends [message] to other clients.
  void post(BroadcastMessage message);

  /// Adds [listener]; returns the function that removes it.
  void Function() subscribe(BroadcastListener listener);

  /// Starts listening; returns the teardown.
  void Function() setup();
}

/// Default channel: there are no other tabs on mobile, so it never delivers.
class DefaultBroadcastChannel implements AuthBroadcastChannel {
  final Set<BroadcastListener> _listeners = <BroadcastListener>{};

  @override
  void post(BroadcastMessage message) {}

  @override
  void Function() subscribe(BroadcastListener listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  @override
  void Function() setup() => () {};
}

/// Process-wide channel, the Dart slot for `globalThis[kBroadcastChannel]`.
AuthBroadcastChannel? globalBroadcastChannel;

/// The current channel, creating the default one on first use.
AuthBroadcastChannel getGlobalBroadcastChannel() =>
    globalBroadcastChannel ??= DefaultBroadcastChannel();
