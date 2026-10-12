/// Framework-agnostic client (`better-auth/client`): atoms instead of
/// `ValueListenable`s. Import this or `re_better_auth.dart`, not both.
library;

export 'package:re_better_auth/src/better_auth/client/vanilla.dart'
    show AuthClient, createAuthClient;
export 'package:re_better_auth/src/exports.dart';
