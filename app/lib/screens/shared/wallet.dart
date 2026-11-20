import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';

final walletProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (ref.watch(authStateProvider).valueOrNull == null) return {};
  return Api.i.get('/wallet');
});

class WalletScreen extends ConsumerWidget {
  final bool vendor;
  const WalletScreen({super.key, this.vendor = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(walletProvider);
    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(walletProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        PageHeader(vendor ? 'Earnings & wallet' : 'Your wallet', subtitle: 'Wallet'),
        async.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(walletProvider)),
          data: (w) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (vendor) _Earnings(w),
            _UsdcCard(w),
            if (vendor && w.list('withdrawals').isNotEmpty) ...[
              const SectionLabel('Withdrawals'),
              KtCard(child: Column(children: [for (final x in w.list('withdrawals')) _WithdrawalRow(x)])),
            ],
            const SectionLabel('Good to know'),
            KtCard(color: KT.sky, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Tip(Icons.currency_exchange_rounded, 'Your wallet holds USDC, a digital dollar. Use it to pay for orders without card fees.'),
              const SizedBox(height: 12),
              _Tip(Icons.south_west_rounded, 'To add money, send USDC on the Stellar network to your address. Other networks will be lost.'),
              if (vendor) ...[const SizedBox(height: 12), _Tip(Icons.account_balance_rounded, 'Withdraw your earnings to a bank account, Mobile Money or any Stellar address.')],
            ])),
          ]),
        ),
      ]),
    );
  }
}

class _Earnings extends StatelessWidget {
  final Map<String, dynamic> w;
  const _Earnings(this.w);
  @override
  Widget build(BuildContext context) {
    final e = w.m('earnings');
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: KtCard(color: KT.ink, padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('AVAILABLE TO WITHDRAW', style: TextStyle(color: Color(0xFF9A9DA5), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        const SizedBox(height: 8),
        Text(usd(e.i('availableCents')), style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w800, letterSpacing: -2)),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.lock_rounded, size: 15, color: Color(0xFF9A9DA5)), const SizedBox(width: 6),
          Text('${usd(e.i('lockedCents'))} locked until inspection', style: const TextStyle(color: Color(0xFF9A9DA5), fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 18),
        KtButton('Withdraw', kind: BtnKind.orange, onPressed: e.i('availableCents') >= 500 ? () => context.push('/v/withdraw') : null),
      ])),
    );
  }
}

class _UsdcCard extends ConsumerWidget {
  final Map<String, dynamic> w;
  const _UsdcCard(this.w);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final has = w.s('address').isNotEmpty;
    return KtCard(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: KT.sky, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.currency_exchange_rounded, color: Color(0xFF2F6BFF))),
        const SizedBox(width: 12),
        Expanded(child: Text('USDC wallet', style: KT.h3)),
        const Pill('Stellar', bg: KT.paper),
      ]),
      const SizedBox(height: 14),
      if (!has) ...[
        Text('Hold digital dollars to pay suppliers faster and cheaper. Setting up takes under a minute.', style: KT.body),
        const SizedBox(height: 16),
        KtButton('Set up wallet', onPressed: () => _setup(context, ref)),
      ] else ...[
        Text(usdStr(w.s('usdc', '0')), style: KT.h1.copyWith(fontSize: 36)),
        const SizedBox(height: 4),
        Text('${w.s('xlm', '0')} XLM for network fees', style: KT.small),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: KtButton('Receive', icon: Icons.qr_code_rounded, kind: BtnKind.soft, onPressed: () => _receive(context, w.s('address')))),
        ]),
      ],
    ]));
  }

  void _receive(BuildContext context, String address) {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Receive USDC', style: KT.h2), const SizedBox(height: 4),
        Text('Send USDC on the Stellar network only.', style: KT.body),
        const SizedBox(height: 18),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), border: Border.all(color: KT.line)),
            child: QrImageView(data: address, size: 190)),
        const SizedBox(height: 14),
        SelectableText(address, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.4)),
        const SizedBox(height: 14),
        KtButton('Copy address', icon: Icons.copy_rounded, onPressed: () { Clipboard.setData(ClipboardData(text: address)); toast(ctx, 'Address copied'); }),
      ]),
    ));
  }

  void _setup(BuildContext context, WidgetRef ref) {
    final me = ref.read(meProvider).valueOrNull?.m('user') ?? {};
    final phone = TextEditingController(text: me.s('phone'));
    final dob = TextEditingController();
    final addr = TextEditingController();
    final city = TextEditingController();
    var busy = false;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Set up your wallet', style: KT.h2), const SizedBox(height: 6),
        Text('We need a few details to verify you. They are used only to create your wallet.', style: KT.body), const SizedBox(height: 16),
        KtField(phone, 'Phone number', keyboard: TextInputType.phone, hint: '+234…'),
        KtField(dob, 'Date of birth', hint: 'YYYY-MM-DD', keyboard: TextInputType.datetime),
        KtField(addr, 'Street address'),
        KtField(city, 'City'),
        KtButton('Create wallet', loading: busy, onPressed: () async {
          set(() => busy = true);
          final r = await guarded(ctx, () async {
            await Api.i.patch('/me', {'phone': phone.text.trim(), 'dob': dob.text.trim(), 'address': addr.text.trim(), 'city': city.text.trim()});
            return Api.i.post('/wallet');
          });
          set(() => busy = false);
          if (r != null && ctx.mounted) {
            Navigator.pop(ctx);
            ref.invalidate(walletProvider);
            ref.invalidate(meProvider);
            toast(context, 'Wallet ready');
          }
        }),
      ])),
    )));
  }
}

class _WithdrawalRow extends StatelessWidget {
  final Map<String, dynamic> x;
  const _WithdrawalRow(this.x);
  @override
  Widget build(BuildContext context) {
    final st = x.s('status');
    final (bg, fg) = switch (st) { 'completed' => (KT.mint, KT.green), 'failed' => (const Color(0xFFFDECEA), KT.red), _ => (KT.butter, const Color(0xFF8A6A00)) };
    final label = x.s('method') == 'usdc' ? 'To Stellar address' : x.s('method') == 'momo' ? 'To Mobile Money' : 'To bank account';
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)), Text(dateShort(x.i('created_at')), style: KT.small),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(usd(x.i('amount_cents')), style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(height: 4), Pill(st == 'pending' ? 'Queued' : st[0].toUpperCase() + st.substring(1), bg: bg, fg: fg)]),
    ]));
  }
}

class _Tip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Tip(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 19, color: const Color(0xFF2F6BFF)), const SizedBox(width: 12), Expanded(child: Text(text, style: KT.body.copyWith(fontSize: 13.5, color: KT.ink.withOpacity(.75)))),
      ]);
}
