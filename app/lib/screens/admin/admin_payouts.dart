import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import 'admin_data.dart';

class AdminPayoutsScreen extends ConsumerStatefulWidget {
  const AdminPayoutsScreen({super.key});
  @override
  ConsumerState<AdminPayoutsScreen> createState() => _S();
}

class _S extends ConsumerState<AdminPayoutsScreen> {
  String tab = 'pending';
  String? busy;

  Future<void> _act(Map<String, dynamic> w, bool done) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(done ? 'Mark as paid?' : 'Reject payout?'),
        content: Text(done
            ? 'Confirm you have sent the money to ${w.s('account_name').isEmpty ? w.s('user_name') : w.s('account_name')}.'
            : 'The USDC goes back to the supplier\'s wallet and the FX spread is reversed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(done ? 'Mark paid' : 'Reject')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = w.s('id'));
    try {
      await Api.i.post('/admin/withdrawals/${w.s('id')}/${done ? 'complete' : 'fail'}', done ? {} : {'note': 'Rejected by Kontena'});
      ref.invalidate(adminWithdrawalsProvider(tab));
      ref.invalidate(adminSummaryProvider);
      if (mounted) toast(context, done ? 'Marked as paid' : 'Payout rejected');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminWithdrawalsProvider(tab));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminWithdrawalsProvider(tab)),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        const PageHeader('Payouts', subtitle: 'Supplier withdrawals'),
        Constrain(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final t in const ['pending', 'processing', 'completed', 'failed'])
                ChoiceChip(label: Text(t[0].toUpperCase() + t.substring(1)), selected: tab == t, onSelected: (_) => setState(() => tab = t)),
            ]),
            const SizedBox(height: 14),
            q.when(
              loading: () => const Loading(),
              error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(adminWithdrawalsProvider(tab))),
              data: (d) {
                final list = d.list('withdrawals');
                if (list.isEmpty) return EmptyState(icon: Icons.payments_outlined, title: 'No $tab payouts', body: 'Nothing here right now.');
                return Column(children: [
                  for (final w in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: KtCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(w.s('user_name'), style: KT.h3)),
                            Text(usd(w.i('amount_cents')), style: KT.h3),
                          ]),
                          const SizedBox(height: 4),
                          Text('${w.s('fiat_currency')} ${(w.i('fiat_minor') / 100).toStringAsFixed(2)} via ${w.s('method')}', style: KT.body),
                          if (w.s('account_number').isNotEmpty)
                            SelectableText('${w.s('bank_name')} · ${w.s('account_number')} · ${w.s('account_name')}', style: KT.small),
                          if (w.s('error').isNotEmpty) Text(w.s('error'), style: KT.small.copyWith(color: KT.red)),
                          Text(dateShort(w.i('created_at')), style: KT.small),
                          if (tab == 'pending' || tab == 'processing') ...[
                            const SizedBox(height: 12),
                            Row(children: [
                              Expanded(child: KtButton('Reject', kind: BtnKind.danger, onPressed: busy == null ? () => _act(w, false) : null)),
                              const SizedBox(width: 10),
                              Expanded(child: KtButton('Mark paid', loading: busy == w.s('id'), onPressed: busy == null ? () => _act(w, true) : null)),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                ]);
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
