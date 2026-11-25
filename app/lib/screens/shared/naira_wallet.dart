import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';
import 'wallet.dart';

/// The Naira wallet: balance, personal account number, add money, withdraw, history, refund preference.
class NairaWalletCard extends ConsumerWidget {
  final Map<String, dynamic> w;
  const NairaWalletCard(this.w, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = w.m('naira');
    final account = n.m('account');
    final active = account.s('status') == 'active';
    final pending = account.s('status') == 'pending';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      KtCard(color: KT.ink, padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('NAIRA WALLET', style: TextStyle(color: Color(0xFF9A9DA5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          const Spacer(),
          const Pill('NGN', bg: Color(0xFF26272C), fg: Colors.white),
        ]),
        const SizedBox(height: 8),
        Text(ngn(n.i('balanceKobo')), style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.8)),
        const SizedBox(height: 4),
        const Text('Pay for orders instantly. Refunds land here.', style: TextStyle(color: Color(0xFF9A9DA5), fontWeight: FontWeight.w600)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: KtButton('Add money', icon: Icons.add_rounded, kind: BtnKind.orange, onPressed: () => _addMoney(context, ref))),
          const SizedBox(width: 10),
          Expanded(child: KtButton('Withdraw', icon: Icons.north_east_rounded, kind: BtnKind.ghost, onPressed: n.i('balanceKobo') >= 10000 ? () => _withdraw(context, ref, w.list('accounts').where((a) => a.s('currency') == 'NGN' && a.s('kind') == 'bank').toList(), n.i('balanceKobo')) : null)),
        ]),
      ])),
      const SizedBox(height: 12),
      KtCard(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: KT.mint, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.account_balance_rounded, color: KT.green)),
          const SizedBox(width: 12),
          Expanded(child: Text('Your Naira account number', style: KT.h3)),
        ]),
        const SizedBox(height: 12),
        if (active) ...[
          Row(children: [
            Expanded(child: SelectableText(account.s('account_number'), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 1.5))),
            IconButton(icon: const Icon(Icons.copy_rounded), onPressed: () { Clipboard.setData(ClipboardData(text: account.s('account_number'))); toast(context, 'Account number copied'); }),
          ]),
          Text('${account.s('bank_name')} · ${account.s('account_name')}', style: KT.small),
          const SizedBox(height: 6),
          Text('Transfer from any Nigerian bank app. It reaches your wallet within a minute.', style: KT.body.copyWith(fontSize: 13.5)),
        ] else if (pending) ...[
          Row(children: [
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: KT.orange)), const SizedBox(width: 12),
            Expanded(child: Text('Setting up your account number. This takes a few seconds.', style: KT.body)),
          ]),
          const SizedBox(height: 12),
          KtButton('Refresh', kind: BtnKind.soft, onPressed: () => ref.invalidate(walletProvider)),
        ] else ...[
          Text(account.s('status') == 'failed'
              ? 'We couldn\'t create your account number. Check your phone number in Profile and try again.'
              : 'Get a personal bank account number. Send money to it from any bank app and it shows up in your wallet.', style: KT.body),
          const SizedBox(height: 14),
          KtButton('Get my account number', onPressed: () => _getAccount(context, ref)),
        ],
      ])),
      const SectionLabel('Naira activity'),
      _History(n.list('entries')),
      const SizedBox(height: 14),
      _RefundPref(),
    ]);
  }

  Future<void> _getAccount(BuildContext context, WidgetRef ref) async {
    final r = await guarded(context, () => Api.i.post('/naira/account'));
    if (r == null) return;
    ref.invalidate(walletProvider);
    if (context.mounted) toast(context, 'Creating your account number…');
  }

  void _addMoney(BuildContext context, WidgetRef ref) {
    final amt = TextEditingController();
    var busy = false;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Add money', style: KT.h2), const SizedBox(height: 6),
        Text('Pay with card, bank transfer or USSD on Paystack. Or send a transfer to your account number above.', style: KT.body),
        const SizedBox(height: 16),
        KtField(amt, 'Amount', prefix: '₦ ', keyboard: TextInputType.number, onChanged: (_) {}),
        Wrap(spacing: 8, children: [for (final v in [5000, 10000, 50000, 100000]) ActionChip(label: Text('₦${v ~/ 1000}k'), onPressed: () => amt.text = '$v')]),
        const SizedBox(height: 16),
        KtButton('Continue to Paystack', kind: BtnKind.orange, loading: busy, onPressed: () async {
          final v = double.tryParse(amt.text.trim()) ?? 0;
          if (v < 100) return toast(ctx, 'Minimum is ₦100');
          set(() => busy = true);
          final r = await guarded(ctx, () => Api.i.post('/naira/topup', {'amountNgn': v}));
          set(() => busy = false);
          if (r == null) return;
          if (ctx.mounted) Navigator.pop(ctx);
          await launchUrl(Uri.parse(r.s('url')), webOnlyWindowName: kIsWeb ? '_self' : null, mode: LaunchMode.externalApplication);
        }),
      ]),
    )));
  }

  void _withdraw(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> accounts, int balanceKobo) {
    final amt = TextEditingController();
    String? accountId = accounts.isEmpty ? null : accounts.first.s('id');
    var busy = false;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Withdraw to bank', style: KT.h2), const SizedBox(height: 6),
        Text('Available ${ngn(balanceKobo)}', style: KT.body), const SizedBox(height: 16),
        KtField(amt, 'Amount', prefix: '₦ ', keyboard: TextInputType.number),
        if (accounts.isEmpty) ...[
          Text('Add a Nigerian bank account first.', style: KT.body), const SizedBox(height: 12),
          KtButton('Add bank account', icon: Icons.add_rounded, kind: BtnKind.soft, onPressed: () async {
            final ok = await addNigerianBank(ctx);
            if (ok == true) { ref.invalidate(walletProvider); if (ctx.mounted) Navigator.pop(ctx); if (context.mounted) toast(context, 'Account saved. Tap Withdraw again.'); }
          }),
        ] else ...[
          for (final a in accounts) Padding(padding: const EdgeInsets.only(bottom: 8), child: KtCard(
            onTap: () => set(() => accountId = a.s('id')),
            child: Row(children: [
              const Icon(Icons.account_balance_rounded, color: KT.orange), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(a.s('account_name'), style: KT.h3), Text('${a.s('bank_name')} · ${a.s('account_number')}', style: KT.small)])),
              Icon(accountId == a.s('id') ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: accountId == a.s('id') ? KT.ink : KT.grey2),
            ]),
          )),
          const SizedBox(height: 8),
          KtButton('Withdraw', kind: BtnKind.orange, loading: busy, onPressed: () async {
            final v = double.tryParse(amt.text.trim()) ?? 0;
            if (v < 100) return toast(ctx, 'Minimum is ₦100');
            if ((v * 100).round() > balanceKobo) return toast(ctx, 'That\'s more than your balance');
            set(() => busy = true);
            final r = await guarded(ctx, () => Api.i.post('/naira/withdraw', {'amountNgn': v, 'payoutAccountId': accountId}));
            set(() => busy = false);
            if (r == null) return;
            ref.invalidate(walletProvider);
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) toast(context, 'On its way to your bank.');
          }),
        ],
      ])),
    )));
  }
}

