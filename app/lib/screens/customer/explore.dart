import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/state.dart';
import '../../core/theme.dart';
import '../../widgets/face.dart';
import '../../widgets/shell.dart';
import '../../widgets/ui.dart';

final storesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, q) async {
  final r = await Api.i.get('/stores', q: {if (q.isNotEmpty) 'q': q});
  return r.list('stores');
});

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});
  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  final search = TextEditingController();
  Timer? _debounce;
  String q = '';

  @override
  void initState() {
    super.initState();
    // someone opened a shared store link before signing up: take them back to it once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = ref.read(prefsProvider);
      final slug = prefs.getString('pending_store');
      if (slug != null) {
        prefs.remove('pending_store');
        if (mounted) context.push('/s/$slug');
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _openLink(String v) {
    final m = RegExp(r'/s/([a-z0-9-]+)').firstMatch(v.trim().toLowerCase());
    final slug = m?.group(1) ?? v.trim().toLowerCase();
    if (slug.isEmpty) return;
    context.push('/s/$slug');
  }

  @override
  Widget build(BuildContext context) {
    final stores = ref.watch(storesProvider(q));
    return RefreshIndicator(
      color: KT.orange,
      onRefresh: () async => ref.refresh(storesProvider(q).future),
      child: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
        const PageHeader('Find suppliers', subtitle: 'Explore'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            controller: search,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => setState(() => q = v.trim()));
            },
            decoration: const InputDecoration(hintText: 'Search stores or goods', prefixIcon: Icon(Icons.search_rounded)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: KtCard(
            color: KT.peach,
            onTap: () => _linkSheet(context),
            child: Row(children: [
              const Icon(Icons.link_rounded, color: KT.orange),
              const SizedBox(width: 12),
              Expanded(child: Text('Got a store link from a supplier? Open it here.', style: KT.body.copyWith(color: KT.ink, fontWeight: FontWeight.w700, fontSize: 14))),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SectionLabel('Stores')),
        stores.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorBox(e, retry: () => ref.invalidate(storesProvider(q))),
          data: (list) => list.isEmpty
              ? const EmptyState(icon: Icons.storefront_outlined, title: 'No stores yet', body: 'Ask your supplier for their Kontena link, or check back soon.')
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(children: [for (final s in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: _StoreTile(s))]),
                ),
        ),
      ]),
    );
  }

  void _linkSheet(BuildContext context) {
    final c = TextEditingController();
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 4, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Open a store link', style: KT.h2),
          const SizedBox(height: 6),
          Text('Paste the link your supplier sent you.', style: KT.body),
          const SizedBox(height: 16),
          KtField(c, 'Store link', hint: 'kontena.app/s/your-supplier'),
          KtButton('Open store', onPressed: () { Navigator.pop(ctx); _openLink(c.text); }),
        ]),
      ),
    );
  }
}

class _StoreTile extends StatelessWidget {
  final Map<String, dynamic> s;
  const _StoreTile(this.s);
  @override
  Widget build(BuildContext context) {
    return KtCard(
      onTap: () => context.push('/s/${s.s('slug')}'),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(16), child: s.s('logo_key').isNotEmpty
            ? Image.network(Api.mediaUrl(s.s('logo_key')), width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => FaceAvatar(s.s('name'), size: 56))
            : FaceAvatar(s.s('name'), size: 56)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(s.s('name'), maxLines: 1, overflow: TextOverflow.ellipsis, style: KT.h3)),
            if (s.b('verified')) ...[const SizedBox(width: 6), const Icon(Icons.verified_rounded, size: 18, color: KT.green)],
          ]),
          const SizedBox(height: 3),
          Text([if (s.s('city').isNotEmpty) s.s('city'), s.s('country') == 'GH' ? 'Ghana' : 'Nigeria', '${s.i('product_count')} products'].join(' · '), style: KT.small),
        ])),
        const Icon(Icons.chevron_right_rounded, color: KT.grey2),
      ]),
    );
  }
}
