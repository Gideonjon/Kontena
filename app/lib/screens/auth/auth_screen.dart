import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../widgets/brand.dart';
import '../../widgets/ui.dart';

class AuthScreen extends StatefulWidget {
  final bool signUp;
  const AuthScreen({super.key, required this.signUp});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool signUp = widget.signUp;
  final name = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  String country = 'NG';
  bool busy = false;

  String _friendly(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'That email address doesn\'t look right.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email or password is incorrect.',
        'email-already-in-use' => 'An account with this email already exists. Try logging in.',
        'weak-password' => 'Use a password with at least 6 characters.',
        'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
        'network-request-failed' => 'No connection. Check your internet and try again.',
        'popup-closed-by-user' || 'cancelled-popup-request' => 'Sign-in was cancelled.',
        _ => 'Could not sign you in. Please try again.',
      };

  Future<void> _submit() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) return toast(context, 'Enter your email and password.');
    if (signUp && name.text.trim().isEmpty) return toast(context, 'Enter your name.');
    setState(() => busy = true);
    try {
      final auth = FirebaseAuth.instance;
      if (signUp) {
        await auth.createUserWithEmailAndPassword(email: email.text.trim(), password: pass.text);
        await auth.currentUser?.updateDisplayName(name.text.trim());
        await Api.i.patch('/me', {'name': name.text.trim(), 'country': country});
      } else {
        await auth.signInWithEmailAndPassword(email: email.text.trim(), password: pass.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) toast(context, _friendly(e));
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => busy = true);
    try {
      final auth = FirebaseAuth.instance;
      final cred = kIsWeb ? await auth.signInWithPopup(GoogleAuthProvider()) : await auth.signInWithProvider(GoogleAuthProvider());
      if (cred.additionalUserInfo?.isNewUser == true) {
        await Api.i.patch('/me', {'name': cred.user?.displayName ?? '', 'country': country});
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) toast(context, _friendly(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _reset() async {
    if (email.text.trim().isEmpty) return toast(context, 'Enter your email first.');
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.text.trim());
      if (mounted) toast(context, 'Reset link sent. Check your inbox.');
    } on FirebaseAuthException catch (e) {
      if (mounted) toast(context, _friendly(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.go('/welcome'))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Constrain(
            max: 440,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const KontenaMark(size: 48),
              const SizedBox(height: 20),
              Text(signUp ? 'Create your account' : 'Welcome back', style: KT.h1.copyWith(fontSize: 30)),
              const SizedBox(height: 6),
              Text(signUp ? 'It takes a minute. You choose how you use Kontena next.' : 'Log in to see your orders and wallet.', style: KT.body),
              const SizedBox(height: 26),
              if (signUp) KtField(name, 'Full name'),
              KtField(email, 'Email', keyboard: TextInputType.emailAddress),
              KtField(pass, 'Password', obscure: true),
              if (signUp) ...[
                Text('I trade in', style: KT.label),
                const SizedBox(height: 8),
                Row(children: [
                  for (final c in const [('NG', 'Nigeria · ₦'), ('GH', 'Ghana · ₵')]) ...[
                    Expanded(child: ChoiceChip(
                      label: SizedBox(width: double.infinity, child: Text(c.$2, textAlign: TextAlign.center)),
                      selected: country == c.$1, onSelected: (_) => setState(() => country = c.$1),
                      showCheckmark: false, selectedColor: KT.ink, backgroundColor: KT.paper, side: BorderSide.none,
                      labelStyle: TextStyle(fontWeight: FontWeight.w800, color: country == c.$1 ? Colors.white : KT.ink),
                      padding: const EdgeInsets.symmetric(vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    )),
                    if (c.$1 == 'NG') const SizedBox(width: 10),
                  ],
                ]),
                const SizedBox(height: 20),
              ],
              KtButton(signUp ? 'Create account' : 'Log in', onPressed: _submit, loading: busy),
              if (!signUp) Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _reset, child: const Text('Forgot password?', style: TextStyle(color: KT.grey, fontWeight: FontWeight.w700)))),
              const SizedBox(height: 14),
              Row(children: const [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: KT.grey2, fontWeight: FontWeight.w700))), Expanded(child: Divider())]),
              const SizedBox(height: 14),
              KtButton('Continue with Google', kind: BtnKind.ghost, icon: Icons.g_mobiledata_rounded, onPressed: busy ? null : _google),
              const SizedBox(height: 18),
              Center(child: TextButton(
                onPressed: () => setState(() => signUp = !signUp),
                child: Text.rich(TextSpan(style: const TextStyle(color: KT.grey, fontWeight: FontWeight.w600), children: [
                  TextSpan(text: signUp ? 'Already have an account? ' : 'New to Kontena? '),
                  TextSpan(text: signUp ? 'Log in' : 'Create account', style: const TextStyle(color: KT.ink, fontWeight: FontWeight.w800)),
                ])),
              )),
            ]),
          ),
        ),
      ),
    );
  }
}
