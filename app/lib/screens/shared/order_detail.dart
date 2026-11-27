import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/media.dart';
import '../../widgets/ui.dart';
import '../customer/checkout.dart';
import '../customer/orders_list.dart';
import '../vendor/vendor_orders.dart';
import 'order_chat.dart';

const _minPhotos = 3;
const _minVideos = 1;

final orderProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async => (await Api.i.get('/orders/$id')).m('order'));

class OrderDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const OrderDetailScreen({super.key, required this.id});
  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  Timer? _t;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    // gentle polling so payment confirmations and inspection results show up without a manual refresh
    _t = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) ref.invalidate(orderProvider(widget.id));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<Object?> Function() f, {String? done}) async {
    setState(() => busy = true);
    final r = await guarded(context, f);
    if (!mounted) return;
    setState(() => busy = false);
    if (r != null) {
      if (done != null) toast(context, done);
      ref.invalidate(orderProvider(widget.id));
      ref.invalidate(myOrdersProvider);
      ref.invalidate(vendorOrdersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderProvider(widget.id));
    final o = async.valueOrNull;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.canPop() ? context.pop() : context.go('/'))),
      body: o == null
          ? async.when(loading: () => const Loading(), error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(orderProvider(widget.id))), data: (_) => const SizedBox())
          : _body(o),
    );
  }

  Widget _body(Map<String, dynamic> o) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final isBuyer = o.s('buyer_id') == uid;
    final status = o.s('status');
    final total = o.i('total_cents');
    final deposit = o.i('deposit_cents');
    final balance = o.i('balance_cents');
    final store = o.m('store');
    final events = o.list('events');
    final items = o.list('items');
    final proofs = (o['proof_keys'] is List ? o['proof_keys'] as List : const []).whereType<String>().toList();
    final other = isBuyer ? store.s('name') : o.s('buyerName', 'Buyer');

    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(orderProvider(widget.id).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            FaceAvatar(other, size: 52, imageKey: isBuyer && store.s('logo_key').isNotEmpty ? store.s('logo_key') : null),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(other, style: KT.h2), Text('${o.s('ref')} · ${dateDay(o.i('created_at'))}', style: KT.small),
            ])),
            StatusPill(status),
          ]),
          const SizedBox(height: 18),
          _Next(status: status, isBuyer: isBuyer, deposit: deposit, balance: balance, shipBy: o.i('ship_by')),
          const SizedBox(height: 14),
          _Escrow(status: status, total: total, deposit: deposit, balance: balance, fee: o.i('fee_cents')),
          if (o['chain'] is Map && o.m('chain').s('state') != 'offchain' && status != 'awaiting_payment' && status != 'cancelled') ...[
            const SizedBox(height: 14),
            _StellarProof(o.m('chain')),
          ],
          if (o['pool'] is Map) ...[
            const SizedBox(height: 14),
            KtCard(child: Row(children: [
              const Icon(Icons.groups_rounded, color: KT.orange), const SizedBox(width: 12),
              Expanded(child: Text('Group order · ${o.m('pool').i('joined_qty')} of ${o.m('pool').i('target_qty')} units joined', style: const TextStyle(fontWeight: FontWeight.w800))),
            ])),
          ],
          ..._actions(o, isBuyer, status),
          if (status != 'cancelled') ...[
            const SectionLabel('Messages'),
            OrderChat(orderId: o.s('id')),
          ],
          const SectionLabel('Items'),
          KtCard(child: Column(children: [
            for (final it in items) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              Expanded(child: Text('${it.i('qty')} × ${it.s('name')}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(usd(it.i('qty') * it.i('unit_cents')), style: const TextStyle(fontWeight: FontWeight.w800)),
            ])),
            const Divider(height: 22),
            Row(children: [const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800))), Text(usd(total), style: KT.h3)]),
          ])),
          if (proofs.isNotEmpty) ...[
            const SectionLabel('Supplier proof'),
            SizedBox(height: 110, child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final k in proofs) _ProofTile(k),
            ])),
          ],
          const SectionLabel('Activity'),
          KtCard(child: Column(children: [
            for (var i = events.length - 1; i >= 0; i--) _EventRow(events[i], last: i == 0),
          ])),
        ])),
      ]),
    );
  }

  List<Widget> _actions(Map<String, dynamic> o, bool isBuyer, String status) {
    final id = o.s('id');
    final w = <Widget>[const SizedBox(height: 18)];
    if (isBuyer && status == 'awaiting_payment') {
      w.add(KtButton('Pay now', kind: BtnKind.orange, loading: busy, onPressed: () => _payChooser(id)));
      w.add(const SizedBox(height: 8));
      w.add(KtButton('Cancel order', kind: BtnKind.danger, onPressed: busy ? null : () => _act(() => Api.i.post('/orders/$id/cancel'), done: 'Order cancelled')));
    } else if (isBuyer && status == 'inspection') {
      w.add(KtButton('Goods look right: release balance', loading: busy, onPressed: () => _act(() => Api.i.post('/orders/$id/inspection', {'pass': true}), done: 'Balance released to supplier')));
      w.add(const SizedBox(height: 8));
      w.add(KtButton('Report a problem', kind: BtnKind.danger, onPressed: busy ? null : () => _problem(id)));
    } else if (isBuyer && status == 'shipped') {
      w.add(KtButton('I received my goods', loading: busy, onPressed: () => _act(() => Api.i.post('/orders/$id/confirm-delivery'), done: 'Marked as delivered')));
    } else if (!isBuyer && status == 'funded') {
      w.add(KtButton('Accept order · get ${usd(o.i('deposit_cents'))}', kind: BtnKind.orange, loading: busy, onPressed: () => _act(() => Api.i.post('/vendor/orders/$id/accept'), done: 'Deposit released to your wallet')));
    } else if (!isBuyer && status == 'accepted') {
      w.add(KtButton('Goods ready: upload proof', icon: Icons.photo_camera_rounded, loading: busy, onPressed: () => _ready(id)));
    } else {
      return const [];
    }
    return w;
  }

  void _payChooser(String id) {
    showModalBottomSheet(context: context, builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pay with', style: KT.h2), const SizedBox(height: 16),
        KtButton('Card, bank or Mobile Money', icon: Icons.credit_card_rounded, onPressed: () { Navigator.pop(ctx); _act(() async => await payOrder(context, id, 'card') ? {'ok': 1} : null); }),
        const SizedBox(height: 10),
        KtButton('USDC wallet', icon: Icons.currency_exchange_rounded, kind: BtnKind.ghost, onPressed: () { Navigator.pop(ctx); _act(() async => await payOrder(context, id, 'usdc') ? {'ok': 1} : null, done: 'Payment sent. Confirming on the network…'); }),
      ]),
    ));
  }

  void _problem(String id) {
    final c = TextEditingController();
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('What\'s wrong?', style: KT.h2), const SizedBox(height: 6),
        Text('The locked balance is refunded to you. The supplier keeps the deposit already released.', style: KT.body), const SizedBox(height: 16),
        KtField(c, 'Describe the problem', maxLines: 3),
        KtButton('Refund the balance', kind: BtnKind.danger, onPressed: () { Navigator.pop(ctx); _act(() => Api.i.post('/orders/$id/inspection', {'pass': false, 'note': c.text.trim()}), done: 'Refund started'); }),
      ]),
    ));
  }

  Future<void> _ready(String id) async {
    final photos = <String>[];
    final videos = <String>[];
    final noteC = TextEditingController();
    final send = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final ok = photos.length >= _minPhotos && videos.length >= _minVideos;
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Show the goods', style: KT.h2), const SizedBox(height: 6),
          Text('Upload at least $_minPhotos clear photos and $_minVideos short video (under 1 minute) so the buyer and inspector can check everything.', style: KT.body),
          const SizedBox(height: 16),
          _ProofRow(icon: Icons.photo_camera_rounded, label: 'Photos', have: photos.length, need: _minPhotos, onAdd: () async {
            final k = await pickAndUploadImages(ctx, multi: true);
            set(() => photos.addAll(k));
          }),
          const SizedBox(height: 10),
          _ProofRow(icon: Icons.videocam_rounded, label: 'Video', have: videos.length, need: _minVideos, onAdd: () async {
            final k = await pickAndUploadVideo(ctx);
            if (k != null) set(() => videos.add(k));
          }),
          const SizedBox(height: 10),
          KtField(noteC, 'Note for the buyer (optional)', maxLines: 2),
          KtButton('Send for inspection', onPressed: ok ? () => Navigator.pop(ctx, true) : null),
        ]),
      );
    }));
    if (send != true || !mounted) return;
    await _act(() => Api.i.post('/vendor/orders/$id/ready', {'proofKeys': [...photos, ...videos], 'note': noteC.text.trim()}), done: 'Sent for inspection');
  }
}

