import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

final notificationsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final r = await Api.i.get('/notifications');
  Api.i.post('/notifications/read').ignore();
  return r.list('notifications');
});

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: async.when(
        loading: () => const Loading(),
        error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(notificationsProvider)),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.notifications_none_rounded, title: 'All quiet', body: 'Payment, inspection and refund updates will show up here.')
            : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
                Constrain(child: Column(children: [
                  for (final n in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: KtCard(
                    onTap: n.s('order_id').isEmpty ? null : () => context.push('/order/${n.s('order_id')}'),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 6, right: 12), decoration: BoxDecoration(color: n.b('read') ? Colors.transparent : KT.orange, shape: BoxShape.circle)),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n.s('title'), style: KT.h3), const SizedBox(height: 2), Text(n.s('body'), style: KT.body.copyWith(fontSize: 14)), const SizedBox(height: 4), Text(dateShort(n.i('created_at')), style: KT.small),
                      ])),
                    ]),
                  )),
                ])),
              ]),
      ),
    );
  }
}
