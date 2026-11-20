import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config.dart';
import '../../core/web_auth.dart';
import '../../core/theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/face.dart';
import '../../widgets/ui.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // On the web the website is the front door: signed-out visitors go to its login page.
    if (kIsWeb) WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) goAuth(context); });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth > 860;
          final copy = _Copy(wide: wide);
          final art = const _Art();
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(children: [
                      Row(children: [
                        const Wordmark(size: 24),
                        const Spacer(),
                        if (wide) TextButton(onPressed: () => launchUrl(Uri.parse(Config.siteUrl)), child: const Text('About Kontena', style: TextStyle(fontWeight: FontWeight.w700, color: KT.ink))),
                        TextButton(onPressed: () => goAuth(context), child: const Text('Log in', style: TextStyle(fontWeight: FontWeight.w800, color: KT.ink))),
                      ]),
                      SizedBox(height: wide ? 56 : 24),
                      wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [Expanded(child: copy), const SizedBox(width: 40), Expanded(child: art)])
                          : Column(children: [art, const SizedBox(height: 28), copy]),
                    ]),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _Copy extends StatelessWidget {
  final bool wide;
  const _Copy({required this.wide});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center, children: [
      Text('Import with\npeace of mind.', textAlign: wide ? TextAlign.start : TextAlign.center,
          style: KT.h1.copyWith(fontSize: wide ? 64 : 40, letterSpacing: wide ? -3 : -2, height: 1.0)),
      const SizedBox(height: 16),
      Text('Pool money with other traders, pay into escrow, and release it only when your goods check out.',
          textAlign: wide ? TextAlign.start : TextAlign.center, style: KT.body.copyWith(fontSize: 17)),
      const SizedBox(height: 28),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(children: [
          KtButton('Create account', onPressed: () => goAuth(context, signUp: true)),
          const SizedBox(height: 10),
          KtButton('I already have an account', kind: BtnKind.ghost, onPressed: () => goAuth(context)),
        ]),
      ),
      const SizedBox(height: 18),
      Wrap(spacing: 8, runSpacing: 8, alignment: wide ? WrapAlignment.start : WrapAlignment.center, children: const [
        Pill('Escrow protected', bg: KT.mint, fg: KT.green),
        Pill('Naira · Cedi · USDC', bg: KT.peach, fg: KT.orange),
        Pill('Refund if it fails', bg: KT.sky, fg: Color(0xFF2F6BFF)),
      ]),
    ]);
  }
}

class _Art extends StatelessWidget {
  const _Art();
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: KT.peach, borderRadius: BorderRadius.circular(40)),
      child: Column(children: [
        KtCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const FaceAvatar('Chidi', size: 36),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Phone accessories', style: KT.h3), Text('Guangzhou → Lagos', style: KT.small)])),
            const Pill('72% funded', bg: KT.peach, fg: KT.orange),
          ]),
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(99), child: const LinearProgressIndicator(value: .72, minHeight: 8, color: KT.orange, backgroundColor: KT.line)),
          const SizedBox(height: 14),
          Row(children: const [FaceStack(['Kwame', 'Ada', 'Tunde', 'Efua'], size: 28, more: 2), Spacer(), Text('4 days left', style: TextStyle(fontWeight: FontWeight.w700, color: KT.grey))]),
        ])),
        const SizedBox(height: 12),
        KtCard(color: KT.ink, child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: KT.orange, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.lock_rounded, color: KT.ink, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Balance locked', style: TextStyle(color: Color(0xFF9A9DA5), fontWeight: FontWeight.w600, fontSize: 12)),
            const Text('\$8,400 until inspected', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
          ])),
        ])),
      ]),
    );
  }
}
