import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

class Stroke {
  final String id;
  final int pageIndex;
  final List<Offset> points;
  final Color color;
  final double thickness;
  final DateTime createdAt;

  Stroke({
    String? id,
    required this.pageIndex,
    required this.points,
    required this.color,
    required this.thickness,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    // Convert color to ARGB32 int (components are 0.0-1.0 doubles)
    final a = (color.a * 255).round();
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final colorValue = (a << 24) | (r << 16) | (g << 8) | b;
    return {
      'id': id,
      'pageIndex': pageIndex,
      'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
      'color': colorValue,
      'thickness': thickness,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] as String,
      pageIndex: json['pageIndex'] as int,
      points: (json['points'] as List)
          .map((p) => Offset(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ))
          .toList(),
      color: Color(json['color'] as int),
      thickness: (json['thickness'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Stroke copyWith({
    String? id,
    int? pageIndex,
    List<Offset>? points,
    Color? color,
    double? thickness,
    DateTime? createdAt,
  }) {
    return Stroke(
      id: id ?? this.id,
      pageIndex: pageIndex ?? this.pageIndex,
      points: points ?? this.points,
      color: color ?? this.color,
      thickness: thickness ?? this.thickness,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class Bookmark {
  final String id;
  final int pageIndex;
  final String label;
  final Color color;

  Bookmark({
    String? id,
    required this.pageIndex,
    required this.label,
    Color? color,
  })  : id = id ?? const Uuid().v4(),
        color = color ?? const Color(0xFFFFD700); // gold

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'label': label,
        'color': color.toARGB32(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        pageIndex: json['pageIndex'] as int,
        label: json['label'] as String,
        color: Color(json['color'] as int),
      );
}

class TextAnnotation {
  final String id;
  final int pageIndex;
  final String text;
  final Offset position; // normalized 0.0-1.0
  final double fontSize;
  final Color color;

  TextAnnotation({
    String? id,
    required this.pageIndex,
    required this.text,
    required this.position,
    this.fontSize = 14.0,
    Color? color,
  })  : id = id ?? const Uuid().v4(),
        color = color ?? const Color(0xFFFF0000);

  Map<String, dynamic> toJson() => {
        'id': id,
        'pageIndex': pageIndex,
        'text': text,
        'x': position.dx,
        'y': position.dy,
        'fontSize': fontSize,
        'color': color.toARGB32(),
      };

  factory TextAnnotation.fromJson(Map<String, dynamic> json) => TextAnnotation(
        id: json['id'] as String,
        pageIndex: json['pageIndex'] as int,
        text: json['text'] as String,
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
        color: Color(json['color'] as int),
      );
}

class AnnotationData {
  final String pdfPath;
  final Map<int, List<Stroke>> strokesByPage;
  final List<Bookmark> bookmarks;
  final Map<int, List<TextAnnotation>> textAnnotationsByPage;

  AnnotationData({
    required this.pdfPath,
    Map<int, List<Stroke>>? strokesByPage,
    List<Bookmark>? bookmarks,
    Map<int, List<TextAnnotation>>? textAnnotationsByPage,
  })  : strokesByPage = strokesByPage ?? {},
        bookmarks = bookmarks ?? [],
        textAnnotationsByPage = textAnnotationsByPage ?? {};

  List<Stroke> getStrokesForPage(int pageIndex) {
    return strokesByPage[pageIndex] ?? [];
  }

  void addStroke(Stroke stroke) {
    strokesByPage.putIfAbsent(stroke.pageIndex, () => []);
    strokesByPage[stroke.pageIndex]!.add(stroke);
  }

  void removeStroke(String strokeId) {
    for (final pageStrokes in strokesByPage.values) {
      pageStrokes.removeWhere((s) => s.id == strokeId);
    }
  }

  void clearPage(int pageIndex) {
    strokesByPage[pageIndex]?.clear();
    textAnnotationsByPage[pageIndex]?.clear();
  }

  void clearAll() {
    strokesByPage.clear();
    textAnnotationsByPage.clear();
  }

  // Bookmark methods
  void addBookmark(Bookmark bookmark) => bookmarks.add(bookmark);
  void removeBookmark(String id) => bookmarks.removeWhere((b) => b.id == id);

  // Text annotation methods
  List<TextAnnotation> getTextAnnotationsForPage(int pageIndex) {
    return textAnnotationsByPage[pageIndex] ?? [];
  }

  void addTextAnnotation(TextAnnotation annotation) {
    textAnnotationsByPage.putIfAbsent(annotation.pageIndex, () => []);
    textAnnotationsByPage[annotation.pageIndex]!.add(annotation);
  }

  void removeTextAnnotation(String id) {
    for (final annotations in textAnnotationsByPage.values) {
      annotations.removeWhere((a) => a.id == id);
    }
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> strokesJson = {};
    strokesByPage.forEach((pageIndex, strokes) {
      strokesJson[pageIndex.toString()] =
          strokes.map((s) => s.toJson()).toList();
    });
    final Map<String, dynamic> textAnnotationsJson = {};
    textAnnotationsByPage.forEach((pageIndex, annotations) {
      textAnnotationsJson[pageIndex.toString()] =
          annotations.map((a) => a.toJson()).toList();
    });
    return {
      'pdfPath': pdfPath,
      'strokesByPage': strokesJson,
      'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
      'textAnnotationsByPage': textAnnotationsJson,
    };
  }

  factory AnnotationData.fromJson(Map<String, dynamic> json) {
    final strokesJson = json['strokesByPage'] as Map<String, dynamic>? ?? {};
    final Map<int, List<Stroke>> strokesByPage = {};

    strokesJson.forEach((key, value) {
      final pageIndex = int.parse(key);
      final strokes = (value as List)
          .map((s) => Stroke.fromJson(s as Map<String, dynamic>))
          .toList();
      strokesByPage[pageIndex] = strokes;
    });

    final bookmarksList = (json['bookmarks'] as List?)
        ?.map((b) => Bookmark.fromJson(b as Map<String, dynamic>))
        .toList();

    final textAnnotationsJson =
        json['textAnnotationsByPage'] as Map<String, dynamic>? ?? {};
    final Map<int, List<TextAnnotation>> textAnnotationsByPage = {};
    textAnnotationsJson.forEach((key, value) {
      final pageIndex = int.parse(key);
      final annotations = (value as List)
          .map((a) => TextAnnotation.fromJson(a as Map<String, dynamic>))
          .toList();
      textAnnotationsByPage[pageIndex] = annotations;
    });

    return AnnotationData(
      pdfPath: json['pdfPath'] as String,
      strokesByPage: strokesByPage,
      bookmarks: bookmarksList,
      textAnnotationsByPage: textAnnotationsByPage,
    );
  }

  static String getAnnotationFilePath(String pdfPath) {
    return '$pdfPath.annotations.json';
  }

  static Future<String> getAnnotationFilePathWithFallback(String pdfPath) async {
    final sidecarPath = getAnnotationFilePath(pdfPath);

    // Try to write to the sidecar location first
    try {
      final sidecarFile = File(sidecarPath);
      final dir = sidecarFile.parent;
      if (await dir.exists()) {
        // Check if we can write to this directory
        final testFile = File(path.join(dir.path, '.write_test_${DateTime.now().millisecondsSinceEpoch}'));
        try {
          await testFile.writeAsString('test');
          await testFile.delete();
          return sidecarPath;
        } catch (_) {
          // Can't write to this directory, fall back to app documents
        }
      }
    } catch (_) {
      // Error checking sidecar path
    }

    // Fall back to a local annotations folder
    final appDir = Directory.current;
    final annotationsDir = Directory(path.join(appDir.path, 'annotations'));
    if (!await annotationsDir.exists()) {
      await annotationsDir.create(recursive: true);
    }

    final pdfFileName = path.basename(pdfPath);
    return path.join(annotationsDir.path, '$pdfFileName.annotations.json');
  }

  Future<void> save() async {
    final filePath = await getAnnotationFilePathWithFallback(pdfPath);
    final file = File(filePath);
    final jsonString = const JsonEncoder.withIndent('  ').convert(toJson());
    await file.writeAsString(jsonString);
  }

  static Future<AnnotationData> load(String pdfPath) async {
    // Try sidecar file first
    final sidecarPath = getAnnotationFilePath(pdfPath);
    File file = File(sidecarPath);

    if (!await file.exists()) {
      // Try fallback location
      final fallbackPath = await getAnnotationFilePathWithFallback(pdfPath);
      file = File(fallbackPath);
    }

    if (await file.exists()) {
      try {
        final jsonString = await file.readAsString();
        final json = jsonDecode(jsonString) as Map<String, dynamic>;
        return AnnotationData.fromJson(json);
      } catch (e) {
        // If file is corrupted, return empty annotations
        return AnnotationData(pdfPath: pdfPath);
      }
    }

    return AnnotationData(pdfPath: pdfPath);
  }
}
