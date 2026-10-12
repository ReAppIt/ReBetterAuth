import 'package:flutter/widgets.dart';
import 'package:re_better_auth/src/convex/flutter/convex_auth_state.dart';

/// Shows [child] once the user is signed in and Convex accepted the token.
class Authenticated extends StatelessWidget {
  /// Creates the gate.
  const Authenticated({super.key, required this.child});

  /// Shown while authenticated.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = useConvexAuth(context);
    if (auth.isLoading || !auth.isAuthenticated) return const SizedBox.shrink();
    return child;
  }
}

/// Shows [child] when the user is signed out or Convex rejected the token.
class Unauthenticated extends StatelessWidget {
  /// Creates the gate.
  const Unauthenticated({super.key, required this.child});

  /// Shown while unauthenticated.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = useConvexAuth(context);
    if (auth.isLoading || auth.isAuthenticated) return const SizedBox.shrink();
    return child;
  }
}

/// Shows [child] while the auth status is being resolved.
class AuthLoading extends StatelessWidget {
  /// Creates the gate.
  const AuthLoading({super.key, required this.child});

  /// Shown while loading.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!useConvexAuth(context).isLoading) return const SizedBox.shrink();
    return child;
  }
}

/// Shows [child] while an authenticated client refetches a rejected token.
class AuthRefreshing extends StatelessWidget {
  /// Creates the gate.
  const AuthRefreshing({super.key, required this.child});

  /// Shown while refreshing.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = useConvexAuth(context);
    if (!auth.isAuthenticated || !auth.isRefreshing) {
      return const SizedBox.shrink();
    }
    return child;
  }
}
