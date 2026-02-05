import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  List<Stroke> _strokes = [];
  int _currentPage = 0;
  int _totalPages = 0;
  int _rotation = 0;

  @override
  void initState() {
    super.initState();
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
          if (data['pageImageBase64'] != null) {
            _pageImageBytes =
                base64Decode(data['pageImageBase64'] as String);
          }
          _strokes = (data['strokes'] as List)
              .map((s) => Stroke.fromJson(Map<String, dynamic>.from(s as Map)))
              .toList();
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
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _pageImageBytes == null
          ? const Center(
              child: Text(
                'En attente du PDF...',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            )
          : Stack(
              children: [
                Center(
                  child: RotatedBox(
                    quarterTurns: _rotation,
                    child: Stack(
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
                                  currentPoints: const [],
                                  currentColor: Colors.transparent,
                                  currentThickness: 0,
                                  rotation: _rotation,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Page counter overlay
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentPage + 1} / $_totalPages',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