/// Bottom sheet to save a Nigerian bank account. The server checks the account name with the bank. Returns true when saved.
Future<bool?> addNigerianBank(BuildContext context) {
  List<Map<String, String>> banks = [];
  Map<String, String>? bank;
  var loading = true, started = false, saving = false;
  String? err;
  final number = TextEditingController();
  return showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
    if (!started) {
      started = true;
      Future.microtask(() async {
        try {
          final r = await Api.i.get('/banks', q: {'country': 'NG'});
          banks = r.list('banks').map((b) => {'name': b.s('name'), 'code': b.s('code')}).toList();
        } on ApiException catch (e) { err = e.message; }
        set(() => loading = false);
      });
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Add bank account', style: KT.h2), const SizedBox(height: 14),
        if (loading) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: KT.orange)))
        else if (err != null) Text(err!, style: const TextStyle(color: KT.red, fontWeight: FontWeight.w700))
        else DropdownButtonFormField<Map<String, String>>(
          isExpanded: true, value: bank, decoration: const InputDecoration(labelText: 'Bank'),
          items: [for (final b in banks) DropdownMenuItem(value: b, child: Text(b['name']!, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => set(() => bank = v),
        ),
        const SizedBox(height: 14),
        KtField(number, 'Account number', keyboard: TextInputType.number),
        KtButton('Save account', loading: saving, onPressed: () async {
          if (bank == null || number.text.trim().length != 10) return toast(ctx, 'Pick your bank and enter the 10-digit account number');
          set(() => saving = true);
          final r = await guarded(ctx, () => Api.i.post('/payout-accounts', {'kind': 'bank', 'bankCode': bank!['code'], 'bankName': bank!['name'], 'accountNumber': number.text.trim()}));
          set(() => saving = false);
          if (r != null && ctx.mounted) { toast(ctx, 'Saved: ${r.s('accountName')}'); Navigator.pop(ctx, true); }
        }),
      ])),
    );
  }));
}

