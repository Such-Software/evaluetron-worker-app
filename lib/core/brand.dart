import 'package:flutter/material.dart';

abstract final class WorkerBrand {
  static const accent = Color(0xFF35E6A8);
  static const accentDeep = Color(0xFF0B8F7D);
  static const signal = Color(0xFFFFB65C);
  static const voidColor = Color(0xFF07100E);
  static const lightSurface = Color(0xFFF4F8F6);
}

class EvaluetronMark extends StatelessWidget {
  const EvaluetronMark({this.size = 36, this.semanticLabel, super.key});

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final mark = CustomPaint(
      size: Size.square(size),
      painter: const _SignalMarkPainter(
        start: WorkerBrand.accent,
        end: WorkerBrand.accentDeep,
      ),
    );
    if (semanticLabel == null) return mark;
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ExcludeSemantics(child: mark),
    );
  }
}

class EvaluetronLockup extends StatelessWidget {
  const EvaluetronLockup({this.markSize = 36, super.key});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Evaluetron Worker',
      header: true,
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EvaluetronMark(size: markSize),
            const SizedBox(width: 11),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'evaluetron',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'WORKER',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalMarkPainter extends CustomPainter {
  const _SignalMarkPainter({required this.start, required this.end});

  final Color start;
  final Color end;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final radius = Radius.circular(size.shortestSide * 0.28);
    final background = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [start, end],
      ).createShader(bounds);
    canvas.drawRRect(RRect.fromRectAndRadius(bounds, radius), background);

    final pulse = Path()
      ..moveTo(size.width * 0.22, size.height * 0.50)
      ..lineTo(size.width * 0.36, size.height * 0.50)
      ..lineTo(size.width * 0.435, size.height * 0.29)
      ..lineTo(size.width * 0.585, size.height * 0.71)
      ..lineTo(size.width * 0.66, size.height * 0.50)
      ..lineTo(size.width * 0.80, size.height * 0.50);
    canvas.drawPath(
      pulse,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.072
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SignalMarkPainter oldDelegate) =>
      start != oldDelegate.start || end != oldDelegate.end;
}
