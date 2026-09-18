import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../models/er_diagram.dart';
import '../../theme/app_colors.dart';

class EREdgeWidget extends StatelessWidget {
  final EREdge edge;
  final bool isHighlighted;

  const EREdgeWidget({
    super.key,
    required this.edge,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final fromNode = edge.fromNode;
    final toNode = edge.toNode;

    // Calculate connection points (center of nodes)
    final fromPoint = Offset(
      fromNode.position.dx + fromNode.size.width / 2,
      fromNode.position.dy + fromNode.size.height / 2,
    );

    final toPoint = Offset(
      toNode.position.dx + toNode.size.width / 2,
      toNode.position.dy + toNode.size.height / 2,
    );

    final colors = context.themeColors;

    return CustomPaint(
      size: Size.infinite,
      painter: EREdgePainter(
        fromPoint: fromPoint,
        toPoint: toPoint,
        edgeName: edge.name,
        fieldMappings: edge.fieldMappings,
        isHighlighted: isHighlighted,
        borderColor: colors.borderColor,
        textSecondary: colors.textSecondary,
        bgSecondary: colors.bgSecondary,
        textMuted: colors.textMuted,
        highlightColor: colors.info,
      ),
    );
  }
}

class EREdgePainter extends CustomPainter {
  final Offset fromPoint;
  final Offset toPoint;
  final String edgeName;
  final List<FieldMapping> fieldMappings;
  final bool isHighlighted;
  final Color borderColor;
  final Color textSecondary;
  final Color bgSecondary;
  final Color textMuted;
  final Color highlightColor;

  EREdgePainter({
    required this.fromPoint,
    required this.toPoint,
    required this.edgeName,
    required this.fieldMappings,
    this.isHighlighted = false,
    required this.borderColor,
    required this.textSecondary,
    required this.bgSecondary,
    required this.textMuted,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isHighlighted ? highlightColor : borderColor
      ..strokeWidth = isHighlighted ? 2.0 : 1.5
      ..style = PaintingStyle.stroke;

    // Draw line with dash pattern for foreign keys
    final dashPattern = [5.0, 5.0];
    _drawDashedLine(canvas, fromPoint, toPoint, paint, dashPattern);

    // Draw arrow head at destination
    _drawArrowHead(canvas, toPoint, fromPoint);

    // Draw relationship label
    _drawLabel(canvas, edgeName, fieldMappings);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
    List<double> dash,
  ) {
    final path = Path();
    final distance = (end - start).distance;
    final dashTotal = dash.reduce((a, b) => a + b);
    final numDashes = (distance / dashTotal).ceil();

    final direction = (end - start) / distance;
    var currentPos = start;

    for (int i = 0; i < numDashes; i++) {
      final dashIndex = i % dash.length;
      final dashLength = dash[dashIndex];

      if (dashTotal == 0) continue;

      if (dashIndex % 2 == 0) {
        // Draw line segment
        final nextPos = currentPos + (direction * dashLength);
        path.moveTo(currentPos.dx, currentPos.dy);
        path.lineTo(nextPos.dx, nextPos.dy);
      }

      currentPos += direction * dashLength;

      if ((currentPos - start).distance >= distance) {
        break;
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawArrowHead(Canvas canvas, Offset tip, Offset from) {
    final size = 10.0;
    final direction = (from - tip);
    final angle = atan2(direction.dy, direction.dx);

    final arrowPaint = Paint()
      ..color = isHighlighted ? highlightColor : borderColor
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(
      tip.dx + size * cos(angle + pi / 6),
      tip.dy + size * sin(angle + pi / 6),
    );
    path.lineTo(
      tip.dx + size * cos(angle - pi / 6),
      tip.dy + size * sin(angle - pi / 6),
    );
    path.close();

    canvas.drawPath(path, arrowPaint);
  }

  void _drawLabel(Canvas canvas, String name, List<FieldMapping> mappings) {
    final midPoint = Offset(
      (fromPoint.dx + toPoint.dx) / 2,
      (fromPoint.dy + toPoint.dy) / 2,
    );

    // Build label text
    final textSpan = TextSpan(
      text: name,
      style: TextStyle(
        color: textSecondary,
        fontSize: 11,
        backgroundColor: bgSecondary,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Draw background
    final bgRect = Rect.fromLTWH(
      midPoint.dx - textPainter.width / 2 - 4,
      midPoint.dy - textPainter.height / 2 - 4,
      textPainter.width + 8,
      textPainter.height + 8,
    );

    final bgPaint = Paint()
      ..color = bgSecondary
      ..style = PaintingStyle.fill;

    canvas.drawRect(bgRect, bgPaint);

    // Draw text
    textPainter.paint(
      canvas,
      Offset(
        midPoint.dx - textPainter.width / 2,
        midPoint.dy - textPainter.height / 2,
      ),
    );

    // Draw field mapping labels if any
    if (mappings.isNotEmpty) {
      final mappingText = mappings
          .map((m) => '${m.fromField} → ${m.toField}')
          .join('\n');

      final mappingSpan = TextSpan(
        text: mappingText,
        style: TextStyle(
          color: textMuted,
          fontSize: 11,
          backgroundColor: bgSecondary,
        ),
      );

      final mappingPainter = TextPainter(
        text: mappingSpan,
        textDirection: TextDirection.ltr,
      );

      mappingPainter.layout();

      final mappingOffset = Offset(
        midPoint.dx - mappingPainter.width / 2,
        midPoint.dy + textPainter.height / 2 + 4,
      );

      // Draw background for mappings
      final mappingBgRect = Rect.fromLTWH(
        mappingOffset.dx - 4,
        mappingOffset.dy - 4,
        mappingPainter.width + 8,
        mappingPainter.height + 8,
      );

      canvas.drawRect(mappingBgRect, bgPaint);

      // Draw mappings text
      mappingPainter.paint(canvas, mappingOffset);
    }
  }

  @override
  bool shouldRepaint(covariant EREdgePainter oldDelegate) {
    return oldDelegate.fromPoint != fromPoint ||
        oldDelegate.toPoint != toPoint ||
        oldDelegate.isHighlighted != isHighlighted;
  }
}
