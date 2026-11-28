import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/media.dart';
import '../../widgets/ui.dart';
import 'inbox.dart';
import 'order_chat.dart';
import 'order_detail.dart' show orderProvider;
import 'store_page.dart' show storeProvider;

/// key is "order/<orderId>" or "inquiry/<conversationId>"
final chatProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, key) async {
  final i = key.indexOf('/');
  final kind = key.substring(0, i), id = key.substring(i + 1);
  if (kind == 'order') return <String, dynamic>{'messages': (await Api.i.get('/orders/$id/messages')).list('messages')};
  return Api.i.get('/inbox/inquiries/$id');
});

const _quick = ['Can I get a price quote?', 'Please send photos and a video of the goods', 'How long will delivery take?'];

/// Full-screen chat. kind is 'order' (buyer, supplier and Kontena's inspector) or 'inquiry' (a customer asking a supplier
/// before ordering). From an enquiry either side can open the store to see the goods or share a product into the chat.
class ChatScreen extends ConsumerStatefulWidget {
  final String kind;
  final String id;
  final Map<String, dynamic>? product; // a product the customer tapped "Ask about this" on
  const ChatScreen({super.key, required this.kind, required this.id, this.product});
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _c = TextEditingController();
  Timer? _t;
  bool sending = false;
  bool _cleared = false;
  Map<String, dynamic>? _product;

