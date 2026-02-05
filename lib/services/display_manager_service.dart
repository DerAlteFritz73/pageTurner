import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_presentation_display/flutter_presentation_display.dart';

import '../models/annotation.dart';

class DisplayManagerService {
  final FlutterPresentationDisplay _displayManager =
      FlutterPresentationDisplay();

  bool _isSecondaryDisplayActive = false;
  int? _secondaryDisplayId;
  StreamSubscription? _displayChangeSub;
  DateTime _lastLiveUpdate = DateTime.now();

  bool get isSecondaryDisplayActive => _isSecondaryDisplayActive;

  Future<void> init({
    required void Function(bool hasSecondaryDisplay) onDisplayStatusChanged,
  }) async {
    await _checkForDisplays(onDisplayStatusChanged);
    _displayChangeSub =
        _displayManager.connectedDisplaysChangedStream.listen((_) {
      _checkForDisplays(onDisplayStatusChanged);
    });
  }

  Future<void> _checkForDisplays(
    void Function(bool) onDisplayStatusChanged,
  ) async {
    final displays = await _displayManager.getDisplays();
    if (displays != null && displays.length > 1) {
      final secondaryDisplay = displays[1];
      _secondaryDisplayId = secondaryDisplay.displayId;
      if (!_isSecondaryDisplayActive) {
        await _displayManager.showSecondaryDisplay(
          displayId: _secondaryDisplayId!,
          routerName: 'presentation',
        );
        _isSecondaryDisplayActive = true;
      }
      onDisplayStatusChanged(true);
    } else {
      if (_isSecondaryDisplayActive && _secondaryDisplayId != null) {
        await _displayManager.hideSecondaryDisplay(
          displayId: _secondaryDisplayId!,
        );
      }
      _isSecondaryDisplayActive = false;
      _secondaryDisplayId = null;
      onDisplayStatusChanged(false);
    }
  }

  Future<void> sendFullSync({
    required int currentPage,
    required int totalPages,
    required int rotation,
    required List<int> pageImageBytes,
    required List<Stroke> strokes,
  }) async {
    if (!_isSecondaryDisplayActive) return;
    final data = jsonEncode({
      'action': 'fullSync',
      'currentPage': currentPage,
      'totalPages': totalPages,
      'rotation': rotation,
      'pageImageBase64': base64Encode(pageImageBytes),
      'strokes': strokes.map((s) => s.toJson()).toList(),
    });
    await _displayManager.transferDataToPresentation(data);
  }

  Future<void> sendStrokeAdded(Stroke stroke) async {
    if (!_isSecondaryDisplayActive) return;
    final data = jsonEncode({
      'action': 'strokeAdded',
      'stroke': stroke.toJson(),
    });
    await _displayManager.transferDataToPresentation(data);
  }

  Future<void> sendStrokeRemoved(String strokeId) async {
    if (!_isSecondaryDisplayActive) return;
    final data = jsonEncode({
      'action': 'strokeRemoved',
      'strokeId': strokeId,
    });
    await _displayManager.transferDataToPresentation(data);
  }

  Future<void> sendLiveStroke({
    required List<Offset> points,
    required Color color,
    required double thickness,
  }) async {
    if (!_isSecondaryDisplayActive) return;
    final now = DateTime.now();
    if (now.difference(_lastLiveUpdate).inMilliseconds < 50) return;
    _lastLiveUpdate = now;
    final data = jsonEncode({
      'action': 'liveStroke',
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'color': ((color.a * 255).round() << 24) |
          ((color.r * 255).round() << 16) |
          ((color.g * 255).round() << 8) |
          (color.b * 255).round(),
      'thickness': thickness,
    });
    await _displayManager.transferDataToPresentation(data);
  }

  Future<void> clearLiveStroke() async {
    if (!_isSecondaryDisplayActive) return;
    final data = jsonEncode({'action': 'liveStrokeClear'});
    await _displayManager.transferDataToPresentation(data);
  }

  Future<void> sendStrokesCleared(int pageIndex) async {
    if (!_isSecondaryDisplayActive) return;
    final data = jsonEncode({
      'action': 'strokesCleared',
      'pageIndex': pageIndex,
    });
    await _displayManager.transferDataToPresentation(data);
  }

  void dispose() {
    _displayChangeSub?.cancel();
  }
}
