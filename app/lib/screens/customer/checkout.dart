import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../shared/wallet.dart';

class CheckoutLine {
  final String productId;
  final String name;
  final int unitCents;
  final int qty;
  final int leadDays;
  CheckoutLine(this.productId, this.name, this.unitCents, this.qty, this.leadDays);
}

class CheckoutArgs {
  final String storeId;
  final String storeName;
  final List<CheckoutLine> lines;
  final String? poolId;
  CheckoutArgs({required this.storeId, required this.storeName, required this.lines, this.poolId});
}

final fxProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => Api.i.get('/fx'));

/// Starts payment for an existing order. Card opens Paystack checkout, USDC sends from the in-app wallet.
Future<bool> payOrder(BuildContext context, String orderId, String method) async {
  final r = await guarded(context, () => Api.i.post('/orders/$orderId/pay', {'method': method}));
  if (r == null) return false;
  if (method == 'card' && r.s('url').isNotEmpty) {
    await launchUrl(Uri.parse(r.s('url')), webOnlyWindowName: kIsWeb ? '_self' : null, mode: LaunchMode.externalApplication);
  }
  return true;
}

class CheckoutScreen extends ConsumerStatefulWidget {
  final CheckoutArgs args;
  const CheckoutScreen({super.key, required this.args});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String method = 'card';
  bool busy = false;

  int get subtotal => widget.args.lines.fold(0, (a, l) => a + l.unitCents * l.qty);
  int get fee => (subtotal * 0.015).round();
  int get deposit => (subtotal * 0.30).round();

