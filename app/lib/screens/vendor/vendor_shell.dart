import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shell.dart';

class VendorShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const VendorShell({super.key, required this.shell});
  @override
  Widget build(BuildContext context) => AdaptiveShell(shell: shell, items: const [
        NavItem(Icons.dashboard_outlined, Icons.dashboard_rounded, 'Home'),
        NavItem(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Orders'),
        NavItem(Icons.storefront_outlined, Icons.storefront_rounded, 'Store'),
        NavItem(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Wallet'),
      ]);
}
