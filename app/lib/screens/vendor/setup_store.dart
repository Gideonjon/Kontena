import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/media.dart';
import '../../widgets/ui.dart';
import '../shared/store_page.dart';
import 'vendor_store.dart';

class SetupStoreScreen extends ConsumerStatefulWidget {
  const SetupStoreScreen({super.key});
  @override
  ConsumerState<SetupStoreScreen> createState() => _SetupStoreScreenState();
}

class _SetupStoreScreenState extends ConsumerState<SetupStoreScreen> {
  final name = TextEditingController();
  final bio = TextEditingController();
  final city = TextEditingController();
  String? logoKey;
  bool busy = false;

  Future<void> _create() async {
    if (name.text.trim().isEmpty) return toast(context, 'Give your store a name.');
    setState(() => busy = true);
    final r = await guarded(context, () => Api.i.post('/vendor/store', {'name': name.text.trim(), 'bio': bio.text.trim(), 'city': city.text.trim(), 'logoKey': logoKey}));
    if (!mounted) return;
    setState(() => busy = false);
    if (r == null) return;
    ref.invalidate(meProvider);
    ref.invalidate(vendorStoreProvider);
    await ref.read(modeProvider.notifier).set('vendor');
    if (!mounted) return;
    context.go('/v/home');
    showShareSheet(context, r.s('slug'), name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Open your store'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () async {
          await ref.read(modeProvider.notifier).set('customer');
          if (context.mounted) context.go('/c/explore');
        }),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
        child: Constrain(max: 480, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tell buyers who you are.', style: KT.body),
          const SizedBox(height: 22),
          Center(child: GestureDetector(
            onTap: () async {
              final k = await pickAndUploadImages(context);
              if (k.isNotEmpty) setState(() => logoKey = k.first);
            },
            child: Stack(children: [
              FaceAvatar(name.text.isEmpty ? 'store' : name.text, size: 96, imageKey: logoKey),
              Positioned(right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(7), decoration: const BoxDecoration(color: KT.orange, shape: BoxShape.circle), child: const Icon(Icons.photo_camera_rounded, size: 16, color: KT.ink))),
            ]),
          )),
          const SizedBox(height: 24),
          KtField(name, 'Store name', hint: 'e.g. Lagos Phone Parts', onChanged: (_) => setState(() {})),
          KtField(bio, 'About your store', maxLines: 3, hint: 'What you sell and where you ship from'),
          KtField(city, 'City'),
          const SizedBox(height: 6),
          KtCard(color: KT.mint, child: Row(children: [
            const Icon(Icons.link_rounded, color: KT.green), const SizedBox(width: 12),
            Expanded(child: Text('You\'ll get a link and QR code to share with buyers on WhatsApp, Instagram or in person.', style: KT.body.copyWith(fontSize: 13.5, color: KT.ink))),
          ])),
          const SizedBox(height: 22),
          KtButton('Create store', kind: BtnKind.orange, loading: busy, onPressed: _create),
        ])),
      ),
    );
  }
}
