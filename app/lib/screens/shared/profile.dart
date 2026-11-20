import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider).valueOrNull ?? {};
    final u = me.m('user');
    final mode = ref.watch(modeProvider);
    final hasStore = me['store'] != null;
    final isAdmin = u.b('isAdmin');
    final name = u.s('name').isEmpty ? (FirebaseAuth.instance.currentUser?.displayName ?? 'You') : u.s('name');
    return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
      const PageHeader('Profile', subtitle: 'Me'),
      Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        KtCard(child: Row(children: [
          FaceAvatar(name, size: 64),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: KT.h2), Text(u.s('email'), style: KT.small),
            const SizedBox(height: 6), Pill(u.s('country') == 'GH' ? 'Ghana · ₵ cedi' : 'Nigeria · ₦ naira'),
          ])),
        ])),
        if (isAdmin) ...[
          const SectionLabel('Admin'),
          KtCard(
            color: KT.ink,
            onTap: () async {
              final next = mode == 'admin' ? 'customer' : 'admin';
              await ref.read(modeProvider.notifier).set(next);
              if (!context.mounted) return;
              context.go(next == 'admin' ? '/a/home' : '/c/explore');
            },
            child: Row(children: [
              const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
              const SizedBox(width: 14),
              Expanded(child: Text(mode == 'admin' ? 'Leave admin console' : 'Open admin console', style: KT.h3.copyWith(color: Colors.white))),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ],
        if (mode != 'admin') ...[
        const SectionLabel('Switch side'),
        KtCard(
          color: KT.mint,
          onTap: () async {
            final next = mode == 'vendor' ? 'customer' : 'vendor';
            await ref.read(modeProvider.notifier).set(next);
            if (!context.mounted) return;
            context.go(next == 'vendor' ? (hasStore ? '/v/home' : '/v/setup') : '/c/explore');
          },
          child: Row(children: [
            Icon(mode == 'vendor' ? Icons.shopping_bag_rounded : Icons.storefront_rounded, color: KT.green),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mode == 'vendor' ? 'Switch to buying' : (hasStore ? 'Switch to selling' : 'Start selling'), style: KT.h3),
              Text(mode == 'vendor' ? 'Browse suppliers and place orders.' : 'Open a store and share your link.', style: KT.small),
            ])),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
        ],
        const SectionLabel('More'),
        KtCard(padding: EdgeInsets.zero, child: Column(children: [
          _Row(Icons.notifications_none_rounded, 'Notifications', () => context.push('/notifications')),
          const Divider(),
          _Row(Icons.public_rounded, 'About Kontena', () => launchUrl(Uri.parse(Config.siteUrl))),
          const Divider(),
          _Row(Icons.mail_outline_rounded, 'Contact support', () => launchUrl(Uri.parse('mailto:support@kontena.app'))),
        ])),
        const SizedBox(height: 22),
        KtButton('Log out', kind: BtnKind.danger, onPressed: () async {
          await ref.read(modeProvider.notifier).set(null);
          await FirebaseAuth.instance.signOut();
        }),
      ])),
    ]);
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Row(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(24),
        child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [Icon(icon, color: KT.grey), const SizedBox(width: 14), Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))), const Icon(Icons.chevron_right_rounded, color: KT.grey2)])),
      );
}
