import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shell.dart';

class AdminShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AdminShell({super.key, required this.shell});
  @override
  Widget build(BuildContext context) => AdaptiveShell(shell: shell, items: const [
        NavItem(Icons.insights_outlined, Icons.insights_rounded, 'Overview'),
        NavItem(Icons.fact_check_outlined, Icons.fact_check_rounded, 'Inspections'),
        NavItem(Icons.payments_outlined, Icons.payments_rounded, 'Payouts'),
        NavItem(Icons.storefront_outlined, Icons.storefront_rounded, 'Stores'),
        NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Me'),
      ]);
}