  Future<void> _place() async {
    setState(() => busy = true);
    final a = widget.args;
    final r = await guarded(context, () => a.poolId != null
        ? Api.i.post('/orders/join-pool', {'poolId': a.poolId, 'qty': a.lines.first.qty})
        : Api.i.post('/orders', {'storeId': a.storeId, 'items': [for (final l in a.lines) {'productId': l.productId, 'qty': l.qty}]}));
    if (r == null) { if (mounted) setState(() => busy = false); return; }
    final id = r.m('order').s('id');
    if (!mounted) return;
    await payOrder(context, id, method);
    ref.invalidate(walletProvider);
    if (!mounted) return;
    setState(() => busy = false);
    context.go('/order/$id');
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull ?? {};
    final country = me.m('user').s('country', 'NG');
    final fx = ref.watch(fxProvider).valueOrNull;
    final wallet = ref.watch(walletProvider).valueOrNull;
    final total = subtotal + fee;
    final rate = fx == null ? null : (country == 'GH' ? fx['USD_GHS'] : fx['USD_NGN']);
    final local = rate == null ? null : (total / 100) * (rate as num) * 1.015;
    final sym = country == 'GH' ? '₵' : '₦';
    final usdcBalance = double.tryParse(wallet?.s('usdc') ?? '0') ?? 0;
    final usdcOk = usdcBalance >= (total + 10) / 100;
    final nairaBal = wallet?.m('naira').i('balanceKobo') ?? 0;
    final nairaNeed = (total * ((fx == null ? 1500 : (fx['USD_NGN'] as num)).toDouble()) * 1.015).ceil();
    final nairaOk = country == 'NG' && fx != null && nairaBal >= nairaNeed;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        child: Constrain(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KtCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.args.storeName, style: KT.label),
            const SizedBox(height: 10),
            for (final l in widget.args.lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
              Expanded(child: Text('${l.qty} × ${l.name}', style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(usd(l.qty * l.unitCents), style: const TextStyle(fontWeight: FontWeight.w800)),
            ])),
            const Divider(height: 24),
            _Row('Subtotal', usd(subtotal)),
            _Row('Protection fee (1.5%)', usd(fee)),
            const SizedBox(height: 6),
            _Row('Total', usd(total), bold: true),
            if (local != null) Align(alignment: Alignment.centerRight, child: Text('≈ $sym${NumberFormatter.compact(local)}', style: KT.small)),
          ])),
          const SectionLabel('How your money is protected'),
          KtCard(color: KT.mint, child: Column(children: [
            _Step(Icons.lock_rounded, 'Today', 'Your ${usd(total)} goes into escrow. The supplier can\'t touch it yet.'),
            _Step(Icons.handshake_rounded, 'Supplier accepts', '${usd(deposit)} (30%) is released so they can start production.'),
            _Step(Icons.fact_check_rounded, 'After inspection', 'The remaining ${usd(subtotal - deposit)} is released only if your goods pass.'),
            _Step(Icons.replay_rounded, 'If it goes wrong', 'Missed deadline or failed inspection? The locked balance comes back to you.', last: true),
          ])),
          const SectionLabel('Pay with'),
          if (country == 'NG') ...[
            _Method(selected: method == 'wallet', icon: Icons.account_balance_wallet_rounded, title: 'Naira wallet',
                sub: wallet == null ? 'Loading balance…' : 'Balance ${ngn(nairaBal)}${nairaOk ? ' · instant' : ' · add money to use'}',
                enabled: nairaOk, onTap: () => setState(() => method = 'wallet')),
            const SizedBox(height: 10),
          ],
          _Method(selected: method == 'card', icon: Icons.credit_card_rounded, title: country == 'GH' ? 'Card or Mobile Money' : 'Card, bank transfer or USSD',
              sub: local == null ? 'Powered by Paystack' : 'Pay about $sym${NumberFormatter.compact(local)} · Paystack', onTap: () => setState(() => method = 'card')),
          const SizedBox(height: 10),
          _Method(selected: method == 'usdc', icon: Icons.currency_exchange_rounded, title: 'USDC wallet',
              sub: wallet == null ? 'Loading balance…' : (wallet.s('address').isEmpty ? 'Set up your wallet in the Wallet tab' : 'Balance ${usdStr(wallet.s('usdc'))}${usdcOk ? '' : ' · not enough'}'),
              enabled: wallet != null && wallet.s('address').isNotEmpty && usdcOk, onTap: () => setState(() => method = 'usdc')),
          const SizedBox(height: 26),
          KtButton(method == 'card' ? 'Place order & pay' : method == 'wallet' ? 'Pay ${ngn(nairaNeed)} from wallet' : 'Pay ${usd(total + 10)} in USDC', kind: BtnKind.orange, loading: busy, onPressed: _place),
          const SizedBox(height: 10),
          Center(child: Text(method == 'usdc' ? 'Includes about \$0.10 network fee.' : method == 'wallet' ? 'Paid instantly. Refunds come back to this wallet.' : 'You\'ll finish payment securely on Paystack.', style: KT.small)),
        ])),
      ),
    );
  }
}

class NumberFormatter {
  static String compact(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

class _Row extends StatelessWidget {
  final String a;
  final String b;
  final bool bold;
  const _Row(this.a, this.b, {this.bold = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(color: bold ? KT.ink : KT.grey, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 15))),
          Text(b, style: TextStyle(fontWeight: FontWeight.w800, fontSize: bold ? 20 : 15)),
        ]),
      );
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final bool last;
  const _Step(this.icon, this.title, this.body, {this.last = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: last ? 0 : 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 34, height: 34, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: Icon(icon, size: 18, color: KT.green)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(body, style: KT.body.copyWith(fontSize: 13.5, color: KT.ink.withOpacity(.7))),
          ])),
        ]),
      );
}

class _Method extends StatelessWidget {
  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _Method({required this.selected, required this.icon, required this.title, required this.sub, required this.onTap, this.enabled = true});
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.white, borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20), onTap: enabled ? onTap : null,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: selected ? KT.ink : KT.line, width: selected ? 2 : 1)),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: KT.peach, borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: KT.orange)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: KT.h3), Text(sub, style: KT.small)])),
                Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? KT.ink : KT.grey2),
              ]),
            ),
          ),
        ),
      );
}
