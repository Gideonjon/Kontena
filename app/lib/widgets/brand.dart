import 'package:flutter/material.dart';
import '../core/theme.dart';

/// The Kontena mark: a container with a K cut into it.
class KontenaMark extends StatelessWidget {
  final double size;
  final bool tile;
  const KontenaMark({super.key, this.size = 40, this.tile = true});
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _MarkPainter(tile)));
}

class _MarkPainter extends CustomPainter {
  final bool tile;
  _MarkPainter(this.tile);
  @override
  void paint(Canvas canvas, Size s) {
    final u = s.width / 64;
    if (tile) canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(18 * u)), Paint()..color = KT.orange);
    final boxColor = tile ? Colors.white : KT.orange;
    final cut = tile ? KT.orange : Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(10 * u, 17 * u, 44 * u, 30 * u), Radius.circular(8.5 * u)), Paint()..color = boxColor);
    final rib = Paint()..color = const Color(0xFFFFC9AD)..style = PaintingStyle.stroke..strokeWidth = 3 * u..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(42 * u, 24.5 * u), Offset(42 * u, 39.5 * u), rib);
    canvas.drawLine(Offset(47.5 * u, 24.5 * u), Offset(47.5 * u, 39.5 * u), rib);
    final k = Paint()..color = cut..style = PaintingStyle.stroke..strokeWidth = 4.6 * u..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(21.5 * u, 24.5 * u), Offset(21.5 * u, 39.5 * u), k);
    canvas.drawLine(Offset(21.5 * u, 32.4 * u), Offset(33 * u, 24.8 * u), k);
    canvas.drawLine(Offset(26.4 * u, 29.6 * u), Offset(34.2 * u, 39.6 * u), k);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.tile != tile;
}

class Wordmark extends StatelessWidget {
  final double size;
  final Color color;
  const Wordmark({super.key, this.size = 26, this.color = KT.ink});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        KontenaMark(size: size * 1.05),
        SizedBox(width: size * 0.22),
        Text('kontena', style: TextStyle(fontWeight: FontWeight.w800, fontSize: size, letterSpacing: -size * 0.06, color: color, height: 1)),
      ]);
}
