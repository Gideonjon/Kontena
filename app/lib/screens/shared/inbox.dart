import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';

final inboxProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => Api.i.get('/inbox'));

/// Unread messages across order chats and enquiries, for the tab badge. Checks again every 20 seconds.
final unreadProvider = StreamProvider.autoDispose<int>((ref) async* {
  while (true) {
    try {
      yield (await Api.i.get('/inbox/unread')).i('unread');
    } catch (_) {}
    await Future<void>.delayed(const Duration(seconds: 20));
  }
});

String _ago(int epoch) {
  final t = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  final n = DateTime.now();
  if (t.year == n.year && t.month == n.month && t.day == n.day) return DateFormat('h:mm a').format(t);
  if (n.difference(t).inDays < 7) return DateFormat('EEE').format(t);
  return DateFormat('d MMM').format(t);
}

/// The Messages tab: every chat in one list, order chats and enquiries to suppliers.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});
  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(inboxProvider);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _open(Map<String, dynamic> t) async {
    await context.push('/chat/${t.s('kind')}/${t.s('id')}');
    if (!mounted) return;
    ref.invalidate(inboxProvider);
    ref.invalidate(unreadProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(inboxProvider);
    final vendor = ref.watch(modeProvider) == 'vendor';
    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(inboxProvider.future),
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        PageHeader('Messages', subtitle: vendor ? 'Customers and orders' : 'Suppliers and orders'),
        async.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(inboxProvider)),
          data: (d) {
            final threads = d.list('threads');
            if (threads.isEmpty) {
              return EmptyState(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'No messages yet',
                body: vendor
                    ? 'When customers ask about your products, or message you about an order, the chat shows up here.'
                    : 'Open any supplier\'s store and tap Message to ask about products, prices and delivery. Order chats show up here too.',
                action: vendor ? null : KtButton('Find suppliers', expand: false, onPressed: () => context.go('/c/explore')),
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(children: [for (final t in threads) Padding(padding: const EdgeInsets.only(bottom: 10), child: _Row(t, onTap: () => _open(t)))]),
            );
          },
        ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> t;
  final VoidCallback onTap;
  const _Row(this.t, {required this.onTap});
  @override
  Widget build(BuildContext context) {
    final unread = t.i('unread');
    final weight = unread > 0 ? FontWeight.w900 : FontWeight.w700;
    return KtCard(
      onTap: onTap,
      child: Row(children: [
        FaceAvatar(t.s('title'), size: 48, imageKey: t.s('logoKey').isEmpty ? null : t.s('logoKey')),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(t.s('title'), maxLines: 1, overflow: TextOverflow.ellipsis, style: KT.h3)),
            const SizedBox(width: 8),
            Pill(t.s('subtitle')),
          ]),
          const SizedBox(height: 4),
          Text('${t.b('mine') ? 'You: ' : ''}${t.s('preview')}', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: unread > 0 ? KT.ink : KT.grey, fontWeight: weight, fontSize: 14)),
        ])),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(_ago(t.i('at')), style: KT.small),
          const SizedBox(height: 6),
          if (unread > 0)
            Container(
              constraints: const BoxConstraints(minWidth: 22), padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: KT.orange, borderRadius: BorderRadius.circular(99)),
              child: Text(unread > 99 ? '99+' : '$unread', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            )
          else
            const SizedBox(height: 22),
        ]),
      ]),
    );
  }
}
