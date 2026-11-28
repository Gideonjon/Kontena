import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shell.dart';
import '../shared/inbox.dart';

class CustomerShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const CustomerShell({super.key, required this.shell});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadProvider).valueOrNull ?? 0;
    return AdaptiveShell(shell: shell, items: [
      const NavItem(Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
      const NavItem(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Orders'),
      NavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Messages', badge: unread),
      const NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
      const NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
    ]);
  }
}
