import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_presentation_display/flutter_presentation_display.dart';

import '../models/annotation.dart';
import 'drawing_canvas.dart';

class PresentationDisplayScreen extends StatefulWidget {
  const PresentationDisplayScreen({super.key});

  @override
  State<PresentationDisplayScreen> createState() =>
      _PresentationDisplayScreenState();
}

class _PresentationDisplayScreenState extends State<PresentationDisplayScreen> {
  final FlutterPresentationDisplay _displayManager =
      FlutterPresentationDisplay();

  Uint8List? _pageImageBytes;
  Uint8List? _nextPageImageBytes;
  List<Stroke> _strokes = [];
  List<Stroke> _nextPageStrokes = [];
  int _currentPage = 0;
  int _totalPages = 0;
  int _rotation = 0;
  double _imageAspectRatio = 1.0;
  bool _halfPageMode = false;
  int _halfPageOffset = 0;

  // Live stroke preview
  List<Offset> _livePoints = [];
  Color _liveColor = Colors.transparent;
  double _liveThickness = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _displayManager.listenDataFromMainDisplay(_handleData);
  }

  void _handleData(dynamic argument) {
    final Map<String, dynamic> data;
    if (argument is String) {
      data = jsonDecode(argument) as Map<String, dynamic>;
    } else if (argument is Map) {
      data = Map<String, dynamic>.from(argument);
    } else {
      return;
    }

    final action = data['action'] as String;

    setState(() {
      switch (action) {
        case 'fullSync':
          _currentPage = data['currentPage'] as int;
          _totalPages = data['totalPages'] as int;
          _rotation = data['rotation'] as int;
          _imageAspectRatio = (data['imageAspectRatio'] as num?)?.toDouble() ?? 1.0;
          _halfPageMode = data['halfPageMode'] as bool? ?? false;
          _halfPageOffset = data['halfPageOffset'] as int? ?? 0;
          if (data['pageImageBase64'] != null) {
            _pageImageBytes =
                base64Decode(data['pageImageBase64'] as String);
          }
          _strokes = (data['strokes'] as List)
              .map((s) => Stroke.fromJson(Map<String, dynamic>.from(s as Map)))
              .toList();
          if (data['nextPageImageBase64'] != null) {
            _nextPageImageBytes =
                base64Decode(data['nextPageImageBase64'] as String);
          } else {
            _nextPageImageBytes = null;
          }
          if (data['nextPageStrokes'] != null) {
            _nextPageStrokes = (data['nextPageStrokes'] as List)
                .map((s) => Stroke.fromJson(Map<String, dynamic>.from(s as Map)))
                .toList();
          } else {
            _nextPageStrokes = [];
          }
          break;
        case 'strokeAdded':
          _strokes.add(
            Stroke.fromJson(
              Map<String, dynamic>.from(data['stroke'] as Map),
            ),
          );
          break;
        case 'strokeRemoved':
          _strokes.removeWhere((s) => s.id == data['strokeId']);
          break;
        case 'strokesCleared':
          _strokes.clear();
          break;
        case 'liveStroke':
          _livePoints = (data['points'] as List)
              .map((p) => Offset(
                    (p['x'] as num).toDouble(),
                    (p['y'] as num).toDouble(),
                  ))
              .toList();
          _liveColor = Color(data['color'] as int);
          _liveThickness = (data['thickness'] as num).toDouble();
          break;
        case 'liveStrokeClear':
          _livePoints = [];
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _pageImageBytes == null
            ? const Center(
                child: Text(
                  'En attente du PDF...',
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              )
            : RotatedBox(
                quarterTurns: _rotation,
                child: Column(
                  children: [
                    // PDF aligned to top
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Builder(builder: (context) {
                          Widget pageContent = Stack(
                            children: [
                              Image.memory(
                                _pageImageBytes!,
                                fit: BoxFit.contain,
                              ),
                              Positioned.fill(
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final size = Size(
                                      constraints.maxWidth,
                                      constraints.maxHeight,
                                    );
                                    return CustomPaint(
                                      size: size,
                                      painter: DrawingCanvasPainter(
                                        strokes: _strokes,
                                        currentPoints: _livePoints,
                                        currentColor: _liveColor,
                                        currentThickness: _liveThickness,
                                        imageAspectRatio: _imageAspectRatio,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          );

                          if (_halfPageMode) {
                            const pageGap = 20.0;
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                final viewW = constraints.maxWidth;
                                final pageH = viewW / _imageAspectRatio;
                                final totalH = pageH * 2 + pageGap;
                                final scrollY = _halfPageOffset == 1 ? totalH / 4 : 0.0;

                                Widget buildPageStack(Uint8List imgBytes, List<Stroke> strokes) => SizedBox(
                                  width: viewW,
                                  height: pageH,
                                  child: Stack(
                                    children: [
                                      Image.memory(imgBytes, width: viewW, height: pageH, fit: BoxFit.fill),
                                      Positioned.fill(
                                        child: CustomPaint(
                                          size: Size(viewW, pageH),
                                          painter: DrawingCanvasPainter(
                                            strokes: strokes,
                                            currentPoints: _livePoints,
                                            currentColor: _liveColor,
                                            currentThickness: _liveThickness,
                                            imageAspectRatio: _imageAspectRatio,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );

                                return ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.topCenter,
                                    maxHeight: totalH,
                                    maxWidth: viewW,
                                    child: Transform.translate(
                                      offset: Offset(0, -scrollY),
                                      child: Column(
                                        children: [
                                          buildPageStack(_pageImageBytes!, _strokes),
                                          SizedBox(height: pageGap),
                                          if (_nextPageImageBytes != null)
                                            buildPageStack(_nextPageImageBytes!, _nextPageStrokes),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }

                          return pageContent;
                        }),
                      ),
                    ),
                    // Bottom bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.black54,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_currentPage + 1} / $_totalPages',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
