import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/annotation.dart';

class DrawingCanvas extends StatefulWidget {
  final List<Stroke> strokes;
  final bool isDrawingMode;
  final bool isEraserMode;
  final Color currentColor;
  final double currentThickness;
  final int currentPageIndex;
  final double imageAspectRatio;
  final void Function(Stroke stroke) onStrokeComplete;
  final void Function(String strokeId) onStrokeErased;
  final void Function(List<Offset> points)? onLivePointsChanged;
  final void Function(bool isActive)? onStylusStateChanged;

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
    this.onStylusStateChanged,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<Offset> _currentPoints = [];
  bool _isDrawing = false;
  int? _activePointerId;

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
    final imageRect = _getImageRect(size);
    return Offset(
      (point.dx - imageRect.left) / imageRect.width,
      (point.dy - imageRect.top) / imageRect.height,
    );
  }

  Offset _untransformPoint(Offset normalized, Size size) {
    final imageRect = _getImageRect(size);
    return Offset(
      normalized.dx * imageRect.width + imageRect.left,
      normalized.dy * imageRect.height + imageRect.top,
    );
  }

  bool _isStylusKind(PointerDeviceKind kind) =>
      kind == PointerDeviceKind.stylus ||
      kind == PointerDeviceKind.invertedStylus;

  void _onPointerDown(PointerDownEvent event, Size size) {
    if (!_isStylusKind(event.kind)) return;
    if (!widget.isDrawingMode && !widget.isEraserMode) return;

    _activePointerId = event.pointer;
    widget.onStylusStateChanged?.call(true);

    final isErasing =
        widget.isEraserMode || event.kind == PointerDeviceKind.invertedStylus;

    if (isErasing) {
      _tryEraseStroke(event.localPosition, size);
    } else {
      setState(() {
        _isDrawing = true;
        _currentPoints = [_transformPoint(event.localPosition, size)];
      });
      widget.onLivePointsChanged?.call(List.unmodifiable(_currentPoints));
    }
  }

  void _onPointerMove(PointerMoveEvent event, Size size) {
    if (event.pointer != _activePointerId) return;

    final isErasing =
        widget.isEraserMode || event.kind == PointerDeviceKind.invertedStylus;

    if (isErasing) {
      _tryEraseStroke(event.localPosition, size);
    } else if (_isDrawing) {
      setState(() {
        _currentPoints.add(_transformPoint(event.localPosition, size));
      });
      widget.onLivePointsChanged?.call(List.unmodifiable(_currentPoints));
    }
  }

  void _onPointerUp(PointerUpEvent event, Size size) {
    if (event.pointer != _activePointerId) return;
    _activePointerId = null;
    widget.onStylusStateChanged?.call(false);

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

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _activePointerId) return;
    _activePointerId = null;
    widget.onStylusStateChanged?.call(false);
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
        if ((strokeScreenPoint - screenPoint).distance < hitRadius) {
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

        // Always translucent: finger events pass through to InteractiveViewer.
        // Only stylus events are handled here for drawing.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _onPointerDown(e, size),
          onPointerMove: (e) => _onPointerMove(e, size),
          onPointerUp: (e) => _onPointerUp(e, size),
          onPointerCancel: (e) => _onPointerCancel(e),
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
