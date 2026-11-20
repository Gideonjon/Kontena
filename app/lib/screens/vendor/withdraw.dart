import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import '../customer/checkout.dart';
import '../shared/wallet.dart';

class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key});
  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  final amount = TextEditingController();
  final address = TextEditingController();
  final memo = TextEditingController();
  String method = 'fiat';
  String? accountId;
  bool busy = false;

  Future<void> _submit(int availableCents) async {
    final usdAmt = double.tryParse(amount.text.trim()) ?? 0;
    if (usdAmt < 5) return toast(context, 'Minimum withdrawal is \$5.');
    if ((usdAmt * 100).round() > availableCents) return toast(context, 'That\'s more than your available balance.');
    if (method == 'fiat' && accountId == null) return toast(context, 'Choose where to send it.');
    if (method == 'usdc' && address.text.trim().isEmpty) return toast(context, 'Paste the Stellar address.');
    setState(() => busy = true);
    final r = await guarded(context, () => Api.i.post('/withdrawals', {
          'method': method, 'amountUsd': usdAmt,
          if (method == 'fiat') 'payoutAccountId': accountId,
          if (method == 'usdc') ...{'address': address.text.trim(), if (memo.text.trim().isNotEmpty) 'memo': memo.text.trim()},
        }));
    if (!mounted) return;
    setState(() => busy = false);
    if (r == null) return;
    ref.invalidate(walletProvider);
    toast(context, r.s('status') == 'completed' ? 'Sent.' : 'On its way. We\'ll notify you when it lands.');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(walletProvider).valueOrNull ?? {};
    final available = w.m('earnings').i('availableCents');
    final accounts = w.list('accounts');
    final fx = ref.watch(fxProvider).valueOrNull;
    final country = ref.watch(meProvider).valueOrNull?.m('user').s('country', 'NG') ?? 'NG';
    final usdAmt = double.tryParse(amount.text.trim()) ?? 0;
    final rate = fx == null ? null : (country == 'GH' ? fx['USD_GHS'] : fx['USD_NGN']) as num;
    final local = rate == null ? null : usdAmt * rate * 0.985;
    final sym = country == 'GH' ? '₵' : '₦';

    return Scaffold(
      appBar: AppBar(title: const Text('Withdraw')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        child: Constrain(max: 520, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          KtCard(color: KT.ink, child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Available', style: TextStyle(color: Color(0xFF9A9DA5), fontWeight: FontWeight.w700)),
              Text(usd(available), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
            ])),
            KtButton('Max', expand: false, kind: BtnKind.orange, onPressed: () => setState(() => amount.text = (available / 100).toStringAsFixed(2))),
          ])),
          const SizedBox(height: 18),
          KtField(amount, 'Amount (USD)', prefix: '\$ ', keyboard: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {})),
          if (method == 'fiat' && local != null && usdAmt > 0) Padding(padding: const EdgeInsets.only(bottom: 14, left: 4), child: Text('You\'ll receive about $sym${NumberFormatter.compact(local)}', style: const TextStyle(fontWeight: FontWeight.w800, color: KT.green))),
          Row(children: [
            Expanded(child: _Seg('Bank / Mobile Money', method == 'fiat', () => setState(() => method = 'fiat'))),
            const SizedBox(width: 8),
            Expanded(child: _Seg('USDC address', method == 'usdc', () => setState(() => method = 'usdc'))),
          ]),
          const SizedBox(height: 18),
          if (method == 'fiat') ...[
            Text('SEND TO', style: KT.label), const SizedBox(height: 10),
            for (final a in accounts) Padding(padding: const EdgeInsets.only(bottom: 10), child: KtCard(
              onTap: () => setState(() => accountId = a.s('id')),
              child: Row(children: [
                Container(width: 42, height: 42, decoration: BoxDecoration(color: KT.peach, borderRadius: BorderRadius.circular(14)), child: Icon(a.s('kind') == 'momo' ? Icons.phone_android_rounded : Icons.account_balance_rounded, color: KT.orange)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.s('account_name'), style: KT.h3), Text('${a.s('bank_name')} · ${a.s('account_number')}', style: KT.small)])),
                Icon(accountId == a.s('id') ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: accountId == a.s('id') ? KT.ink : KT.grey2),
              ]),
            )),
            KtButton('Add bank or Mobile Money', icon: Icons.add_rounded, kind: BtnKind.ghost, onPressed: () => _addAccount(country)),
          ] else ...[
            KtField(address, 'Stellar address', hint: 'G…'),
            KtField(memo, 'Memo (only if the receiver asks for one)'),
            Text('Make sure the receiving wallet supports USDC on Stellar.', style: KT.small),
          ],
          const SizedBox(height: 26),
          KtButton('Withdraw', kind: BtnKind.orange, loading: busy, onPressed: () => _submit(available)),
        ])),
      ),
    );
  }

  void _addAccount(String country) {
    String kind = 'bank';
    Map<String, String>? bank;
    List<Map<String, String>> banks = [];
    var loading = true;
    String? err;
    final number = TextEditingController();
    final accName = TextEditingController();
    var saving = false;
    var started = false;

    Future<void> loadBanks(StateSetter set) async {
      set(() { loading = true; err = null; });
      try {
        final r = await Api.i.get('/banks', q: {'country': country, if (kind == 'momo') 'type': 'momo'});
        banks = r.list('banks').map((b) => {'name': b.s('name'), 'code': b.s('code')}).toList();
        bank = null;
      } on ApiException catch (e) {
        err = e.message;
      }
      set(() => loading = false);
    }

    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      if (!started) {
        started = true;
        Future.microtask(() => loadBanks(set));
      }
      return Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Add payout account', style: KT.h2), const SizedBox(height: 14),
          if (country == 'GH') Padding(padding: const EdgeInsets.only(bottom: 14), child: Row(children: [
            Expanded(child: _Seg('Bank', kind == 'bank', () { kind = 'bank'; banks = []; loadBanks(set); })),
            const SizedBox(width: 8),
            Expanded(child: _Seg('Mobile Money', kind == 'momo', () { kind = 'momo'; banks = []; loadBanks(set); })),
          ])),
          if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: KT.orange)))
          else if (err != null) Text(err!, style: const TextStyle(color: KT.red, fontWeight: FontWeight.w700))
          else DropdownButtonFormField<Map<String, String>>(
            isExpanded: true, value: bank, decoration: InputDecoration(labelText: kind == 'momo' ? 'Network' : 'Bank'),
            items: [for (final b in banks) DropdownMenuItem(value: b, child: Text(b['name']!, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => set(() => bank = v),
          ),
          const SizedBox(height: 14),
          KtField(number, kind == 'momo' ? 'Mobile Money number' : 'Account number', keyboard: TextInputType.number),
          if (kind == 'momo' || country == 'GH') KtField(accName, 'Account name'),
          KtButton('Save account', loading: saving, onPressed: () async {
            if (bank == null || number.text.trim().isEmpty) { toast(ctx, 'Choose a bank and enter the number.'); return; }
            set(() => saving = true);
            final r = await guarded(ctx, () => Api.i.post('/payout-accounts', {
                  'kind': kind, 'bankCode': bank!['code'], 'bankName': bank!['name'], 'accountNumber': number.text.trim(),
                  if (accName.text.trim().isNotEmpty) 'accountName': accName.text.trim(),
                }));
            set(() => saving = false);
            if (r != null && ctx.mounted) {
              Navigator.pop(ctx);
              ref.invalidate(walletProvider);
              setState(() => accountId = r.s('id'));
              toast(context, 'Saved: ${r.s('accountName')}');
            }
          }),
        ])),
      );
    }));
  }
}

class _Seg extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback tap;
  const _Seg(this.label, this.on, this.tap);
  @override
  Widget build(BuildContext context) => Material(
        color: on ? KT.ink : Colors.white, borderRadius: BorderRadius.circular(14),
        child: InkWell(borderRadius: BorderRadius.circular(14), onTap: tap, child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: on ? Colors.white : KT.ink))))),
      );
}
