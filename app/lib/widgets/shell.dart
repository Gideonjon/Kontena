import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/theme.dart';
import 'brand.dart';

class NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badge; // unread count shown on the tab icon
  const NavItem(this.icon, this.activeIcon, this.label, {this.badge = 0});
}

Widget _badged(NavItem item, Widget icon) => item.badge > 0
    ? Badge(label: Text(item.badge > 9 ? '9+' : '${item.badge}'), backgroundColor: KT.orange, textColor: Colors.white, child: icon)
    : icon;

/// Bottom bar on phones, side rail on wide screens (web / tablet).
class AdaptiveShell extends StatelessWidget {
  final StatefulNavigationShell shell;
  final List<NavItem> items;
  const AdaptiveShell({super.key, required this.shell, required this.items});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          Container(
            width: 240, color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 28, 16, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.only(left: 8, bottom: 28), child: Wordmark(size: 22)),
              for (var i = 0; i < items.length; i++)
                _RailItem(item: items[i], selected: shell.currentIndex == i, onTap: () => go(i)),
              const Spacer(),
              _RailItem(item: const NavItem(Icons.notifications_none_rounded, Icons.notifications_rounded, 'Notifications'), selected: false, onTap: () => context.push('/notifications')),
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: shell))),
        ]),
      );
    }
    return Scaffold(
      body: shell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: KT.line))),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _BarItem(item: items[i], selected: shell.currentIndex == i, onTap: () => go(i))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _BarItem({required this.item, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = selected ? KT.orange : KT.grey2;
    return InkWell(
      borderRadius: BorderRadius.circular(16), onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _badged(item, Icon(selected ? item.activeIcon : item.icon, color: c, size: 25)),
          const SizedBox(height: 3),
          Text(item.label, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _RailItem({required this.item, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? KT.peach : Colors.transparent, borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14), onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(children: [
                _badged(item, Icon(selected ? item.activeIcon : item.icon, color: selected ? KT.orange : KT.grey, size: 22)),
                const SizedBox(width: 12),
                Text(item.label, style: TextStyle(fontWeight: FontWeight.w800, color: selected ? KT.ink : KT.grey)),
              ]),
            ),
          ),
        ),
      );
}

/// Page title row used at the top of tab screens.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader(this.title, {super.key, this.subtitle, this.actions = const []});
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (subtitle != null) Text(subtitle!, style: KT.small),
          Text(title, style: KT.h1.copyWith(fontSize: 28)),
        ])),
        ...actions,
        if (!wide) IconButton(onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none_rounded, size: 26)),
      ]),
    );
  }
}
