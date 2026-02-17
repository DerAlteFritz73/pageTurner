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
  final double imageAspectRatio; // width / height of the PDF page
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
    required this.imageAspectRatio,
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

  /// Computes the display rect of the image within the container,
  /// matching BoxFit.contain behavior.
  Rect _getImageRect(Size containerSize) {
    final ar = widget.imageAspectRatio;
    double imageWidth, imageHeight;
    if (containerSize.width / containerSize.height > ar) {
      imageHeight = containerSize.height;
      imageWidth = imageHeight * ar;
    } else {
      imageWidth = containerSize.width;
      imageHeight = imageWidth / ar;
    }
    final left = (containerSize.width - imageWidth) / 2;
    final top = (containerSize.height - imageHeight) / 2;
    return Rect.fromLTWH(left, top, imageWidth, imageHeight);
  }

  Offset _transformPoint(Offset point, Size size) {
    // Transform screen coordinates to image-relative normalized coordinates (0-1)
    final imageRect = _getImageRect(size);
    return Offset(
      (point.dx - imageRect.left) / imageRect.width,
      (point.dy - imageRect.top) / imageRect.height,
    );
  }

  Offset _untransformPoint(Offset normalized, Size size) {
    // Transform image-relative normalized coordinates back to screen coordinates
    final imageRect = _getImageRect(size);
    return Offset(
      normalized.dx * imageRect.width + imageRect.left,
      normalized.dy * imageRect.height + imageRect.top,
    );
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
                imageAspectRatio: widget.imageAspectRatio,
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
  final double imageAspectRatio;

  DrawingCanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentThickness,
    required this.imageAspectRatio,
  });

  Rect _getImageRect(Size containerSize) {
    final ar = imageAspectRatio;
    double imageWidth, imageHeight;
    if (containerSize.width / containerSize.height > ar) {
      imageHeight = containerSize.height;
      imageWidth = imageHeight * ar;
    } else {
      imageWidth = containerSize.width;
      imageHeight = imageWidth / ar;
    }
    final left = (containerSize.width - imageWidth) / 2;
    final top = (containerSize.height - imageHeight) / 2;
    return Rect.fromLTWH(left, top, imageWidth, imageHeight);
  }

  Offset _untransformPoint(Offset normalized, Size size) {
    final imageRect = _getImageRect(size);
    return Offset(
      normalized.dx * imageRect.width + imageRect.left,
      normalized.dy * imageRect.height + imageRect.top,
    );
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
        imageAspectRatio != oldDelegate.imageAspectRatio;
  }
}
