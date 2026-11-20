import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shell.dart';

class CustomerShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const CustomerShell({super.key, required this.shell});
  @override
  Widget build(BuildContext context) => AdaptiveShell(shell: shell, items: const [
        NavItem(Icons.explore_outlined, Icons.explore_rounded, 'Explore'),
        NavItem(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Orders'),
        NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
        NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
      ]);
}
