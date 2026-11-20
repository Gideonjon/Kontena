import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/media.dart';
import '../../widgets/ui.dart';
import 'vendor_store.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? existing;
  const ProductFormScreen({super.key, this.existing});
  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  late final name = TextEditingController(text: widget.existing?.s('name'));
  late final desc = TextEditingController(text: widget.existing?.s('description'));
  late final price = TextEditingController(text: widget.existing == null ? '' : (widget.existing!.i('price_cents') / 100).toStringAsFixed(2));
  late final minQty = TextEditingController(text: '${widget.existing?.i('min_qty', 1) ?? 1}');
  late final lead = TextEditingController(text: '${widget.existing?.i('lead_days', 21) ?? 21}');
  String? imageKey;
  bool active = true;
  bool busy = false;
  bool get editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    imageKey = widget.existing?.s('image_key');
    active = widget.existing == null || widget.existing!.b('active');
  }

  Future<void> _save() async {
    final p = double.tryParse(price.text.trim()) ?? 0;
    if (name.text.trim().isEmpty || p <= 0) return toast(context, 'Add a name and a price above \$0.');
    final body = {
      'name': name.text.trim(), 'description': desc.text.trim(), 'priceUsd': p,
      'minQty': int.tryParse(minQty.text) ?? 1, 'leadDays': int.tryParse(lead.text) ?? 21,
      if (imageKey != null && imageKey!.isNotEmpty) 'imageKey': imageKey, if (editing) 'active': active,
    };
    setState(() => busy = true);
    final r = await guarded(context, () => editing ? Api.i.patch('/vendor/products/${widget.existing!.s('id')}', body) : Api.i.post('/vendor/products', body));
    if (!mounted) return;
    setState(() => busy = false);
    if (r == null) return;
    ref.invalidate(vendorStoreProvider);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'Edit product' : 'New product')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Constrain(max: 480, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () async {
              final k = await pickAndUploadImages(context);
              if (k.isNotEmpty) setState(() => imageKey = k.first);
            },
            child: Container(
              height: 170, width: double.infinity, decoration: BoxDecoration(color: KT.peach, borderRadius: BorderRadius.circular(24)),
              clipBehavior: Clip.antiAlias,
              child: imageKey != null && imageKey!.isNotEmpty
                  ? Image.network(Api.mediaUrl(imageKey), fit: BoxFit.cover)
                  : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_photo_alternate_rounded, size: 36, color: KT.orange), SizedBox(height: 6), Text('Add a photo', style: TextStyle(fontWeight: FontWeight.w800))]),
            ),
          ),
          const SizedBox(height: 20),
          KtField(name, 'Product name'),
          KtField(desc, 'Description', maxLines: 3),
          KtField(price, 'Price per unit (USD)', prefix: '\$ ', keyboard: const TextInputType.numberWithOptions(decimal: true)),
          Row(children: [
            Expanded(child: KtField(minQty, 'Minimum order', keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            Expanded(child: KtField(lead, 'Lead time (days)', keyboard: TextInputType.number)),
          ]),
          Text('Buyers pay into escrow. You get a 30% deposit when you accept, and the rest after inspection. Lead time sets your shipping deadline.', style: KT.small),
          if (editing) SwitchListTile(contentPadding: EdgeInsets.zero, value: active, activeColor: KT.orange, onChanged: (v) => setState(() => active = v), title: const Text('Visible on my store', style: TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(height: 20),
          KtButton(editing ? 'Save changes' : 'Add product', kind: BtnKind.orange, loading: busy, onPressed: _save),
        ])),
      ),
    );
  }
}
