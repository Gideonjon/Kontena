import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import 'admin_data.dart';

const _revenueLabels = {
  'protection_fee': 'Buyer protection fees',
  'seller_commission': 'Seller commission',
  'withdrawal_spread': 'Withdrawal FX spread',
  'withdrawal_spread_reversal': 'Spread reversed (failed payouts)',
};

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(adminSummaryProvider);
    final issues = ref.watch(adminRefundIssuesProvider).valueOrNull?.list('issues') ?? const [];
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(adminSummaryProvider);
        ref.invalidate(adminRefundIssuesProvider);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        const PageHeader('Overview', subtitle: 'Kontena admin'),
        Constrain(
          child: s.when(
            loading: () => const Loading(),
            error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(adminSummaryProvider)),
            data: (d) {
              final rev = d.m('revenue');
              final kinds = rev.m('byKind');
              final orders = d.m('orders');
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                KtCard(
                  color: KT.ink,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PLATFORM REVENUE', style: KT.label.copyWith(color: Colors.white70)),
                    const SizedBox(height: 8),
                    Text(usd(rev.i('totalCents')), style: KT.h1.copyWith(color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('${usd(rev.i('last30Cents'))} in the last 30 days', style: KT.small.copyWith(color: Colors.white70)),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Stat('Volume (GMV)', usd(d.i('gmvCents')), KT.sky)),
                  const SizedBox(width: 12),
                  Expanded(child: _Stat('Held in escrow', usd(d.i('escrowHeldCents')), KT.butter)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _Stat('Owed to suppliers', usd(d.i('owedToSuppliersCents')), KT.mint)),
                  const SizedBox(width: 12),
                  Expanded(child: _Stat('Payouts waiting', '${d.i('pendingWithdrawals')}', KT.peach)),
                ]),
                const SectionLabel('Revenue by source'),
                KtCard(
                  child: Column(children: [
                    if (kinds.isEmpty) Text('No revenue yet. It appears once suppliers accept orders.', style: KT.body),
                    for (final e in kinds.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(child: Text(_revenueLabels[e.key] ?? e.key, style: KT.body.copyWith(color: KT.ink))),
                          Text(usd((e.value as num).toInt()), style: KT.h3),
                        ]),
                      ),
                  ]),
                ),
                const SectionLabel('Orders'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in orders.entries) Row(mainAxisSize: MainAxisSize.min, children: [StatusPill(e.key), const SizedBox(width: 6), Text('${e.value}', style: KT.h3)]),
                  if (orders.isEmpty) Text('No orders yet.', style: KT.body),
                ]),
                const SectionLabel('Platform'),
                KtCard(child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${d.i('users')}', style: KT.h2), Text('Users', style: KT.small)])),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${d.i('stores')}', style: KT.h2), Text('Stores', style: KT.small)])),
                ])),
                if (issues.isNotEmpty) ...[
                  SectionLabel('Refunds that need attention (${issues.length})'),
                  for (final i in issues)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: KtCard(
                        color: const Color(0xFFFDECEA),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${i.s('ref')} · ${usd(i.i('total_cents'))}', style: KT.h3),
                          const SizedBox(height: 4),
                          Text('Paid by ${i.s('funding')}. ${i.s('note')}', style: KT.body),
                        ]),
                      ),
                    ),
                ],
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color bg;
  const _Stat(this.label, this.value, this.bg);
  @override
  Widget build(BuildContext context) => KtCard(
        color: bg,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: KT.small),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: KT.h2)),
        ]),
      );
}
