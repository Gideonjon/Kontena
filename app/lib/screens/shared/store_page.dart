import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/web_auth.dart';
import '../../core/format.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/ui.dart';
import '../customer/checkout.dart';

final storeProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, slug) => Api.i.get('/stores/$slug'));

class StorePage extends ConsumerStatefulWidget {
  final String slug;
  const StorePage({super.key, required this.slug});
  @override
  ConsumerState<StorePage> createState() => _StorePageState();
}

class _StorePageState extends ConsumerState<StorePage> {
  final Map<String, int> cart = {};

  int _subtotal(List<Map<String, dynamic>> products) {
    var t = 0;
    for (final p in products) {
      t += (cart[p.s('id')] ?? 0) * p.i('price_cents');
    }
    return t;
  }

  bool _requireAuth() {
    if (FirebaseAuth.instance.currentUser != null) return true;
    ref.read(prefsProvider).setString('pending_store', widget.slug);
    toast(context, 'Create a free account to order. Your cart will be waiting.');
    goAuth(context, signUp: true, next: '/s/${widget.slug}');
    return false;
  }

  /// Opens (or reopens) the chat with this supplier. A tapped product rides along as a card on the first message.
  Future<void> _message(Map<String, dynamic> store, [Map<String, dynamic>? product]) async {
    if (!_requireAuth()) return;
    final r = await guarded(context, () => Api.i.post('/inbox/start', {'storeId': store.s('id')}));
    if (r == null || !mounted) return;
    context.push('/chat/inquiry/${r.s('id')}', extra: product);
  }

  void _checkout(Map<String, dynamic> store, List<Map<String, dynamic>> products) {
    if (!_requireAuth()) return;
    final lines = [
      for (final p in products)
        if ((cart[p.s('id')] ?? 0) > 0) CheckoutLine(p.s('id'), p.s('name'), p.i('price_cents'), cart[p.s('id')]!, p.i('lead_days')),
    ];
    context.push('/checkout', extra: CheckoutArgs(storeId: store.s('id'), storeName: store.s('name'), lines: lines));
  }

  void _setQty(Map<String, dynamic> p, int q) {
    final min = p.i('min_qty');
    setState(() {
      if (q < min) {
        cart.remove(p.s('id'));
      } else {
        cart[p.s('id')] = q;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(storeProvider(widget.slug));
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        actions: [
          IconButton(icon: const Icon(Icons.ios_share_rounded), onPressed: () => Share.share('${Config.siteUrl}/s/${widget.slug}')),
        ],
      ),
      body: async.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(storeProvider(widget.slug))),
        data: (d) {
          final store = d.m('store');
          final products = d.list('products');
          final pools = d.list('pools');
          final subtotal = _subtotal(products);
          return Stack(children: [
            RefreshIndicator(
              color: KT.orange,
              onRefresh: () async => ref.refresh(storeProvider(widget.slug).future),
              child: ListView(padding: EdgeInsets.fromLTRB(20, 0, 20, subtotal > 0 ? 120 : 40), children: [
                Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _Header(store, onMessage: () => _message(store)),
                  if (pools.isNotEmpty) ...[
                    const SectionLabel('Open group orders'),
                    for (final pl in pools) _PoolCard(pool: pl, product: products.firstWhere((p) => p.s('id') == pl.s('product_id'), orElse: () => {}),
                        store: store, onNeedAuth: _requireAuth),
                  ],
                  const SectionLabel('Products'),
                  if (products.isEmpty)
                    const EmptyState(icon: Icons.inventory_2_outlined, title: 'No products yet', body: 'This supplier hasn\'t listed anything yet.')
                  else
                    for (final p in products) _ProductTile(p, qty: cart[p.s('id')] ?? 0, onQty: (q) => _setQty(p, q), onAsk: () => _message(store, p)),
                  const SizedBox(height: 18),
                  KtCard(color: KT.mint, child: Row(children: [
                    const Icon(Icons.lock_rounded, color: KT.green),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Your payment is held in escrow. Only a 30% deposit goes to the supplier up front. The rest is released after inspection.', style: KT.body.copyWith(color: KT.ink, fontSize: 13.5))),
                  ])),
                ])),
              ]),
            ),
            if (subtotal > 0)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  color: Colors.white, padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
                  child: SafeArea(top: false, child: Constrain(child: KtButton('Checkout · ${usd(subtotal)}', kind: BtnKind.orange, onPressed: () => _checkout(store, products)))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Map<String, dynamic> s;
  final VoidCallback onMessage;
  const _Header(this.s, {required this.onMessage});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(22), child: s.s('logo_key').isNotEmpty
            ? Image.network(Api.mediaUrl(s.s('logo_key')), width: 72, height: 72, fit: BoxFit.cover, errorBuilder: (_, __, ___) => FaceAvatar(s.s('name'), size: 72))
            : FaceAvatar(s.s('name'), size: 72)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.s('name'), style: KT.h1.copyWith(fontSize: 26)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (s.b('verified')) const Pill('Verified', bg: KT.mint, fg: KT.green),
            Pill(s.s('country') == 'GH' ? 'Ghana' : 'Nigeria'),
            if (s.s('city').isNotEmpty) Pill(s.s('city')),
          ]),
        ])),
      ]),
      if (s.s('bio').isNotEmpty) ...[const SizedBox(height: 14), Text(s.s('bio'), style: KT.body)],
      const SizedBox(height: 14),
      KtButton('Message supplier', kind: BtnKind.soft, icon: Icons.chat_bubble_outline_rounded, expand: false, onPressed: onMessage),
    ]);
  }
}

