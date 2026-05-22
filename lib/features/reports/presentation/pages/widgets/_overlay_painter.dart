part of '../trends_screen.dart';


class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withOpacity(0.55);
    const cut = 240.0;
    final cx = size.width / 2, cy = size.height / 2;
    final rect =
        Rect.fromCenter(center: Offset(cx, cy), width: cut, height: cut);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()
          ..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16))),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