  String get _key => '${widget.kind}/${widget.id}';
  bool get _isOrder => widget.kind == 'order';

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _t = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(chatProvider(_key));
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _send({String? mediaKey, String? productId}) async {
    final text = _c.text.trim();
    final pid = productId ?? _product?.s('id');
    if (text.isEmpty && mediaKey == null && pid == null) return;
    setState(() => sending = true);
    final r = await guarded(
      context,
      () => Api.i.post(_isOrder ? '/orders/${widget.id}/messages' : '/inbox/inquiries/${widget.id}/messages', {
        'body': text,
        if (mediaKey != null) 'mediaKey': mediaKey,
        if (!_isOrder && pid != null) 'productId': pid,
      }),
    );
    if (!mounted) return;
    setState(() => sending = false);
    if (r != null) {
      _c.clear();
      setState(() => _product = null);
      ref.invalidate(chatProvider(_key));
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

  void _shareProduct(String slug) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final async = ref.watch(storeProvider(slug));
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Share a product', style: KT.h2),
              const SizedBox(height: 4),
              Text('It appears in the chat as a card the other person can tap.', style: KT.small),
              const SizedBox(height: 10),
              async.when(
                loading: () => const Loading(),
                error: (e, _) => ErrorBox(e),
                data: (d) {
                  final ps = d.list('products');
                  if (ps.isEmpty) return Padding(padding: const EdgeInsets.all(16), child: Text('No products listed yet.', style: KT.body));
                  return ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 380),
                    child: ListView(shrinkWrap: true, children: [
                      for (final p in ps)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: p.s('image_key').isNotEmpty
                              ? Image.network(Api.mediaUrl(p.s('image_key')), width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph())
                              : _ph()),
                          title: Text(p.s('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: KT.h3),
                          subtitle: Text('${usdShort(p.i('price_cents'))} each · min ${p.i('min_qty')}', style: KT.small),
                          onTap: () {
                            Navigator.pop(ctx);
                            _send(productId: p.s('id'));
                          },
                        ),
                    ]),
                  );
                },
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _ph() => Container(width: 48, height: 48, color: KT.peach, child: const Icon(Icons.inventory_2_rounded, color: KT.orange, size: 22));

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider(_key));
    ref.listen(chatProvider(_key), (_, next) {
      if (!_cleared && next.hasValue) {
        _cleared = true; // the server marked this thread read, so the tab badge can drop
        ref.invalidate(unreadProvider);
      }
    });
    final data = chat.valueOrNull;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var title = 'Messages', subtitle = '', slug = '', logo = '';
    var iAmBuyer = true;
    if (_isOrder) {
      final o = ref.watch(orderProvider(widget.id)).valueOrNull;
      if (o != null) {
        final store = o.m('store');
        iAmBuyer = o.s('buyer_id') == uid;
        title = iAmBuyer ? store.s('name') : (o.s('buyerName').isEmpty ? 'Customer' : o.s('buyerName'));
        subtitle = 'Order ${o.s('ref')}';
        slug = store.s('slug');
        logo = iAmBuyer ? store.s('logo_key') : '';
      }
    } else if (data != null) {
      final cv = data.m('conversation');
      final store = cv.m('store');
      iAmBuyer = cv.b('iAmBuyer');
      title = iAmBuyer ? store.s('name') : (cv.s('buyerName').isEmpty ? 'Customer' : cv.s('buyerName'));
      subtitle = 'Enquiry';
      slug = store.s('slug');
      logo = iAmBuyer ? store.s('logo_key') : '';
    }
    final msgs = data == null ? const <Map<String, dynamic>>[] : data.list('messages');

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          FaceAvatar(title, size: 36, imageKey: logo.isEmpty ? null : logo),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: KT.h3),
            if (subtitle.isNotEmpty) Text(subtitle, style: KT.small),
          ])),
        ]),
        actions: [
          if (slug.isNotEmpty) IconButton(tooltip: 'See their goods', icon: const Icon(Icons.storefront_outlined), onPressed: () => context.push('/s/$slug')),
          if (_isOrder) IconButton(tooltip: 'View order', icon: const Icon(Icons.receipt_long_outlined), onPressed: () => context.push('/order/${widget.id}')),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(children: [
            Expanded(
              child: data == null
                  ? (chat.hasError ? ErrorBox(chat.error!, retry: () => ref.invalidate(chatProvider(_key))) : const Loading())
                  : msgs.isEmpty
                      ? _empty(iAmBuyer && !_isOrder)
                      : ListView(
                          reverse: true, padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          children: [for (final m in msgs.reversed) ChatBubble(m, slug: slug.isEmpty ? null : slug)],
                        ),
            ),
            _composer(slug),
          ]),
        ),
      ),
    );
  }

  Widget _empty(bool showQuick) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64, decoration: const BoxDecoration(color: KT.peach, shape: BoxShape.circle), child: const Icon(Icons.chat_bubble_outline_rounded, color: KT.orange, size: 28)),
            const SizedBox(height: 14),
            Text(showQuick ? 'Ask the supplier anything' : 'No messages yet', style: KT.h3),
            const SizedBox(height: 6),
            Text(showQuick ? 'Prices, minimum quantities, samples, delivery. You can also ask for photos and videos of the goods.' : 'Say hello, or share an update.', style: KT.body, textAlign: TextAlign.center),
            if (showQuick) ...[
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(q),
                    onPressed: () => setState(() => _c.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length))),
                  ),
              ]),
            ],
          ]),
        ),
      );

  Widget _composer(String slug) => Container(
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: KT.line))),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_product != null)
              Container(
                margin: const EdgeInsets.fromLTRB(8, 0, 8, 8), padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: KT.peach, borderRadius: BorderRadius.circular(14)),
                child: Row(children: [
                  const Icon(Icons.sell_outlined, size: 18, color: KT.orange),
                  const SizedBox(width: 8),
                  Expanded(child: Text('About: ${_product!.s('name')} · ${usdShort(_product!.i('price_cents'))}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                  InkWell(onTap: () => setState(() => _product = null), child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.close_rounded, size: 18))),
                ]),
              ),
            Row(children: [
              IconButton(onPressed: sending ? null : () => _attach(false), icon: const Icon(Icons.photo_camera_rounded), tooltip: 'Send a photo'),
              IconButton(onPressed: sending ? null : () => _attach(true), icon: const Icon(Icons.videocam_rounded), tooltip: 'Send a video'),
              if (!_isOrder && slug.isNotEmpty) IconButton(onPressed: sending ? null : () => _shareProduct(slug), icon: const Icon(Icons.sell_outlined), tooltip: 'Share a product'),
              Expanded(child: TextField(
                controller: _c, minLines: 1, maxLines: 4, textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Write a message', border: InputBorder.none, isDense: true),
              )),
              IconButton(onPressed: sending ? null : () => _send(), icon: const Icon(Icons.send_rounded, color: KT.orange), tooltip: 'Send'),
            ]),
          ]),
        ),
      );
}
