import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/media.dart';
import '../../widgets/ui.dart';

final messagesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) async => (await Api.i.get('/orders/$id/messages')).list('messages'));

/// Chat for one order between the buyer, the supplier and Kontena's inspector. Photos and videos can be attached.
class OrderChat extends ConsumerStatefulWidget {
  final String orderId;
  const OrderChat({super.key, required this.orderId});
  @override
  ConsumerState<OrderChat> createState() => _OrderChatState();
}

class _OrderChatState extends ConsumerState<OrderChat> {
  final _c = TextEditingController();
  Timer? _t;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted) ref.invalidate(messagesProvider(widget.orderId));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _send({String? mediaKey}) async {
    final text = _c.text.trim();
    if (text.isEmpty && mediaKey == null) return;
    setState(() => sending = true);
    final r = await guarded(context, () => Api.i.post('/orders/${widget.orderId}/messages', {'body': text, if (mediaKey != null) 'mediaKey': mediaKey}));
    if (!mounted) return;
    setState(() => sending = false);
    if (r != null) {
      _c.clear();
      ref.invalidate(messagesProvider(widget.orderId));
    }
  }

  Future<void> _attach(bool video) async {
    String? k;
    if (video) {
      k = await pickAndUploadVideo(context);
    } else {
      final ks = await pickAndUploadImages(context);
      k = ks.isEmpty ? null : ks.first;
    }
    if (k != null && mounted) await _send(mediaKey: k);
  }

  @override
  Widget build(BuildContext context) {
    final msgs = ref.watch(messagesProvider(widget.orderId)).valueOrNull ?? const <Map<String, dynamic>>[];
    final shown = msgs.length > 20 ? msgs.sublist(msgs.length - 20) : msgs;
    return KtCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (shown.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text('No messages yet. Ask a question or share an update about this order.', style: KT.small)),
      for (final m in shown) _Bubble(m),
      Row(children: [
        IconButton(onPressed: sending ? null : () => _attach(false), icon: const Icon(Icons.photo_camera_rounded), tooltip: 'Send a photo'),
        IconButton(onPressed: sending ? null : () => _attach(true), icon: const Icon(Icons.videocam_rounded), tooltip: 'Send a video'),
        Expanded(child: TextField(
          controller: _c, minLines: 1, maxLines: 4,
          decoration: const InputDecoration(hintText: 'Write a message', border: InputBorder.none, isDense: true),
        )),
        IconButton(onPressed: sending ? null : () => _send(), icon: const Icon(Icons.send_rounded, color: KT.orange), tooltip: 'Send'),
      ]),
    ]));
  }
}

class _Bubble extends StatelessWidget {
  final Map<String, dynamic> m;
  const _Bubble(this.m);
  @override
  Widget build(BuildContext context) {
    final mine = m.b('mine');
    final who = mine ? 'You' : switch (m.s('role')) { 'supplier' => 'Supplier', 'kontena' => 'Kontena', _ => 'Buyer' };
    final key = m.s('mediaKey');
    final text = mine ? Colors.white : KT.ink;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(color: mine ? KT.ink : KT.paper, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mine ? KT.orange : KT.grey)),
          if (key.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: m.b('isVideo')
              ? InkWell(
                  onTap: () => launchUrl(Uri.parse(Api.mediaUrl(key)), mode: LaunchMode.externalApplication),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.play_circle_fill_rounded, color: text, size: 30), const SizedBox(width: 8),
                    Text('Play video', style: TextStyle(color: text, fontWeight: FontWeight.w700)),
                  ]))
              : GestureDetector(
                  onTap: () => showDialog(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(Api.mediaUrl(key))))),
                  child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(Api.mediaUrl(key), width: 200, fit: BoxFit.cover)))),
          if (m.s('body').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(m.s('body'), style: TextStyle(color: text, height: 1.35))),
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(dateShort(m.i('at')), style: TextStyle(fontSize: 11, color: mine ? const Color(0xFFA9ABB2) : KT.grey))),
        ]),
      ),
    );
  }
}
