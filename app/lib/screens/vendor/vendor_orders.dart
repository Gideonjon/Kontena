import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../customer/orders_list.dart';

final vendorOrdersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async => (await Api.i.get('/vendor/orders')).list('orders'));

class VendorOrdersScreen extends ConsumerStatefulWidget {
  const VendorOrdersScreen({super.key});
  @override
  ConsumerState<VendorOrdersScreen> createState() => _VendorOrdersScreenState();
}

class _VendorOrdersScreenState extends ConsumerState<VendorOrdersScreen> {
  String filter = 'all';
  static const filters = [('all', 'All'), ('funded', 'New'), ('accepted', 'In progress'), ('inspection', 'Inspection'), ('shipped', 'Shipped'), ('delivered', 'Done')];

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(vendorOrdersProvider);
    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(vendorOrdersProvider.future),
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const PageHeader('Orders', subtitle: 'Sales'),
        SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
          for (final f in filters) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
            label: Text(f.$2), selected: filter == f.$1, onSelected: (_) => setState(() => filter = f.$1), showCheckmark: false,
            selectedColor: KT.ink, backgroundColor: Colors.white, side: BorderSide.none,
            labelStyle: TextStyle(fontWeight: FontWeight.w800, color: filter == f.$1 ? Colors.white : KT.ink),
          )),
        ])),
        const SizedBox(height: 8),
        async.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(vendorOrdersProvider)),
          data: (all) {
            final list = filter == 'all' ? all : all.where((o) => o.s('status') == filter).toList();
            return list.isEmpty
                ? const EmptyState(icon: Icons.inventory_2_outlined, title: 'No orders here', body: 'Share your store link and orders will appear as soon as buyers pay.')
                : Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
                    for (final o in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: OrderTile(o, title: o.s('buyer_name', 'Buyer'))),
                  ]));
          },
        ),
      ]),
    );
  }
}