class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> p;
  final int qty;
  final void Function(int) onQty;
  final VoidCallback onAsk;
  const _ProductTile(this.p, {required this.qty, required this.onQty, required this.onAsk});
  @override
  Widget build(BuildContext context) {
    final min = p.i('min_qty');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KtCard(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(16), child: p.s('image_key').isNotEmpty
              ? Image.network(Api.mediaUrl(p.s('image_key')), width: 76, height: 76, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph())
              : _ph()),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.s('name'), style: KT.h3),
            if (p.s('description').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(p.s('description'), maxLines: 2, overflow: TextOverflow.ellipsis, style: KT.body.copyWith(fontSize: 13))),
            const SizedBox(height: 6),
            Text('${usdShort(p.i('price_cents'))} each · min $min · ~${p.i('lead_days')} days', style: KT.small),
            const SizedBox(height: 10),
            qty == 0
                ? Wrap(spacing: 8, runSpacing: 8, children: [
                    KtButton('Add $min', kind: BtnKind.soft, expand: false, onPressed: () => onQty(min)),
                    KtButton('Ask', kind: BtnKind.ghost, icon: Icons.chat_bubble_outline_rounded, expand: false, onPressed: onAsk),
                  ])
                : Row(children: [
                    _Step(Icons.remove_rounded, () => onQty(qty - (qty > min ? 1 : min))),
                    SizedBox(width: 56, child: Text('$qty', textAlign: TextAlign.center, style: KT.h3)),
                    _Step(Icons.add_rounded, () => onQty(qty + 1)),
                    const Spacer(),
                    Text(usd(qty * p.i('price_cents')), style: KT.h3),
                  ]),
          ])),
        ]),
      ),
    );
  }

  Widget _ph() => Container(width: 76, height: 76, color: KT.peach, child: const Icon(Icons.inventory_2_rounded, color: KT.orange));
}

class _Step extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _Step(this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => Material(color: KT.paper, shape: const CircleBorder(), child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: Padding(padding: const EdgeInsets.all(8), child: Icon(icon, size: 20))));
}

class _PoolCard extends ConsumerWidget {
  final Map<String, dynamic> pool;
  final Map<String, dynamic> product;
  final Map<String, dynamic> store;
  final bool Function() onNeedAuth;
  const _PoolCard({required this.pool, required this.product, required this.store, required this.onNeedAuth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (product.isEmpty) return const SizedBox();
    final target = pool.i('target_qty');
    final joined = pool.i('joined_qty');
    final frac = target == 0 ? 0.0 : (joined / target).clamp(0.0, 1.0);
    final members = pool.i('members');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KtCard(
        color: KT.peach,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(product.s('name'), style: KT.h3)),
            Pill(timeLeft(pool.i('ends_at')), bg: Colors.white),
          ]),
          const SizedBox(height: 4),
          Text('${usdShort(product.i('price_cents'))} each when the group fills', style: KT.small),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: frac, minHeight: 8, color: KT.orange, backgroundColor: Colors.white)),
          const SizedBox(height: 8),
          Row(children: [
            if (members > 0) FaceStack([for (var i = 0; i < members.clamp(1, 4); i++) '${pool.s('id')}$i'], size: 26, more: members > 4 ? members - 4 : 0),
            if (members > 0) const SizedBox(width: 8),
            Expanded(child: Text('$joined of $target units', style: const TextStyle(fontWeight: FontWeight.w800))),
            KtButton('Join', expand: false, onPressed: () {
              if (!onNeedAuth()) return;
              _join(context, ref);
            }),
          ]),
        ]),
      ),
    );
  }

  void _join(BuildContext context, WidgetRef ref) {
    final min = product.i('min_qty');
    final c = TextEditingController(text: '$min');
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Join this group order', style: KT.h2),
          const SizedBox(height: 6),
          Text('Your money goes into escrow, same as any order. Minimum $min units.', style: KT.body),
          const SizedBox(height: 16),
          KtField(c, 'How many units?', keyboard: TextInputType.number),
          KtButton('Continue', onPressed: () {
            final q = int.tryParse(c.text) ?? 0;
            if (q < min) { toast(ctx, 'Minimum is $min units.'); return; }
            Navigator.pop(ctx);
            context.push('/checkout', extra: CheckoutArgs(
              storeId: store.s('id'), storeName: store.s('name'), poolId: pool.s('id'),
              lines: [CheckoutLine(product.s('id'), product.s('name'), product.i('price_cents'), q, product.i('lead_days'))],
            ));
          }),
        ]),
      ),
    );
  }
}

/// Shared by the vendor "share my store" sheet.
void showShareSheet(BuildContext context, String slug, String name) {
  final link = '${Config.siteUrl}/s/$slug';
  showModalBottomSheet(
    context: context, isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Share your store', style: KT.h2),
        const SizedBox(height: 4),
        Text('Anyone with this link can see your products and order safely.', style: KT.body, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: KT.line)),
          child: QrImageView(data: link, size: 200, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: KT.ink), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: KT.ink)),
        ),
        const SizedBox(height: 14),
        SelectableText(link, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 18),
        KtButton('Share link', icon: Icons.ios_share_rounded, onPressed: () => Share.share('Shop $name safely on Kontena: $link')),
      ]),
    ),
  );
}