class _ProofRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int have, need;
  final Future<void> Function() onAdd;
  const _ProofRow({required this.icon, required this.label, required this.have, required this.need, required this.onAdd});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: have >= need ? KT.mint : KT.paper, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, color: KT.ink), const SizedBox(width: 12),
          Expanded(child: Text('$label · $have added (need $need+)', style: const TextStyle(fontWeight: FontWeight.w700))),
          TextButton(onPressed: onAdd, child: Text(have == 0 ? 'Add' : 'Add more')),
        ]),
      );
}

/// One piece of supplier evidence: photos open full size, videos open in the browser's player.
class _ProofTile extends StatelessWidget {
  final String k;
  const _ProofTile(this.k);
  @override
  Widget build(BuildContext context) {
    final video = isVideoKey(k);
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: GestureDetector(
          onTap: () => video
              ? launchUrl(Uri.parse(Api.mediaUrl(k)), mode: LaunchMode.externalApplication)
              : showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(Api.mediaUrl(k))))),
          child: video
              ? Container(width: 110, height: 110, color: KT.ink, child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 42), SizedBox(height: 4),
                  Text('Video', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ]))
              : Image.network(Api.mediaUrl(k), width: 110, height: 110, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _Next extends StatelessWidget {
  final String status;
  final bool isBuyer;
  final int deposit, balance, shipBy;
  const _Next({required this.status, required this.isBuyer, required this.deposit, required this.balance, required this.shipBy});
  @override
  Widget build(BuildContext context) {
    final (icon, text, bg) = switch ((status, isBuyer)) {
      ('awaiting_payment', true) => (Icons.payments_rounded, 'Complete your payment to lock in this order.', KT.butter),
      ('awaiting_payment', false) => (Icons.hourglass_top_rounded, 'Waiting for the buyer to pay.', KT.butter),
      ('funded', true) => (Icons.lock_rounded, 'Your money is safe in escrow. Waiting for the supplier to accept.', KT.sky),
      ('funded', false) => (Icons.bolt_rounded, 'Payment is in escrow. Accept now to receive your ${usd(deposit)} deposit.', KT.peach),
      ('accepted', true) => (Icons.precision_manufacturing_rounded, 'Supplier is preparing your goods.${shipBy > 0 ? ' Due by ${dateDay(shipBy)}.' : ''}', KT.peach),
      ('accepted', false) => (Icons.inventory_rounded, 'Ship by ${shipBy > 0 ? dateDay(shipBy) : 'the deadline'}, then upload proof to unlock ${usd(balance)}.', KT.peach),
      ('inspection', true) => (Icons.fact_check_rounded, 'Check the supplier\'s photos. Release the balance if everything is right.', KT.butter),
      ('inspection', false) => (Icons.fact_check_rounded, 'Inspection in progress. ${usd(balance)} releases when it passes.', KT.butter),
      ('shipped', true) => (Icons.local_shipping_rounded, 'Your goods passed inspection and are on their way.', KT.sky),
      ('shipped', false) => (Icons.local_shipping_rounded, 'Balance released. Waiting for delivery confirmation.', KT.sky),
      ('delivered', _) => (Icons.check_circle_rounded, 'All done. This order is complete.', KT.mint),
      ('refunded', true) => (Icons.replay_rounded, 'Refunded. The money is on its way back to you.', const Color(0xFFFDECEA)),
      ('refunded', false) => (Icons.replay_rounded, 'This order was refunded to the buyer.', const Color(0xFFFDECEA)),
      _ => (Icons.info_outline_rounded, 'This order was cancelled.', KT.paper),
    };
    return Container(
      padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [Icon(icon, color: KT.ink), const SizedBox(width: 12), Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35)))]),
    );
  }
}

