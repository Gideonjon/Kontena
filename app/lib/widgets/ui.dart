import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/api.dart';

enum BtnKind { primary, orange, soft, ghost, danger }

class KtButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final BtnKind kind;
  final IconData? icon;
  final bool expand;
  const KtButton(this.label, {super.key, this.onPressed, this.loading = false, this.kind = BtnKind.primary, this.icon, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (kind) {
      BtnKind.primary => (KT.ink, Colors.white),
      BtnKind.orange => (KT.orange, KT.ink),
      BtnKind.soft => (KT.peach, KT.ink),
      BtnKind.ghost => (Colors.white, KT.ink),
      BtnKind.danger => (const Color(0xFFFDECEA), KT.red),
    };
    final disabled = onPressed == null || loading;
    final child = loading
        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 19, color: fg), const SizedBox(width: 8)],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16, letterSpacing: -0.2))),
          ]);
    final btn = Material(
      color: disabled && !loading ? bg.withOpacity(0.45) : bg,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: disabled ? null : onPressed,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 26),
          decoration: kind == BtnKind.ghost ? BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: KT.line)) : null,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: btn) : btn;
  }
}

class KtCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final VoidCallback? onTap;
  const KtCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color = Colors.white, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: color,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(borderRadius: BorderRadius.circular(24), onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}

class KtField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboard;
  final bool obscure;
  final int maxLines;
  final String? prefix;
  final void Function(String)? onChanged;
  const KtField(this.controller, this.label, {super.key, this.hint, this.keyboard, this.obscure = false, this.maxLines = 1, this.prefix, this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller, keyboardType: keyboard, obscureText: obscure, maxLines: obscure ? 1 : maxLines, onChanged: onChanged,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          decoration: InputDecoration(labelText: label, hintText: hint, prefixText: prefix, floatingLabelBehavior: FloatingLabelBehavior.auto),
        ),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const Pill(this.text, {super.key, this.bg = KT.paper, this.fg = KT.ink});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800)),
      );
}

/// Plain-language order status chip.
class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  static (String, Color, Color) info(String s) => switch (s) {
        'awaiting_payment' => ('Awaiting payment', KT.butter, const Color(0xFF8A6A00)),
        'funded' => ('In escrow', KT.sky, const Color(0xFF2F6BFF)),
        'accepted' => ('Deposit released', KT.peach, KT.orange),
        'inspection' => ('Inspection', KT.butter, const Color(0xFF8A6A00)),
        'shipped' => ('On its way', KT.sky, const Color(0xFF2F6BFF)),
        'delivered' => ('Delivered', KT.mint, KT.green),
        'refunded' => ('Refunded', const Color(0xFFFDECEA), KT.red),
        'cancelled' => ('Cancelled', KT.paper, KT.grey),
        _ => (s, KT.paper, KT.grey),
      };
  @override
  Widget build(BuildContext context) {
    final (t, bg, fg) = info(status);
    return Pill(t, bg: bg, fg: fg);
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Row(children: [Expanded(child: Text(text.toUpperCase(), style: KT.label)), if (trailing != null) trailing!]),
      );
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: KT.orange)));
}

class ErrorBox extends StatelessWidget {
  final Object error;
  final VoidCallback? retry;
  const ErrorBox(this.error, {super.key, this.retry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: KT.grey2),
            const SizedBox(height: 12),
            Text(error is ApiException ? (error as ApiException).message : 'Something went wrong.', textAlign: TextAlign.center, style: KT.body),
            if (retry != null) ...[const SizedBox(height: 16), KtButton('Try again', onPressed: retry, expand: false, kind: BtnKind.soft)],
          ]),
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 72, height: 72, decoration: const BoxDecoration(color: KT.peach, shape: BoxShape.circle), child: Icon(icon, color: KT.orange, size: 32)),
            const SizedBox(height: 18),
            Text(title, style: KT.h3, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(body, style: KT.body, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ]),
        ),
      );
}

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

/// Runs an API call with a loading flag and error toast. Returns null on failure.
Future<T?> guarded<T>(BuildContext c, Future<T> Function() f, {void Function(bool)? busy}) async {
  busy?.call(true);
  try {
    return await f();
  } on ApiException catch (e) {
    if (c.mounted) toast(c, e.message);
  } catch (_) {
    if (c.mounted) toast(c, 'Something went wrong. Please try again.');
  } finally {
    busy?.call(false);
  }
  return null;
}

/// Constrains content to a phone-ish column on wide screens (web / tablet).
class Constrain extends StatelessWidget {
  final Widget child;
  final double max;
  const Constrain({super.key, required this.child, this.max = 640});
  @override
  Widget build(BuildContext context) => Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child));
}
