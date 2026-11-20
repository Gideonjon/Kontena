import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api.dart';
import 'core/state.dart';
import 'core/theme.dart';
import 'firebase_options.dart';
import 'router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  runApp(ProviderScope(overrides: [prefsProvider.overrideWithValue(prefs)], child: const KontenaApp()));
}

class KontenaApp extends ConsumerWidget {
  const KontenaApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Kontena',
      debugShowCheckedModeBanner: false,
      theme: KT.theme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => _PushBootstrap(child: child ?? const SizedBox()),
    );
  }
}

/// Registers the device for push notifications once someone is signed in. Never blocks the UI.
class _PushBootstrap extends ConsumerStatefulWidget {
  final Widget child;
  const _PushBootstrap({required this.child});
  @override
  ConsumerState<_PushBootstrap> createState() => _PushBootstrapState();
}

class _PushBootstrapState extends ConsumerState<_PushBootstrap> {
  String? _registeredFor;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user != null && _registeredFor != user.uid) {
      _registeredFor = user.uid;
      _register();
    }
    return widget.child;
  }

  Future<void> _register() async {
    try {
      final m = FirebaseMessaging.instance;
      final perm = await m.requestPermission();
      if (perm.authorizationStatus == AuthorizationStatus.denied) return;
      // On web a VAPID key is required: pass --dart-define=FCM_VAPID_KEY=...
      const vapid = String.fromEnvironment('FCM_VAPID_KEY');
      final token = await m.getToken(vapidKey: kIsWeb && vapid.isNotEmpty ? vapid : null);
      if (token == null) return;
      await Api.i.post('/device-token', {'token': token, 'platform': kIsWeb ? 'web' : defaultTargetPlatform.name});
    } catch (e) {
      debugPrint('push registration skipped: $e');
    }
  }
}
