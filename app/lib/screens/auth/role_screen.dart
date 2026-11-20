import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/ui.dart';

/// "How will you use Kontena?" One account can do both; this only picks the starting side.
class RoleScreen extends ConsumerStatefulWidget {
  const RoleScreen({super.key});
  @override
  ConsumerState<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends ConsumerState<RoleScreen> {
  String? busy;

  Future<void> _pick(String mode) async {
    setState(() => busy = mode);
    final ok = await guarded(context, () => Api.i.patch('/me', {'role': mode}));
    if (!mounted) return;
    setState(() => busy = null);
    if (ok == null) return;
    await ref.read(modeProvider.notifier).set(mode);
    ref.invalidate(meProvider);
    if (!mounted) return;
    if (mode == 'vendor') {
      final me = await ref.read(meProvider.future);
      if (!mounted) return;
      context.go(me['store'] == null ? '/v/setup' : '/v/home');
    } else {
      context.go('/c/explore');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Constrain(
            max: 480,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 12),
              const Wordmark(size: 22),
              const SizedBox(height: 36),
              Text('How will you\nuse Kontena?', style: KT.h1),
              const SizedBox(height: 8),
              Text('You can switch any time from your profile.', style: KT.body),
              const SizedBox(height: 28),
              _Tile(
                color: KT.peach, icon: Icons.shopping_bag_rounded, title: "I'm buying",
                body: 'Order from suppliers or join a group order. Your money stays protected until goods are inspected.',
                loading: busy == 'customer', onTap: busy != null ? null : () => _pick('customer'),
              ),
              const SizedBox(height: 14),
              _Tile(
                color: KT.mint, icon: Icons.storefront_rounded, title: "I'm selling",
                body: 'Open a store, share one link with your buyers, get a deposit up front and the balance after inspection.',
                loading: busy == 'vendor', onTap: busy != null ? null : () => _pick('vendor'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String title;
  final String body;
  final bool loading;
  final VoidCallback? onTap;
  const _Tile({required this.color, required this.icon, required this.title, required this.body, required this.loading, this.onTap});
  @override
  Widget build(BuildContext context) => KtCard(
        color: color, onTap: onTap, padding: const EdgeInsets.all(22),
        child: Row(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Icon(icon, color: KT.ink, size: 28)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: KT.h2), const SizedBox(height: 4), Text(body, style: KT.body.copyWith(fontSize: 14, color: KT.ink.withOpacity(.7))),
          ])),
          const SizedBox(width: 8),
          loading ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: KT.ink)) : const Icon(Icons.arrow_forward_rounded),
        ]),
      );
}
