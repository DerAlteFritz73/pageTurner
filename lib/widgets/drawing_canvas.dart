import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation.dart';

class DrawingCanvas extends StatefulWidget {
  final List<Stroke> strokes;
  final bool isDrawingMode;
  final bool isEraserMode;
  final Color currentColor;
  final double currentThickness;
  final int currentPageIndex;
  final int rotation; // 0, 1, 2, or 3 (quarter turns)
  final void Function(Stroke stroke) onStrokeComplete;
  final void Function(String strokeId) onStrokeErased;
  final void Function(List<Offset> points)? onLivePointsChanged;

  const DrawingCanvas({
    super.key,
    required this.strokes,
    required this.isDrawingMode,
    required this.isEraserMode,
    required this.currentColor,
    required this.currentThickness,
    required this.currentPageIndex,
    required this.rotation,
    required this.onStrokeComplete,
    required this.onStrokeErased,
    this.onLivePointsChanged,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<Offset> _currentPoints = [];
  bool _isDrawing = false;

  Offset _transformPoint(Offset point, Size size) {
    // Transform screen coordinates to normalized coordinates (0-1)
    // taking rotation into account
    double x = point.dx;
    double y = point.dy;

    // First, transform based on rotation
    switch (widget.rotation) {
      case 1: // 90° clockwise
        final temp = x;
        x = y;
        y = size.width - temp;
        // After rotation, swap dimensions
        return Offset(x / size.height, y / size.width);
      case 2: // 180°
        x = size.width - x;
        y = size.height - y;
        return Offset(x / size.width, y / size.height);
      case 3: // 270° clockwise
        final temp = x;
        x = size.height - y;
        y = temp;
        // After rotation, swap dimensions
        return Offset(x / size.height, y / size.width);
      default: // 0°
        return Offset(x / size.width, y / size.height);
    }
  }

  Offset _untransformPoint(Offset normalized, Size size) {
    // Transform normalized coordinates (0-1) back to screen coordinates
    // taking rotation into account
    double x = normalized.dx;
    double y = normalized.dy;

    switch (widget.rotation) {
      case 1: // 90° clockwise
        // Reverse: x = y/h, y = (w-temp)/w => temp = w - y*w, y_screen = x*h
        final screenX = size.width - y * size.width;
        final screenY = x * size.height;
        return Offset(screenX, screenY);
      case 2: // 180°
        return Offset(
          size.width - x * size.width,
          size.height - y * size.height,
        );
      case 3: // 270° clockwise
        // Reverse transformation
        final screenX = y * size.width;
        final screenY = size.height - x * size.height;
        return Offset(screenX, screenY);
      default: // 0°
        return Offset(x * size.width, y * size.height);
    }
  }

  void _onPanStart(DragStartDetails details, Size size) {
    if (!widget.isDrawingMode && !widget.isEraserMode) return;

    final localPosition = details.localPosition;

    if (widget.isEraserMode) {
      _tryEraseStroke(localPosition, size);
    } else {
      setState(() {
        _isDrawing = true;
        _currentPoints = [_transformPoint(localPosition, size)];
      });
      widget.onLivePointsChanged?.call(List.unmodifiable(_currentPoints));
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (!widget.isDrawingMode && !widget.isEraserMode) return;

    final localPosition = details.localPosition;

    if (widget.isEraserMode) {
      _tryEraseStroke(localPosition, size);
    } else if (_isDrawing) {
      setState(() {
        _currentPoints.add(_transformPoint(localPosition, size));
      });
      widget.onLivePointsChanged?.call(List.unmodifiable(_currentPoints));
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (!widget.isDrawingMode || widget.isEraserMode) return;

    if (_isDrawing && _currentPoints.length >= 2) {
      final stroke = Stroke(
        pageIndex: widget.currentPageIndex,
        points: List.from(_currentPoints),
        color: widget.currentColor,
        thickness: widget.currentThickness,
      );
      widget.onStrokeComplete(stroke);
    }

    setState(() {
      _isDrawing = false;
      _currentPoints = [];
    });
    widget.onLivePointsChanged?.call(const []);
  }

  void _tryEraseStroke(Offset screenPoint, Size size) {
    const hitRadius = 20.0;

    for (final stroke in widget.strokes) {
      for (final normalizedPoint in stroke.points) {
        final strokeScreenPoint = _untransformPoint(normalizedPoint, size);
        final distance = (strokeScreenPoint - screenPoint).distance;
        if (distance < hitRadius) {
          widget.onStrokeErased(stroke.id);
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);

        return GestureDetector(
          behavior: (widget.isDrawingMode || widget.isEraserMode)
              ? HitTestBehavior.opaque
              : HitTestBehavior.translucent,
          onPanStart: (details) => _onPanStart(details, size),
          onPanUpdate: (details) => _onPanUpdate(details, size),
          onPanEnd: _onPanEnd,
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: DrawingCanvasPainter(
                strokes: widget.strokes,
                currentPoints: _currentPoints,
                currentColor: widget.currentColor,
                currentThickness: widget.currentThickness,
                rotation: widget.rotation,
              ),
            ),
          ),
        );
      },
    );
  }
}

class DrawingCanvasPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentThickness;
  final int rotation;

  DrawingCanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentThickness,
    required this.rotation,
  });

  Offset _untransformPoint(Offset normalized, Size size) {
    double x = normalized.dx;
    double y = normalized.dy;

    switch (rotation) {
      case 1: // 90° clockwise
        final screenX = size.width - y * size.width;
        final screenY = x * size.height;
        return Offset(screenX, screenY);
      case 2: // 180°
        return Offset(
          size.width - x * size.width,
          size.height - y * size.height,
        );
      case 3: // 270° clockwise
        final screenX = y * size.width;
        final screenY = size.height - x * size.height;
        return Offset(screenX, screenY);
      default: // 0°
        return Offset(x * size.width, y * size.height);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Draw existing strokes
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;

      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.thickness
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = ui.Path();
      final screenPoints =
          stroke.points.map((p) => _untransformPoint(p, size)).toList();

      path.moveTo(screenPoints[0].dx, screenPoints[0].dy);
      for (int i = 1; i < screenPoints.length; i++) {
        path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
      }

      canvas.drawPath(path, paint);
    }

    // Draw current stroke being drawn
    if (currentPoints.length >= 2) {
      final paint = Paint()
        ..color = currentColor
        ..strokeWidth = currentThickness
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      final path = ui.Path();
      final screenPoints =
          currentPoints.map((p) => _untransformPoint(p, size)).toList();

      path.moveTo(screenPoints[0].dx, screenPoints[0].dy);
      for (int i = 1; i < screenPoints.length; i++) {
        path.lineTo(screenPoints[i].dx, screenPoints[i].dy);
      }

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(DrawingCanvasPainter oldDelegate) {
    return strokes != oldDelegate.strokes ||
        currentPoints != oldDelegate.currentPoints ||
        currentColor != oldDelegate.currentColor ||
        currentThickness != oldDelegate.currentThickness ||
        rotation != oldDelegate.rotation;
  }
}