class _Escrow extends StatelessWidget {
  final String status;
  final int total, deposit, balance, fee;
  const _Escrow({required this.status, required this.total, required this.deposit, required this.balance, required this.fee});
  @override
  Widget build(BuildContext context) {
    final released = switch (status) { 'accepted' || 'inspection' => deposit, 'shipped' || 'delivered' => deposit + balance, _ => 0 };
    final paid = status != 'awaiting_payment' && status != 'cancelled';
    final subtotal = deposit + balance;
    final locked = paid && status != 'refunded' ? total - released : 0;
    return KtCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ESCROW', style: KT.label),
      const SizedBox(height: 10),
      Text(usd(total), style: KT.h1.copyWith(fontSize: 34)),
      const SizedBox(height: 14),
      ClipRRect(borderRadius: BorderRadius.circular(99), child: SizedBox(height: 12, child: Row(children: [
        if (released > 0) Expanded(flex: released, child: Container(color: KT.green)),
        if (locked > 0) Expanded(flex: locked, child: Container(color: KT.orange)),
        if (released == 0 && locked == 0) Expanded(child: Container(color: KT.line)),
      ]))),
      const SizedBox(height: 12),
      Row(children: [
        _Legend(KT.green, 'Released', usd(released)),
        const SizedBox(width: 24),
        _Legend(KT.orange, 'Locked', usd(locked)),
      ]),
      if (paid) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${usd(deposit)} deposit · ${usd(balance)} balance · ${usd(fee)} protection fee', style: KT.small)),
      if (!paid && subtotal > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Nothing is charged until you pay.', style: KT.small)),
    ]));
  }
}

