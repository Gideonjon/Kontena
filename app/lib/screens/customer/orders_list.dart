import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';

final myOrdersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => (await Api.i.get('/orders')).list('orders'));

class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myOrdersProvider);
    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(myOrdersProvider.future),
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const PageHeader('Your orders', subtitle: 'Orders'),
        async.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(myOrdersProvider)),
          data: (list) => list.isEmpty
              ? EmptyState(icon: Icons.inventory_2_outlined, title: 'No orders yet', body: 'When you order from a supplier, you\'ll track every step here.',
                  action: KtButton('Find suppliers', expand: false, onPressed: () => context.go('/c/explore')))
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [for (final o in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: OrderTile(o))]),
                ),
        ),
      ]),
    );
  }
}

class OrderTile extends StatelessWidget {
  final Map<String, dynamic> o;
  final String? title;
  const OrderTile(this.o, {super.key, this.title});
  @override
  Widget build(BuildContext context) {
    final name = title ?? o.s('store_name', o.s('buyer_name'));
    return KtCard(
      onTap: () => context.push('/order/${o.s('id')}'),
      child: Row(children: [
        FaceAvatar(name, size: 46, imageKey: o.s('logo_key').isEmpty ? null : o.s('logo_key')),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Flexible(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: KT.h3)), const SizedBox(width: 8), StatusPill(o.s('status'))]),
          const SizedBox(height: 3),
          Text(o.s('summary'), maxLines: 1, overflow: TextOverflow.ellipsis, style: KT.small),
          Text('${o.s('ref')} · ${dateShort(o.i('created_at'))}', style: KT.small),
        ])),
        const SizedBox(width: 8),
        Text(usd(o.i('total_cents')), style: KT.h3),
      ]),
    );
  }
}
