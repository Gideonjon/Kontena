import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../customer/orders_list.dart';
import '../shared/store_page.dart';
import '../shared/wallet.dart';
import 'vendor_orders.dart';
import 'vendor_store.dart';

class VendorHomeScreen extends ConsumerWidget {
  const VendorHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(vendorStoreProvider);
    final wallet = ref.watch(walletProvider).valueOrNull;
    final orders = ref.watch(vendorOrdersProvider).valueOrNull ?? const <Map<String, dynamic>>[];
    final name = (ref.watch(meProvider).valueOrNull?.m('user').s('name') ?? '').split(' ').first;
    final todo = orders.where((o) => o.s('status') == 'funded' || o.s('status') == 'accepted').toList();

    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async {
        ref.invalidate(walletProvider);
        ref.invalidate(vendorOrdersProvider);
        await ref.refresh(vendorStoreProvider.future);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        PageHeader(name.isEmpty ? 'Your dashboard' : 'Hi, $name', subtitle: 'Home'),
        store.when(
          loading: () => const Loading(),
          error: (e, _) => e is ApiException && e.status == 404
              ? EmptyState(icon: Icons.storefront_outlined, title: 'Open your store', body: 'Add your name and products, then share one link with your buyers.',
                  action: KtButton('Set up store', expand: false, onPressed: () => context.go('/v/setup')))
              : ErrorBox(e, retry: () => ref.invalidate(vendorStoreProvider)),
          data: (d) {
            final s = d.m('store');
            final earn = wallet?.m('earnings') ?? {};
            final link = d.s('link');
            final products = d.list('products');
            return Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KtCard(color: KT.ink, padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('AVAILABLE', style: TextStyle(color: Color(0xFF9A9DA5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                const SizedBox(height: 6),
                Text(usd(earn.i('availableCents')), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.8)),
                const SizedBox(height: 6),
                Text('${usd(earn.i('lockedCents'))} locked until inspection', style: const TextStyle(color: Color(0xFF9A9DA5), fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: KtButton('Withdraw', kind: BtnKind.orange, onPressed: earn.i('availableCents') >= 500 ? () => context.push('/v/withdraw') : null)),
                ]),
              ])),
              const SizedBox(height: 14),
              KtCard(color: KT.peach, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.link_rounded, color: KT.orange), const SizedBox(width: 10),
                  Expanded(child: Text('Your store link', style: KT.h3)),
                ]),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Expanded(child: Text(link.replaceFirst('https://', ''), overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
                    IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.copy_rounded, size: 20), onPressed: () { Clipboard.setData(ClipboardData(text: link)); toast(context, 'Link copied'); }),
                  ]),
                ),
                const SizedBox(height: 12),
                KtButton('Share store · QR code', icon: Icons.qr_code_2_rounded, onPressed: () => showShareSheet(context, s.s('slug'), s.s('name'))),
              ])),
              if (products.isEmpty) ...[
                const SizedBox(height: 14),
                KtCard(onTap: () => context.push('/v/product'), child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: KT.mint, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.add_rounded, color: KT.green)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Add your first product', style: KT.h3), Text('Buyers can\'t order until you list something.', style: KT.small)])),
                  const Icon(Icons.chevron_right_rounded),
                ])),
              ],
              SectionLabel('Needs your attention', trailing: todo.isEmpty ? null : Pill('${todo.length}', bg: KT.orange, fg: Colors.white)),
              if (todo.isEmpty)
                KtCard(child: Row(children: [const Icon(Icons.check_circle_outline_rounded, color: KT.green), const SizedBox(width: 12), Expanded(child: Text('You\'re all caught up.', style: KT.body))]))
              else
                for (final o in todo.take(5)) Padding(padding: const EdgeInsets.only(bottom: 10), child: OrderTile(o, title: o.s('buyer_name', 'Buyer'))),
            ]));
          },
        ),
      ]),
    );
  }
}