/// Shows that the money sits in a Stellar smart contract, with every step linked to the public explorer.
class _StellarProof extends StatelessWidget {
  final Map<String, dynamic> c;
  const _StellarProof(this.c);

  static const _titles = {
    'convert': 'Naira converted to USDC',
    'fund': 'Locked in the smart contract',
    'accept': '30% deposit paid to supplier',
    'release': '70% balance paid after inspection',
    'refund': 'Refunded by the contract',
    'expire': 'Deadline refund by the contract',
  };
  static const _icons = {
    'convert': Icons.currency_exchange_rounded, 'fund': Icons.lock_rounded, 'accept': Icons.handshake_rounded,
    'release': Icons.verified_rounded, 'refund': Icons.replay_rounded, 'expire': Icons.timer_off_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final txs = c.list('txs');
    final state = c.s('state');
    final testnet = c.s('network') != 'public';
    final lead = switch (state) {
      'funded' => 'Your money is locked in a smart contract. It can only go to the supplier or back to you.',
      'accepted' => 'Deposit paid. The balance stays locked in the contract until inspection passes.',
      'released' => 'Paid in full by the contract after inspection.',
      'refunded' => 'The contract returned the locked money.',
      _ => 'Recording this order on Stellar…',
    };
    return KtCard(color: KT.ink, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Icon(Icons.shield_rounded, color: KT.orange, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text('PROTECTED ON STELLAR', style: KT.label.copyWith(color: Colors.white))),
        if (testnet) Text('TESTNET', style: KT.small.copyWith(color: KT.orange)),
      ]),
      const SizedBox(height: 10),
      Text(lead, style: KT.body.copyWith(color: const Color(0xFFD5D6DA))),
      if (c.s('error').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Retrying on Stellar. Your money is safe.', style: KT.small.copyWith(color: KT.orange))),
      if (txs.isNotEmpty) const SizedBox(height: 12),
      for (final t in txs) InkWell(
        onTap: () => launchUrl(Uri.parse(t.s('url')), mode: LaunchMode.externalApplication),
        borderRadius: BorderRadius.circular(12),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
          Icon(_icons[t.s('step')] ?? Icons.link_rounded, color: KT.orange, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_titles[t.s('step')] ?? t.s('step'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            Text('${t.s('hash').substring(0, 8)}…  ·  ${dateShort(t.i('at'))}', style: KT.small.copyWith(color: const Color(0xFFA9ABB2))),
          ])),
          Text('View on Stellar ↗', style: KT.small.copyWith(color: KT.orange, fontWeight: FontWeight.w800)),
        ])),
      ),
      if (c.s('contractUrl').isNotEmpty) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: Colors.white, padding: EdgeInsets.zero),
          onPressed: () => launchUrl(Uri.parse(c.s('contractUrl')), mode: LaunchMode.externalApplication),
          icon: const Icon(Icons.open_in_new_rounded, size: 16),
          label: const Text('Check the escrow contract yourself', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    ]));
  }
}

class _Legend extends StatelessWidget {
  final Color c;
  final String a, b;
  const _Legend(this.c, this.a, this.b);
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)), const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a, style: KT.small), Text(b, style: const TextStyle(fontWeight: FontWeight.w800))]),
      ]);
}

class _EventRow extends StatelessWidget {
  final Map<String, dynamic> e;
  final bool last;
  const _EventRow(this.e, {required this.last});
  @override
  Widget build(BuildContext context) {
    final t = e.s('type');
    final bad = const {'refund_failed', 'inspection_failed', 'missed_deadline', 'expired'}.contains(t);
    final icon = switch (t) {
      'created' => Icons.add_circle_outline_rounded, 'funded' || 'payment_sent' => Icons.lock_rounded, 'accepted' => Icons.handshake_rounded,
      'inspection_requested' => Icons.photo_camera_rounded, 'inspection_passed' => Icons.verified_rounded, 'delivered' => Icons.check_circle_rounded,
      'refund_sent' => Icons.replay_rounded,
      'chain_convert' || 'chain_fund' || 'chain_accept' || 'chain_release' || 'chain_refund' || 'chain_expire' => Icons.shield_rounded,
      _ => Icons.circle_outlined,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: bad ? const Color(0xFFFDECEA) : KT.paper, shape: BoxShape.circle), child: Icon(icon, size: 17, color: bad ? KT.red : KT.ink)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.s('note'), style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3)), Text(dateShort(e.i('created_at')), style: KT.small),
        ])),
      ]),
    );
  }
}
