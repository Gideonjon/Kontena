import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';
import 'admin_data.dart';

class AdminStoresScreen extends ConsumerWidget {
  const AdminStoresScreen({super.key});

  Future<void> _set(BuildContext context, WidgetRef ref, Map<String, dynamic> s, String what, bool v) async {
    try {
      await Api.i.post('/admin/stores/${s.s('id')}/$what', {what == 'verify' ? 'verified' : 'active': v});
      ref.invalidate(adminStoresProvider);
    } catch (e) {
      if (context.mounted) toast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(adminStoresProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(adminStoresProvider),
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        const PageHeader('Stores', subtitle: 'Verify and moderate suppliers'),
        Constrain(
          child: q.when(
            loading: () => const Loading(),
            error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(adminStoresProvider)),
            data: (d) {
              final list = d.list('stores');
              if (list.isEmpty) return const EmptyState(icon: Icons.storefront_outlined, title: 'No stores yet', body: 'Stores appear here when suppliers sign up.');
              return Column(children: [
                for (final s in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: KtCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          FaceAvatar(s.s('name'), size: 44),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.s('name'), style: KT.h3),
                            Text('${s.s('email')} · ${s.s('country')} · ${s.i('orders')} orders', style: KT.small),
                          ])),
                          if (s.b('verified')) const Pill('Verified', bg: KT.mint, fg: KT.green),
                        ]),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, dense: true, title: const Text('Verified badge'),
                          value: s.b('verified'), onChanged: (v) => _set(context, ref, s, 'verify', v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero, dense: true, title: const Text('Store is live'),
                          value: s.b('active'), onChanged: (v) => _set(context, ref, s, 'active', v),
                        ),
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
