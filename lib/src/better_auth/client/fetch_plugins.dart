import 'package:re_better_auth/src/better_fetch/plugins.dart';

/// Default `redirect` plugin; browser navigation does not exist on iOS/Android.
const BetterFetchPlugin redirectPlugin = BetterFetchPlugin(
  id: 'redirect',
  name: 'Redirect',
);
