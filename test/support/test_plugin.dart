import 'package:re_better_auth/re_better_auth.dart';

/// Port of `test-plugin.ts`: a `/test` query atom and signal listeners.
class TestClientPlugin extends BetterAuthClientPlugin {
  TestClientPlugin({this.queryOptions});

  final ClientFetchOption? queryOptions;
  final Atom<bool> $test = Atom<bool>(false);

  @override
  String get id => 'test';

  @override
  Map<String, Object?> getActions(
    BetterFetch $fetch,
    ClientStore $store,
    BetterAuthClientOptions? options,
  ) => <String, Object?>{
    'setTestAtom': $test.set,
    'test': <String, Object?>{'signOut': () async {}},
  };

  @override
  Map<String, Atom<Object?>> getAtoms(BetterFetch $fetch) {
    final $signal = Atom<bool>(false);
    final queryAtom = useAuthQuery<Object?>(
      <Atom<Object?>>[$signal],
      '/test',
      $fetch,
      options: queryOptions ?? ClientFetchOption(method: 'GET'),
    );
    return <String, Atom<Object?>>{
      r'$test': $test,
      r'$signal': $signal,
      'queryAtom': queryAtom,
    };
  }

  @override
  List<ClientAtomListener> get atomListeners => <ClientAtomListener>[
    ClientAtomListener(matcher: (path) => path == '/test', signal: r'$test'),
    ClientAtomListener(
      matcher: (path) => path == '/test2/sign-out',
      signal: r'$sessionSignal',
    ),
  ];
}

/// Contributes `signIn.methodA`, for the deep-merge tests.
class DeepMergePluginA extends BetterAuthClientPlugin {
  @override
  String get id => 'test-deep-merge-a';

  @override
  Map<String, Object?> getActions(
    BetterFetch $fetch,
    ClientStore $store,
    BetterAuthClientOptions? options,
  ) => <String, Object?>{
    'signIn': <String, Object?>{
      'methodA': () async => <String, Object?>{'success': true, 'method': 'A'},
    },
  };
}

/// Contributes `signIn.methodB`, for the deep-merge tests.
class DeepMergePluginB extends BetterAuthClientPlugin {
  @override
  String get id => 'test-deep-merge-b';

  @override
  Map<String, Object?> getActions(
    BetterFetch $fetch,
    ClientStore $store,
    BetterAuthClientOptions? options,
  ) => <String, Object?>{
    'signIn': <String, Object?>{
      'methodB': () async => <String, Object?>{'success': true, 'method': 'B'},
    },
  };
}
