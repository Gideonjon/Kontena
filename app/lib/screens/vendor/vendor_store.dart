import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/media.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import '../shared/store_page.dart';

final vendorStoreProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => Api.i.get('/vendor/store'));

class VendorStoreScreen extends ConsumerWidget {
  const VendorStoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(vendorStoreProvider);
    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(vendorStoreProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        PageHeader('My store', subtitle: 'Store', actions: [
          IconButton(icon: const Icon(Icons.add_circle_rounded, color: KT.orange, size: 30), onPressed: () => context.push('/v/product')),
        ]),
        async.when(
          loading: () => const Loading(),
          error: (e, _) => e is ApiException && e.status == 404
              ? EmptyState(icon: Icons.storefront_outlined, title: 'No store yet', body: 'Set up your store to start selling.', action: KtButton('Set up store', expand: false, onPressed: () => context.go('/v/setup')))
              : ErrorBox(e, retry: () => ref.invalidate(vendorStoreProvider)),
          data: (d) {
            final s = d.m('store');
            final products = d.list('products');
            return Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KtCard(child: Row(children: [
                GestureDetector(
                  onTap: () async {
                    final k = await pickAndUploadImages(context);
                    if (k.isEmpty || !context.mounted) return;
                    await guarded(context, () => Api.i.patch('/vendor/store', {'logoKey': k.first}));
                    ref.invalidate(vendorStoreProvider);
                  },
                  child: Stack(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(20), child: s.s('logo_key').isNotEmpty
                        ? Image.network(Api.mediaUrl(s.s('logo_key')), width: 68, height: 68, fit: BoxFit.cover, errorBuilder: (_, __, ___) => FaceAvatar(s.s('name'), size: 68))
                        : FaceAvatar(s.s('name'), size: 68)),
                    Positioned(right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: KT.ink, shape: BoxShape.circle), child: const Icon(Icons.edit_rounded, size: 12, color: Colors.white))),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.s('name'), style: KT.h2), Text('kontena.app/s/${s.s('slug')}', style: KT.small),
                  const SizedBox(height: 6),
                  s.b('verified') ? const Pill('Verified', bg: KT.mint, fg: KT.green) : const Pill('Not verified yet'),
                ])),
                IconButton(icon: const Icon(Icons.ios_share_rounded), onPressed: () => showShareSheet(context, s.s('slug'), s.s('name'))),
              ])),
              const SectionLabel('Products'),
              if (products.isEmpty)
                EmptyState(icon: Icons.inventory_2_outlined, title: 'No products yet', body: 'Add what you sell, with a price and minimum order.', action: KtButton('Add product', expand: false, onPressed: () => context.push('/v/product')))
              else
                for (final p in products) Padding(padding: const EdgeInsets.only(bottom: 10), child: _ProductRow(p)),
            ]));
          },
        ),
      ]),
    );
  }
}

class _ProductRow extends ConsumerWidget {
  final Map<String, dynamic> p;
  const _ProductRow(this.p);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = p.b('active');
    return Opacity(
      opacity: active ? 1 : 0.55,
      child: KtCard(
        onTap: () => context.push('/v/product', extra: p),
        child: Row(children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: p.s('image_key').isNotEmpty
              ? Image.network(Api.mediaUrl(p.s('image_key')), width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph())
              : _ph()),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.s('name'), style: KT.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${usdShort(p.i('price_cents'))} · min ${p.i('min_qty')} · ${p.i('lead_days')} days${active ? '' : ' · hidden'}', style: KT.small),
          ])),
          IconButton(
            tooltip: 'Open a group order', icon: const Icon(Icons.groups_rounded, color: KT.orange),
            onPressed: active ? () => _pool(context, ref) : null,
          ),
        ]),
      ),
    );
  }

  Widget _ph() => Container(width: 56, height: 56, color: KT.peach, child: const Icon(Icons.inventory_2_rounded, color: KT.orange));

  void _pool(BuildContext context, WidgetRef ref) {
    final target = TextEditingController(text: '500');
    final days = TextEditingController(text: '14');
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Open a group order', style: KT.h2), const SizedBox(height: 6),
        Text('Let small buyers pool together to hit a container-size order of ${p.s('name')}.', style: KT.body), const SizedBox(height: 16),
        KtField(target, 'Target quantity (units)', keyboard: TextInputType.number),
        KtField(days, 'Open for how many days?', keyboard: TextInputType.number),
        KtButton('Open group order', onPressed: () async {
          final r = await guarded(ctx, () => Api.i.post('/vendor/pools', {'productId': p.s('id'), 'targetQty': int.tryParse(target.text) ?? 0, 'days': int.tryParse(days.text) ?? 14}));
          if (r != null && ctx.mounted) { Navigator.pop(ctx); toast(context, 'Group order is live on your store'); }
        }),
      ]),
    ));
  }
}
