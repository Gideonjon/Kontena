import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import 'admin_data.dart';

class AdminInspectionsScreen extends ConsumerStatefulWidget {
  const AdminInspectionsScreen({super.key});
  @override
  ConsumerState<AdminInspectionsScreen> createState() => _S();
}

class _S extends ConsumerState<AdminInspectionsScreen> {
  String? busy;

  Future<void> _decide(Map<String, dynamic> o, bool pass) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pass ? 'Pass inspection?' : 'Fail inspection?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(pass
              ? '${usd(o.i('balance_cents'))} will be released to the supplier. This cannot be undone.'
              : 'The buyer is refunded ${usd(o.i('balance_cents'))} and the order is closed. This cannot be undone.'),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(hintText: 'Note (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(pass ? 'Release funds' : 'Refund buyer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = o.s('id'));
    try {
      await Api.i.post('/orders/${o.s('id')}/inspection', {'pass': pass, 'note': note.text.trim()});
      ref.invalidate(adminInspectionsProvider);
      ref.invalidate(adminSummaryProvider);
      if (mounted) toast(context, pass ? 'Funds released' : 'Buyer refunded');
    } catch (e) {
      if (mounted) toast(context, e.toString());
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(adminInspectionsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminInspectionsProvider),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        const PageHeader('Inspections', subtitle: 'Goods waiting for a decision'),
        Constrain(
          child: q.when(
            loading: () => const Loading(),
            error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(adminInspectionsProvider)),
            data: (d) {
              final list = d.list('orders');
              if (list.isEmpty) {
                return const EmptyState(icon: Icons.fact_check_outlined, title: 'Nothing to inspect', body: 'Orders appear here once goods arrive for inspection.');
              }
              return Column(children: [
                for (final o in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: KtCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(o.s('ref'), style: KT.h3)),
                          Text(usd(o.i('balance_cents')), style: KT.h3),
                        ]),
                        const SizedBox(height: 4),
                        Text('${o.s('store_name')} → ${o.s('buyer_name')}', style: KT.body),
                        if (o.s('summary').isNotEmpty) Text(o.s('summary'), style: KT.small),
                        const SizedBox(height: 4),
                        Text('Balance held · ${dateShort(o.i('updated_at'))}', style: KT.small),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: KtButton('Fail', kind: BtnKind.danger, onPressed: busy == null ? () => _decide(o, false) : null)),
                          const SizedBox(width: 10),
                          Expanded(child: KtButton('Pass', loading: busy == o.s('id'), onPressed: busy == null ? () => _decide(o, true) : null)),
                        ]),
                        TextButton(onPressed: () => context.push('/order/${o.s('id')}'), child: const Text('View order')),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