class _History extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _History(this.items);
  static const labels = {
    'topup': 'Added by card', 'transfer_in': 'Bank transfer in', 'order_payment': 'Paid for an order', 'refund': 'Refund',
    'withdrawal': 'Withdrawal to bank', 'withdrawal_reversal': 'Withdrawal returned',
  };
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return KtCard(child: Text('Nothing yet. Add money to get started.', style: KT.body));
    return KtCard(child: Column(children: [
      for (final x in items) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: x.i('amount_kobo') >= 0 ? KT.mint : KT.paper, shape: BoxShape.circle),
            child: Icon(x.i('amount_kobo') >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded, size: 17, color: x.i('amount_kobo') >= 0 ? KT.green : KT.ink)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(labels[x.s('kind')] ?? x.s('kind'), style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(x.s('note').isEmpty ? dateShort(x.i('created_at')) : '${x.s('note')} · ${dateShort(x.i('created_at'))}', style: KT.small, overflow: TextOverflow.ellipsis),
        ])),
        Text('${x.i('amount_kobo') >= 0 ? '+' : '−'}${ngn(x.i('amount_kobo').abs())}', style: TextStyle(fontWeight: FontWeight.w800, color: x.i('amount_kobo') >= 0 ? KT.green : KT.ink)),
      ])),
    ]));
  }
}

class _RefundPref extends ConsumerStatefulWidget {
  @override
  ConsumerState<_RefundPref> createState() => _RefundPrefState();
}

class _RefundPrefState extends ConsumerState<_RefundPref> {
  String? value;
  @override
  Widget build(BuildContext context) {
    final cur = value ?? ref.watch(walletProvider).valueOrNull?.m('naira').s('refundTo', 'wallet') ?? 'wallet';
    return KtCard(color: KT.sky, child: Row(children: [
      const Icon(Icons.replay_rounded, color: Color(0xFF2F6BFF)), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Send refunds to my wallet', style: TextStyle(fontWeight: FontWeight.w800)),
        Text(cur == 'wallet' ? 'Instant. Card payments are refunded into this wallet.' : 'Card payments are refunded to your card, which can take days.', style: KT.small),
      ])),
      Switch(value: cur == 'wallet', activeColor: KT.orange, onChanged: (on) async {
        final next = on ? 'wallet' : 'original';
        setState(() => value = next);
        final r = await guarded(context, () => Api.i.patch('/naira/refund-to', {'refundTo': next}));
        if (r == null) setState(() => value = on ? 'original' : 'wallet');
      }),
    ]));
  }
}
