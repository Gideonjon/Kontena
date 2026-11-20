import 'package:flutter/material.dart';
import '../core/api.dart';

/// Illustrated face avatar, deterministic from a seed (name or id). Falls back to this when no photo exists.
class FaceAvatar extends StatelessWidget {
  final String seed;
  final double size;
  final String? imageKey;
  const FaceAvatar(this.seed, {super.key, this.size = 40, this.imageKey});

  static const _skins = [Color(0xFF6B4430), Color(0xFF9A6B4B), Color(0xFFC28A63), Color(0xFF4E3022), Color(0xFFE8B896)];
  static const _bgs = [Color(0xFFFFD9C7), Color(0xFFCDEFDD), Color(0xFFD5E4FF), Color(0xFFFFE9A8), Color(0xFFE3D9FF)];
  static const _shirts = [Color(0xFFFF5B14), Color(0xFF0E7A4B), Color(0xFF2F6BFF), Color(0xFF101114), Color(0xFFF2B84B)];

  @override
  Widget build(BuildContext context) {
    if (imageKey != null && imageKey!.isNotEmpty) {
      return ClipOval(child: Image.network(Api.mediaUrl(imageKey), width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _face()));
    }
    return _face();
  }

  Widget _face() {
    final h = seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff);
    return ClipOval(child: SizedBox(width: size, height: size, child: CustomPaint(painter: _FacePainter(h))));
  }
}

class _FacePainter extends CustomPainter {
  final int h;
  _FacePainter(this.h);

  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 48;
    Paint p(Color c) => Paint()..color = c..isAntiAlias = true;
    final skin = FaceAvatar._skins[h % 5];
    final bg = FaceAvatar._bgs[(h ~/ 5) % 5];
    final shirt = FaceAvatar._shirts[(h ~/ 25) % 5];
    final hairStyle = (h ~/ 125) % 4;
    final hair = const Color(0xFF1B1412);
    canvas.drawRect(Offset.zero & s, p(bg));
    if (hairStyle == 1) canvas.drawCircle(Offset(24 * u, 17 * u), 13.5 * u, p(hair)); // afro back
    if (hairStyle == 2) {
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(11.5 * u, 12 * u, 25 * u, 28 * u), Radius.circular(12 * u)), p(hair)); // long back
    }
    canvas.drawOval(Rect.fromCenter(center: Offset(24 * u, 50 * u), width: 34 * u, height: 26 * u), p(shirt));
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(20 * u, 29 * u, 8 * u, 9 * u), Radius.circular(3 * u)), p(skin));
    canvas.drawCircle(Offset(14.6 * u, 23.5 * u), 2 * u, p(skin));
    canvas.drawCircle(Offset(33.4 * u, 23.5 * u), 2 * u, p(skin));
    canvas.drawOval(Rect.fromCenter(center: Offset(24 * u, 22.5 * u), width: 18.4 * u, height: 20.8 * u), p(skin));
    // hair front
    final hp = Path()
      ..moveTo(14.8 * u, 21 * u)
      ..cubicTo(14 * u, 12 * u, 19 * u, 9.8 * u, 24 * u, 9.8 * u)
      ..cubicTo(29 * u, 9.8 * u, 34 * u, 12 * u, 33.2 * u, 21 * u)
      ..cubicTo(31 * u, 17.5 * u, 28 * u, 16 * u, 24 * u, 16 * u)
      ..cubicTo(20 * u, 16 * u, 17 * u, 17.5 * u, 14.8 * u, 21 * u)
      ..close();
    if (hairStyle == 3) {
      canvas.drawPath(hp, p(const Color(0xFFFF5B14))); // head wrap
    } else {
      canvas.drawPath(hp, p(hair));
    }
    canvas.drawCircle(Offset(20.4 * u, 22.6 * u), 1.25 * u, p(const Color(0xFF2A1B14)));
    canvas.drawCircle(Offset(27.6 * u, 22.6 * u), 1.25 * u, p(const Color(0xFF2A1B14)));
    final smile = Path()..moveTo(20.8 * u, 27 * u)..quadraticBezierTo(24 * u, 29.8 * u, 27.2 * u, 27 * u);
    canvas.drawPath(smile, Paint()..color = const Color(0xFF3A1F14)..style = PaintingStyle.stroke..strokeWidth = 1.3 * u..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) => old.h != h;
}

class FaceStack extends StatelessWidget {
  final List<String> seeds;
  final double size;
  final int more;
  const FaceStack(this.seeds, {super.key, this.size = 26, this.more = 0});
  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < seeds.length; i++) {
      items.add(Positioned(
        left: i * (size * 0.68),
        child: Container(
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: FaceAvatar(seeds[i], size: size),
        ),
      ));
    }
    if (more > 0) {
      items.add(Positioned(
        left: seeds.length * (size * 0.68),
        child: Container(
          width: size + 4, height: size + 4, alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFF101114), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
          child: Text('+$more', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
        ),
      ));
    }
    final w = (seeds.length + (more > 0 ? 1 : 0)) * (size * 0.68) + size * 0.4;
    return SizedBox(width: w, height: size + 4, child: Stack(children: items));
  }
}
