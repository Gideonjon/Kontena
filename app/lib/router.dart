import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/state.dart';
import 'screens/auth/welcome.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/auth/role_screen.dart';
import 'screens/customer/customer_shell.dart';
import 'screens/customer/explore.dart';
import 'screens/customer/orders_list.dart';
import 'screens/customer/checkout.dart';
import 'screens/shared/store_page.dart';
import 'screens/shared/order_detail.dart';
import 'screens/shared/wallet.dart';
import 'screens/shared/profile.dart';
import 'screens/shared/notifications.dart';
import 'screens/shared/inbox.dart';
import 'screens/shared/chat_screen.dart';
import 'screens/vendor/vendor_shell.dart';
import 'screens/vendor/vendor_home.dart';
import 'screens/vendor/vendor_orders.dart';
import 'screens/vendor/vendor_store.dart';
import 'screens/vendor/setup_store.dart';
import 'screens/vendor/product_form.dart';
import 'screens/vendor/withdraw.dart';
import 'screens/admin/admin_shell.dart';
import 'screens/admin/admin_home.dart';
import 'screens/admin/admin_inspections.dart';
import 'screens/admin/admin_payouts.dart';
import 'screens/admin/admin_stores.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);
  final prefs = ref.watch(prefsProvider);
  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final loc = state.matchedLocation;
      final mode = prefs.getString('mode');
      final isPublic = loc == '/welcome' || loc == '/auth' || loc.startsWith('/s/');
      if (user == null) {
        if (loc == '/') return '/welcome';
        if (!isPublic) return '/welcome';
        return null;
      }
      final home = mode == 'admin' ? '/a/home' : (mode == 'vendor' ? '/v/home' : '/c/explore');
      if (loc == '/' || loc == '/welcome' || loc == '/auth') return mode == null ? '/role' : home;
      if (mode == null && loc != '/role' && !loc.startsWith('/s/')) return '/role';
      if (mode == 'admin' && !loc.startsWith('/a/') && !loc.startsWith('/order/') && loc != '/notifications') return '/a/home';
      if (mode != 'admin' && loc.startsWith('/a/')) return home;
      if (mode == 'vendor' && loc.startsWith('/c/')) return '/v/home';
      if (mode == 'customer' && loc.startsWith('/v/') && loc != '/v/setup') return '/c/explore';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const Scaffold(body: Center(child: CircularProgressIndicator()))),
      GoRoute(path: '/welcome', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/auth', builder: (_, s) => AuthScreen(signUp: s.uri.queryParameters['mode'] != 'login')),
      GoRoute(path: '/role', builder: (_, __) => const RoleScreen()),
      GoRoute(path: '/s/:slug', builder: (_, s) => StorePage(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/order/:id', builder: (_, s) => OrderDetailScreen(id: s.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/chat/:kind/:id', builder: (_, s) => ChatScreen(kind: s.pathParameters['kind']!, id: s.pathParameters['id']!, product: s.extra is Map<String, dynamic> ? s.extra as Map<String, dynamic> : null)),
      GoRoute(path: '/checkout', builder: (_, s) => CheckoutScreen(args: s.extra as CheckoutArgs)),
      GoRoute(path: '/v/setup', builder: (_, __) => const SetupStoreScreen()),
      GoRoute(path: '/v/product', builder: (_, s) => ProductFormScreen(existing: s.extra as Map<String, dynamic>?)),
      GoRoute(path: '/v/withdraw', builder: (_, __) => const WithdrawScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/c/explore', builder: (_, __) => const ExploreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/c/orders', builder: (_, __) => const OrdersListScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/c/messages', builder: (_, __) => const InboxScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/c/wallet', builder: (_, __) => const WalletScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/c/me', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => VendorShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/v/home', builder: (_, __) => const VendorHomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/v/orders', builder: (_, __) => const VendorOrdersScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/v/messages', builder: (_, __) => const InboxScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/v/store', builder: (_, __) => const VendorStoreScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/v/wallet', builder: (_, __) => const WalletScreen(vendor: true))]),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => AdminShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/a/home', builder: (_, __) => const AdminHomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/a/inspections', builder: (_, __) => const AdminInspectionsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/a/payouts', builder: (_, __) => const AdminPayoutsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/a/stores', builder: (_, __) => const AdminStoresScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/a/me', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});
