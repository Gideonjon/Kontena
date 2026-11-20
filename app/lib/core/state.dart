import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));

final authStateProvider = StreamProvider<User?>((ref) => FirebaseAuth.instance.authStateChanges());

/// Profile + store from our API. Re-fetches whenever the signed-in user changes.
final meProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final u = ref.watch(authStateProvider).valueOrNull;
  if (u == null) return {};
  return Api.i.get('/me');
});

/// Which side of the app the person is using: 'customer' or 'vendor'. Stored on the device.
class ModeNotifier extends StateNotifier<String?> {
  final SharedPreferences prefs;
  ModeNotifier(this.prefs) : super(prefs.getString('mode'));
  Future<void> set(String? m) async {
    state = m;
    if (m == null) {
      await prefs.remove('mode');
    } else {
      await prefs.setString('mode', m);
    }
  }
}

final modeProvider = StateNotifierProvider<ModeNotifier, String?>((ref) => ModeNotifier(ref.watch(prefsProvider)));

/// Bridges auth + mode changes to go_router so redirects re-run.
class RouterRefresh extends ChangeNotifier {
  RouterRefresh(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(modeProvider, (_, __) => notifyListeners());
  }
}

final routerRefreshProvider = Provider<RouterRefresh>((ref) => RouterRefresh(ref));
