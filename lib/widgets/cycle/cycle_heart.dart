import 'package:flutter/material.dart';
import 'package:todo_app/widgets/cycle/cycle_colors.dart';

/// The day's heart for a mark of sex: **solid** with protection, only an
/// **outline** without it. Null — no heart at all, so a day with no such mark
/// draws nothing.
///
/// [sex] is the stored value of `cycle_days.sex`: 0 none, 1 protected,
/// 2 unprotected.
class CycleHeart extends StatelessWidget {
  const CycleHeart({super.key, required this.sex, this.size = 12});

  final int? sex;
  final double size;

  /// Whether a day with this mark shows a heart at all.
  static bool shows(int? sex) => sex == 1 || sex == 2;

  @override
  Widget build(BuildContext context) {
    if (!shows(sex)) return SizedBox(width: size, height: size);
    return Semantics(
      label: sex == 1 ? 'секс с защитой' : 'секс без защиты',
      child: CustomPaint(
        size: Size(size, size),
        painter: CycleHeartPainter(
          fill: sex == 1 ? heartColor : null,
          stroke: heartColor,
          strokeWidth: 2.2,
        ),
      ),
    );
  }
}

/// The design's heart (24x24 grid): solid when [fill] is given, outlined when
/// [stroke] is.
class CycleHeartPainter extends CustomPainter {
  const CycleHeartPainter({this.fill, this.stroke, this.strokeWidth = 1.8});

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..fillType = PathFillType.nonZero
      ..moveTo(12, 20.5)
      ..cubicTo(12, 20.5, 4.5, 15.9, 4.5, 10.3)
      ..arcToPoint(const Offset(12, 7.6), radius: const Radius.circular(4.3))
      ..arcToPoint(const Offset(19.5, 10.3), radius: const Radius.circular(4.3))
      ..cubicTo(19.5, 15.9, 12, 20.5, 12, 20.5)
      ..close();
    if (fill != null) canvas.drawPath(path, Paint()..color = fill!);
    if (stroke != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = stroke!
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(CycleHeartPainter old) =>
      old.fill != fill || old.stroke != stroke;
}
