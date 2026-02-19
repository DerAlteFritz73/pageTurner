import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

import 'models/annotation.dart';
import 'services/display_manager_service.dart';
import 'widgets/drawing_canvas.dart';
import 'widgets/presentation_display.dart';

final _theme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);

Route<dynamic> _generateRoute(RouteSettings settings) {
  switch (settings.name) {
    case 'presentation':
      return MaterialPageRoute(
        builder: (_) => const PresentationDisplayScreen(),
      );
    default:
      return MaterialPageRoute(
        builder: (_) => const PdfViewerPage(),
      );
  }
}

void main() {
  runApp(MaterialApp(
    title: 'Leggio',
    debugShowCheckedModeBanner: false,
    theme: _theme,
    onGenerateRoute: _generateRoute,
    initialRoute: '/',
  ));
}

@pragma('vm:entry-point')
void secondaryDisplayMain() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _theme,
    onGenerateRoute: _generateRoute,
    initialRoute: 'presentation',
  ));
}

enum _ActionType { addStroke, removeStroke }

class _AnnotationAction {
  final _ActionType type;
  final Stroke stroke;
  const _AnnotationAction(this.type, this.stroke);
}

class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({super.key});

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> with WidgetsBindingObserver {
  PdfDocument? _document;
  PdfPageImage? _pageImage;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoading = false;
  String? _errorMessage;
  int _rotation = 1; // 0=0°, 1=90°, 2=180°, 3=270° (défaut: 90°)

  // Secondary display state
  final DisplayManagerService _displayService = DisplayManagerService();
  bool _hasSecondaryDisplay = false;

  // Swipe / zoom / stylus state
  final TransformationController _transformationController = TransformationController();
  bool _isZoomed = false;
  bool _isStylusDrawing = false;

  // Annotation state
  String? _currentPdfPath;
  AnnotationData? _annotationData;
  bool _isEraserMode = false;

  // Half-page mode
  bool _halfPageMode = false;

  // Auto-crop
  bool _autoCrop = false;
  Rect? _cropRect; // normalized crop rect (0.0-1.0) for current page

  // Undo/redo stacks
  final List<_AnnotationAction> _undoStack = [];
  final List<_AnnotationAction> _redoStack = [];
  bool _isTextMode = false;
  Color _currentColor = Colors.red;
  double _currentThickness = 1.0;
  double _imageAspectRatio = 1.0;

  // Available colors and thickness options
  static const List<Color> _colorOptions = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.white,
  ];
  // Thickness range for the slider
  static const double _minThickness = 0.3;
  static const double _maxThickness = 8.0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addObserver(this);
    _transformationController.addListener(_onTransformChanged);
    _displayService.init(
      onDisplayStatusChanged: (hasDisplay) {
        setState(() {
          _hasSecondaryDisplay = hasDisplay;
        });
        if (hasDisplay && _pageImage != null) {
          _syncFullStateToPresentation();
        }
      },
    );
  }

  @override
  void dispose() {
    _displayService.dispose();
    _transformationController.removeListener(_onTransformChanged);
    _transformationController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _saveAnnotations();
    _document?.close();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.05;
    if (zoomed != _isZoomed) {
      setState(() {
        _isZoomed = zoomed;
      });
    }
  }

  Future<void> _syncFullStateToPresentation() async {
    if (!_hasSecondaryDisplay || _pageImage == null) return;
    await _displayService.sendFullSync(
      currentPage: _currentPage,
      totalPages: _totalPages,
      rotation: _rotation,
      pageImageBytes: _pageImage!.bytes,
      strokes: _currentPageStrokes,
      imageAspectRatio: _imageAspectRatio,
      halfPageMode: _halfPageMode,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveAnnotations();
    }
  }

  Future<void> _saveAnnotations() async {
    if (_annotationData != null) {
      try {
        await _annotationData!.save();
      } catch (e) {
        // Silently handle save errors
      }
    }
  }

  Future<void> _loadAnnotations() async {
    if (_currentPdfPath != null) {
      _annotationData = await AnnotationData.load(_currentPdfPath!);
      setState(() {});
    }
  }

  int get _effectiveRotation => _hasSecondaryDisplay ? 0 : _rotation;

  List<Stroke> get _currentPageStrokes {
    return _annotationData?.getStrokesForPage(_currentPage) ?? [];
  }

  void _onStrokeComplete(Stroke stroke) {
    if (_annotationData != null) {
      setState(() {
        _annotationData!.addStroke(stroke);
        _undoStack.add(_AnnotationAction(_ActionType.addStroke, stroke));
        _redoStack.clear();
      });
      _displayService.sendStrokeAdded(stroke);
    }
  }

  void _onStrokeErased(String strokeId) {
    if (_annotationData != null) {
      // Find the stroke before removing so we can undo later
      Stroke? erasedStroke;
      for (final strokes in _annotationData!.strokesByPage.values) {
        for (final s in strokes) {
          if (s.id == strokeId) {
            erasedStroke = s;
            break;
          }
        }
        if (erasedStroke != null) break;
      }
      setState(() {
        _annotationData!.removeStroke(strokeId);
        if (erasedStroke != null) {
          _undoStack.add(_AnnotationAction(_ActionType.removeStroke, erasedStroke));
          _redoStack.clear();
        }
      });
      _displayService.sendStrokeRemoved(strokeId);
    }
  }

  void _undo() {
    if (_undoStack.isEmpty || _annotationData == null) return;
    final action = _undoStack.removeLast();
    setState(() {
      switch (action.type) {
        case _ActionType.addStroke:
          _annotationData!.removeStroke(action.stroke.id);
          _displayService.sendStrokeRemoved(action.stroke.id);
        case _ActionType.removeStroke:
          _annotationData!.addStroke(action.stroke);
          _displayService.sendStrokeAdded(action.stroke);
      }
      _redoStack.add(action);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty || _annotationData == null) return;
    final action = _redoStack.removeLast();
    setState(() {
      switch (action.type) {
        case _ActionType.addStroke:
          _annotationData!.addStroke(action.stroke);
          _displayService.sendStrokeAdded(action.stroke);
        case _ActionType.removeStroke:
          _annotationData!.removeStroke(action.stroke.id);
          _displayService.sendStrokeRemoved(action.stroke.id);
      }
      _undoStack.add(action);
    });
  }

  void _toggleEraserMode() {
    setState(() {
      _isEraserMode = !_isEraserMode;
      if (_isEraserMode) _isTextMode = false;
    });
  }

  void _toggleTextMode() {
    setState(() {
      _isTextMode = !_isTextMode;
      if (_isTextMode) _isEraserMode = false;
    });
  }

  // Bookmark methods
  List<Bookmark> get _bookmarks => _annotationData?.bookmarks ?? [];

  void _showBookmarkMenu() {
    final pageBookmarks = _bookmarks
        .where((b) => b.pageIndex == _currentPage)
        .toList();
    final hasBookmarkOnPage = pageBookmarks.isNotEmpty;

    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Signets', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Add/remove bookmark for current page
                ListTile(
                  leading: Icon(
                    hasBookmarkOnPage ? Icons.bookmark_remove : Icons.bookmark_add,
                    color: hasBookmarkOnPage ? Colors.orange : Colors.white,
                  ),
                  title: Text(
                    hasBookmarkOnPage
                        ? 'Retirer le signet (p. ${_currentPage + 1})'
                        : 'Ajouter un signet (p. ${_currentPage + 1})',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    if (hasBookmarkOnPage) {
                      _removeBookmarksOnPage(_currentPage);
                    } else {
                      _showAddBookmarkDialog();
                    }
                  },
                ),
                if (_bookmarks.isNotEmpty) ...[
                  const Divider(color: Colors.white24),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Aller à...', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _bookmarks.length,
                      itemBuilder: (context, index) {
                        final bookmark = _bookmarks[index];
                        final isCurrent = bookmark.pageIndex == _currentPage;
                        return ListTile(
                          dense: true,
                          leading: Icon(Icons.bookmark, color: bookmark.color),
                          title: Text(
                            bookmark.label,
                            style: TextStyle(
                              color: isCurrent ? Colors.white : Colors.white70,
                              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            'Page ${bookmark.pageIndex + 1}',
                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.white38, size: 18),
                            onPressed: () {
                              setState(() => _annotationData?.removeBookmark(bookmark.id));
                              Navigator.of(context).pop();
                              _showBookmarkMenu(); // reopen to show updated list
                            },
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _goToPage(bookmark.pageIndex);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddBookmarkDialog() {
    final presetLabels = ['D.S.', 'D.C.', 'Coda', 'Fine', 'Segno', '\u{1D10B}', '\u{1D10C}'];
    String customLabel = '';

    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text('Signet — page ${_currentPage + 1}',
                style: const TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presetLabels.map((label) {
                    return ActionChip(
                      label: Text(label),
                      onPressed: () {
                        _addBookmark(label);
                        Navigator.of(context).pop();
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Texte libre...',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white),
                    ),
                  ),
                  onChanged: (v) => customLabel = v,
                  onSubmitted: (v) {
                    if (v.isNotEmpty) {
                      _addBookmark(v);
                      Navigator.of(context).pop();
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () {
                  if (customLabel.isNotEmpty) {
                    _addBookmark(customLabel);
                  } else {
                    _addBookmark('Page ${_currentPage + 1}');
                  }
                  Navigator.of(context).pop();
                },
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _addBookmark(String label) {
    if (_annotationData == null) return;
    final bookmark = Bookmark(pageIndex: _currentPage, label: label);
    setState(() => _annotationData!.addBookmark(bookmark));
  }

  void _removeBookmarksOnPage(int pageIndex) {
    if (_annotationData == null) return;
    setState(() {
      _annotationData!.bookmarks.removeWhere((b) => b.pageIndex == pageIndex);
    });
  }

  void _goToPage(int pageIndex) {
    if (pageIndex != _currentPage && pageIndex >= 0 && pageIndex < _totalPages) {
      _renderPage(pageIndex);
    }
  }

  // Text annotation methods
  List<TextAnnotation> get _currentPageTextAnnotations {
    return _annotationData?.getTextAnnotationsForPage(_currentPage) ?? [];
  }

  void _onTextAnnotationErased(String id) {
    if (_annotationData != null) {
      setState(() => _annotationData!.removeTextAnnotation(id));
    }
  }

  void _showTextInputDialog(Offset normalizedPosition) {
    String text = '';
    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Annotation texte', style: TextStyle(color: Colors.white)),
          content: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Texte...',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
              ),
            ),
            onChanged: (v) => text = v,
            onSubmitted: (v) {
              if (v.isNotEmpty) {
                _addTextAnnotation(v, normalizedPosition);
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                if (text.isNotEmpty) {
                  _addTextAnnotation(text, normalizedPosition);
                }
                Navigator.of(context).pop();
              },
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _addTextAnnotation(String text, Offset position) {
    if (_annotationData == null) return;
    final annotation = TextAnnotation(
      pageIndex: _currentPage,
      text: text,
      position: position,
      color: _currentColor,
    );
    setState(() => _annotationData!.addTextAnnotation(annotation));
  }

  void _showColorPicker() {
    double tempThickness = _currentThickness;
    Color tempColor = _currentColor;
    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Couleur & épaisseur', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Color swatches
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _colorOptions.map((color) {
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() => tempColor = color);
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tempColor == color
                                ? Colors.white
                                : Colors.white24,
                            width: tempColor == color ? 3 : 1,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                // Thickness preview line
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24, width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Container(
                      width: 160,
                      height: tempThickness.clamp(0.5, 48.0),
                      decoration: BoxDecoration(
                        color: tempColor,
                        borderRadius: BorderRadius.circular(tempThickness / 2),
                      ),
                    ),
                  ),
                ),
                // Thickness slider
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: tempColor,
                    thumbColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    overlayColor: tempColor.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: tempThickness,
                    min: _minThickness,
                    max: _maxThickness,
                    onChanged: (value) {
                      setDialogState(() => tempThickness = value);
                    },
                  ),
                ),
                Text(
                  tempThickness.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _currentColor = tempColor;
                    _currentThickness = tempThickness;
                  });
                  Navigator.of(context).pop();
                },
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showParamsMenu() {
    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Paramètres', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Cast status
              if (_hasSecondaryDisplay)
                ListTile(
                  leading: const Icon(Icons.cast_connected, color: Colors.greenAccent),
                  title: const Text('Écran externe connecté',
                      style: TextStyle(color: Colors.greenAccent)),
                ),
              if (_hasSecondaryDisplay)
                const Divider(color: Colors.white24),
              // Rotation
              ListTile(
                leading: Icon(
                  Icons.rotate_right,
                  color: _hasSecondaryDisplay ? Colors.lightBlueAccent : Colors.white,
                ),
                title: Text(
                  _hasSecondaryDisplay
                      ? 'Écran externe: ${_rotation * 90}°'
                      : 'Rotation: ${_rotation * 90}°',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _rotateRight();
                  Navigator.of(context).pop();
                },
              ),
              const Divider(color: Colors.white24),
              // Auto-crop
              SwitchListTile(
                secondary: const Icon(Icons.crop, color: Colors.white),
                title: const Text('Recadrage auto',
                    style: TextStyle(color: Colors.white)),
                value: _autoCrop,
                onChanged: (value) {
                  setState(() => _autoCrop = value);
                  Navigator.of(context).pop();
                  // Re-render to apply/remove crop
                  if (_document != null) _renderPage(_currentPage);
                },
                activeTrackColor: Colors.lightBlueAccent,
              ),
              // Half-page mode
              SwitchListTile(
                secondary: const Icon(Icons.vertical_split, color: Colors.white),
                title: const Text('Demi-page',
                    style: TextStyle(color: Colors.white)),
                value: _halfPageMode,
                onChanged: (value) {
                  setState(() => _halfPageMode = value);
                  Navigator.of(context).pop();
                },
                activeTrackColor: Colors.lightBlueAccent,
              ),
              const Divider(color: Colors.white24),
              // Debug info
              ExpansionTile(
                leading: const Icon(Icons.bug_report, color: Colors.white54),
                title: const Text('Debug écrans',
                    style: TextStyle(color: Colors.white54, fontSize: 14)),
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white54,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _displayService.debugStatus,
                      style: const TextStyle(
                        color: Colors.yellow,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearCurrentPage() {
    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Effacer les annotations',
              style: TextStyle(color: Colors.white)),
          content: const Text(
            'Effacer toutes les annotations de cette page ?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                if (_annotationData != null) {
                  setState(() {
                    _annotationData!.clearPage(_currentPage);
                  });
                  _displayService.sendStrokesCleared(_currentPage);
                }
                Navigator.of(context).pop();
              },
              child:
                  const Text('Effacer', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndOpenPdf() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Ouvrir un PDF', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Choisissez la source du fichier',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop('local'),
              icon: const Icon(Icons.phone_android),
              label: const Text('Local'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop('cloud'),
              icon: const Icon(Icons.cloud),
              label: const Text('Cloud'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    String? selectedPath;

    if (choice == 'local') {
      selectedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => FileBrowserPage(rotation: _rotation),
        ),
      );
    } else if (choice == 'cloud') {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (result != null && result.files.single.path != null) {
          selectedPath = result.files.single.path;
        }
      } catch (e) {
        setState(() {
          _errorMessage = 'Erreur lors de la sélection: $e';
        });
        return;
      }
    }

    if (selectedPath != null) {
      await _openPdf(selectedPath);
    }
  }

  Future<void> _openPdf(String path) async {
    // Save current annotations before switching PDFs
    await _saveAnnotations();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isEraserMode = false;
      _undoStack.clear();
      _redoStack.clear();
    });

    try {
      _document?.close();
      final document = await PdfDocument.openFile(path);

      setState(() {
        _document = document;
        _totalPages = document.pagesCount;
        _currentPage = 0;
        _currentPdfPath = path;
      });

      await _loadAnnotations();
      await _renderPage(0);
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de l\'ouverture: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _renderPage(int pageIndex) async {
    if (_document == null) return;

    // Save annotations when changing pages
    if (pageIndex != _currentPage) {
      await _saveAnnotations();
    }

    setState(() {
      _isLoading = true;
    });

    _transformationController.value = Matrix4.identity();

    try {
      final page = await _document!.getPage(pageIndex + 1);
      final pageImage = await page.render(
        width: page.width * 3,
        height: page.height * 3,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      final aspectRatio = page.width / page.height;
      await page.close();

      // Compute crop rect if auto-crop is enabled
      Rect? cropRect;
      if (_autoCrop && pageImage != null) {
        cropRect = await _computeCropRect(pageImage.bytes);
      }

      setState(() {
        _pageImage = pageImage;
        _currentPage = pageIndex;
        _imageAspectRatio = aspectRatio;
        _cropRect = cropRect;
        _isLoading = false;
      });

      _syncFullStateToPresentation();
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors du rendu: $e';
        _isLoading = false;
      });
    }
  }

  Future<Rect?> _computeCropRect(Uint8List pngBytes) async {
    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;

    final pixels = byteData.buffer.asUint8List();
    final w = image.width;
    final h = image.height;
    const threshold = 240; // near-white threshold

    bool isWhitePixel(int x, int y) {
      final i = (y * w + x) * 4;
      return pixels[i] >= threshold &&
          pixels[i + 1] >= threshold &&
          pixels[i + 2] >= threshold;
    }

    bool isRowWhite(int y) {
      for (int x = 0; x < w; x += 4) { // sample every 4th pixel for speed
        if (!isWhitePixel(x, y)) return false;
      }
      return true;
    }

    bool isColWhite(int x) {
      for (int y = 0; y < h; y += 4) {
        if (!isWhitePixel(x, y)) return false;
      }
      return true;
    }

    int top = 0, bottom = h - 1, left = 0, right = w - 1;
    while (top < h && isRowWhite(top)) { top++; }
    while (bottom > top && isRowWhite(bottom)) { bottom--; }
    while (left < w && isColWhite(left)) { left++; }
    while (right > left && isColWhite(right)) { right--; }

    // Add small padding (2% of dimensions)
    final padX = (w * 0.02).round();
    final padY = (h * 0.02).round();
    top = (top - padY).clamp(0, h - 1);
    bottom = (bottom + padY).clamp(0, h - 1);
    left = (left - padX).clamp(0, w - 1);
    right = (right + padX).clamp(0, w - 1);

    // Return normalized rect
    return Rect.fromLTRB(
      left / w,
      top / h,
      right / w,
      bottom / h,
    );
  }

  void _previousPage() {
    if (_currentPage > 0) _renderPage(_currentPage - 1);
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) _renderPage(_currentPage + 1);
  }

  void _rotateRight() {
    setState(() {
      _rotation = (_rotation + 1) % 4; // Cycle: 0 -> 1 -> 2 -> 3 -> 0
    });
    _syncFullStateToPresentation();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.space) {
      _nextPage();
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.pageUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      _previousPage();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: _buildLayout(),
        ),
      ),
    );
  }

  Widget _buildLayout() {
    final content = Expanded(child: _buildContent());
    final controls = _buildControls();

    // Controls always at the physical bottom to maximise PDF display width
    return Column(
      children: [
        content,
        controls,
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_pageImage == null) {
      return Center(
        child: RotatedBox(
          quarterTurns: _effectiveRotation,
          child: const Text(
            'Aucun PDF sélectionné',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    // Fingers always interact; stylus drawing disables pan/scale temporarily.
    final canSwipe = !_isStylusDrawing && !_isZoomed && _document != null;

    // Half-page mode: show top and bottom halves simultaneously in a 2-panel split.
    if (_halfPageMode) {
      Widget buildPanel(bool isTop) => Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelH = constraints.maxHeight;
            final panelW = constraints.maxWidth;
            return ClipRect(
              child: Align(
                alignment: isTop ? Alignment.topCenter : Alignment.bottomCenter,
                child: SizedBox(
                  width: panelW,
                  height: panelH * 2,
                  child: Stack(
                    children: [
                      Image.memory(_pageImage!.bytes, fit: BoxFit.contain),
                      Positioned.fill(
                        child: DrawingCanvas(
                          strokes: _currentPageStrokes,
                          textAnnotations: _currentPageTextAnnotations,
                          isEraserMode: _isEraserMode,
                          isTextMode: _isTextMode,
                          currentColor: _currentColor,
                          currentThickness: _currentThickness,
                          currentPageIndex: _currentPage,
                          imageAspectRatio: _imageAspectRatio,
                          onStrokeComplete: _onStrokeComplete,
                          onStrokeErased: _onStrokeErased,
                          onTextAnnotationErased: _onTextAnnotationErased,
                          onTextTap: _showTextInputDialog,
                          onStylusStateChanged: (isActive) {
                            if (_isStylusDrawing != isActive) {
                              setState(() => _isStylusDrawing = isActive);
                            }
                          },
                          onLivePointsChanged: _hasSecondaryDisplay
                              ? (points) {
                                  if (points.isEmpty) {
                                    _displayService.clearLiveStroke();
                                  } else {
                                    _displayService.sendLiveStroke(
                                      points: points,
                                      color: _currentColor,
                                      thickness: _currentThickness,
                                    );
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

      return GestureDetector(
        onHorizontalDragEnd: canSwipe
            ? (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -300) {
                  _nextPage();
                } else if (velocity > 300) {
                  _previousPage();
                }
              }
            : null,
        child: RotatedBox(
          quarterTurns: _effectiveRotation,
          child: Column(
            children: [
              buildPanel(true),
              Container(height: 1, color: Colors.white24),
              buildPanel(false),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: canSwipe
          ? (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -300) {
                _nextPage();
              } else if (velocity > 300) {
                _previousPage();
              }
            }
          : null,
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 0.5,
        maxScale: 10.0,
        panEnabled: !_isStylusDrawing && _isZoomed,
        scaleEnabled: !_isStylusDrawing,
        child: Center(
        child: RotatedBox(
          quarterTurns: _effectiveRotation,
          child: LayoutBuilder(
            builder: (context, constraints) {
              Widget pageContent = Stack(
                children: [
                  Image.memory(
                    _pageImage!.bytes,
                    fit: BoxFit.contain,
                  ),
                  Positioned.fill(
                    child: DrawingCanvas(
                      strokes: _currentPageStrokes,
                      textAnnotations: _currentPageTextAnnotations,
                      isEraserMode: _isEraserMode,
                      isTextMode: _isTextMode,
                      currentColor: _currentColor,
                      currentThickness: _currentThickness,
                      currentPageIndex: _currentPage,
                      imageAspectRatio: _imageAspectRatio,
                      onStrokeComplete: _onStrokeComplete,
                      onStrokeErased: _onStrokeErased,
                      onTextAnnotationErased: _onTextAnnotationErased,
                      onTextTap: _showTextInputDialog,
                      onStylusStateChanged: (isActive) {
                        if (_isStylusDrawing != isActive) {
                          setState(() => _isStylusDrawing = isActive);
                        }
                      },
                      onLivePointsChanged: _hasSecondaryDisplay
                          ? (points) {
                              if (points.isEmpty) {
                                _displayService.clearLiveStroke();
                              } else {
                                _displayService.sendLiveStroke(
                                  points: points,
                                  color: _currentColor,
                                  thickness: _currentThickness,
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                ],
              );

              if (_autoCrop && _cropRect != null) {
                final cr = _cropRect!;
                pageContent = ClipRect(
                  child: Align(
                    alignment: FractionalOffset(
                      cr.left / (1.0 - (cr.right - cr.left)),
                      cr.top / (1.0 - (cr.bottom - cr.top)),
                    ),
                    widthFactor: cr.right - cr.left,
                    heightFactor: cr.bottom - cr.top,
                    child: pageContent,
                  ),
                );
              }

              return pageContent;
            },
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildControls() {
    final effectiveRotation = _effectiveRotation;
    final isVertical = effectiveRotation == 1 || effectiveRotation == 3;

    final previousButton = IconButton(
      onPressed: _currentPage > 0 ? _previousPage : null,
      icon: Icon(isVertical ? Icons.arrow_upward : Icons.arrow_back),
      color: Colors.white,
    );

    final openButton = RotatedBox(
      quarterTurns: isVertical ? _rotation : 0,
      child: IconButton(
        onPressed: _pickAndOpenPdf,
        icon: const Icon(Icons.folder_open),
        color: Colors.white,
        tooltip: 'Ouvrir',
      ),
    );

    final paramsButton = RotatedBox(
      quarterTurns: isVertical ? _rotation : 0,
      child: IconButton(
        onPressed: _showParamsMenu,
        icon: const Icon(Icons.settings),
        color: Colors.white,
        tooltip: 'Paramètres',
      ),
    );

    final pageCounter = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: Text(
              '${_currentPage + 1} / $_totalPages',
              style: const TextStyle(color: Colors.white),
            ),
          )
        : const SizedBox.shrink();

    final nextButton = IconButton(
      onPressed: _currentPage < _totalPages - 1 ? _nextPage : null,
      icon: Icon(isVertical ? Icons.arrow_downward : Icons.arrow_forward),
      color: Colors.white,
    );

    // Annotation controls (only show when PDF is open)
    final colorButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _showColorPicker,
              icon: Icon(
                Icons.palette,
                color: _currentColor == Colors.black ? Colors.white : _currentColor,
              ),
              tooltip: 'Couleur',
            ),
          )
        : const SizedBox.shrink();

    final eraserButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _toggleEraserMode,
              icon: Icon(
                Icons.cleaning_services,
                color: _isEraserMode ? Colors.yellow : Colors.white,
              ),
              tooltip: 'Gomme',
            ),
          )
        : const SizedBox.shrink();

    final textButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _toggleTextMode,
              icon: Icon(
                Icons.text_fields,
                color: _isTextMode ? Colors.yellow : Colors.white,
              ),
              tooltip: 'Texte',
            ),
          )
        : const SizedBox.shrink();

    final undoButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _undoStack.isNotEmpty ? _undo : null,
              icon: const Icon(Icons.undo),
              color: Colors.white,
              tooltip: 'Annuler',
            ),
          )
        : const SizedBox.shrink();

    final redoButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _redoStack.isNotEmpty ? _redo : null,
              icon: const Icon(Icons.redo),
              color: Colors.white,
              tooltip: 'Rétablir',
            ),
          )
        : const SizedBox.shrink();

    final clearButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _clearCurrentPage,
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.white,
              ),
              tooltip: 'Effacer tout',
            ),
          )
        : const SizedBox.shrink();

    final bookmarkButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _showBookmarkMenu,
              icon: Icon(
                _bookmarks.any((b) => b.pageIndex == _currentPage)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: _bookmarks.any((b) => b.pageIndex == _currentPage)
                    ? Colors.orange
                    : Colors.white,
              ),
              tooltip: 'Signets',
            ),
          )
        : const SizedBox.shrink();

    final separator = _document != null
        ? Container(
            width: 1,
            height: 24,
            color: Colors.white38,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          )
        : const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      color: Colors.black54,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            previousButton,
            const SizedBox(width: 8),
            openButton,
            const SizedBox(width: 8),
            paramsButton,
            const SizedBox(width: 8),
            pageCounter,
            const SizedBox(width: 8),
            nextButton,
            if (_document != null) ...[
              separator,
              colorButton,
              eraserButton,
              textButton,
              undoButton,
              redoButton,
              clearButton,
              bookmarkButton,
            ],
          ],
        ),
      ),
    );
  }
}

// Custom File Browser Page
class FileBrowserPage extends StatefulWidget {
  final int rotation;

  const FileBrowserPage({super.key, required this.rotation});

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  Directory? _currentDirectory;
  List<FileSystemEntity> _items = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoad();
  }

  Future<void> _requestPermissionAndLoad() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Request storage permission
      PermissionStatus status;

      if (Platform.isAndroid) {
        // For Android 11+ (API 30+), we need MANAGE_EXTERNAL_STORAGE
        // For older versions, READ_EXTERNAL_STORAGE is sufficient
        status = await Permission.manageExternalStorage.request();
        if (!status.isGranted) {
          status = await Permission.storage.request();
        }
      } else {
        status = await Permission.storage.request();
      }

      if (status.isGranted || status.isLimited) {
        _permissionGranted = true;
        await _navigateToDirectory(_getInitialDirectory());
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _errorMessage = 'Permission refusée. Veuillez autoriser l\'accès au stockage dans les paramètres.';
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Permission de stockage requise pour parcourir les fichiers.';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: $e';
        _isLoading = false;
      });
    }
  }

  Directory _getInitialDirectory() {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0');
    } else if (Platform.isWindows) {
      return Directory('C:\\');
    } else {
      return Directory('/');
    }
  }

  Future<void> _navigateToDirectory(Directory directory) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final items = await directory.list().toList();

      // Sort: directories first, then files, both alphabetically
      items.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

      // Filter: show directories and PDF files only
      final filteredItems = items.where((item) {
        if (item is Directory) {
          // Hide hidden directories
          final name = item.path.split(Platform.pathSeparator).last;
          return !name.startsWith('.');
        } else if (item is File) {
          return item.path.toLowerCase().endsWith('.pdf');
        }
        return false;
      }).toList();

      setState(() {
        _currentDirectory = directory;
        _items = filteredItems;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Impossible d\'accéder à ce dossier: $e';
        _isLoading = false;
      });
    }
  }

  void _goUp() {
    if (_currentDirectory != null) {
      final parent = _currentDirectory!.parent;
      if (parent.path != _currentDirectory!.path) {
        _navigateToDirectory(parent);
      }
    }
  }

  void _onItemTap(FileSystemEntity item) {
    if (item is Directory) {
      _navigateToDirectory(item);
    } else if (item is File) {
      Navigator.of(context).pop(item.path);
    }
  }

  String _getItemName(FileSystemEntity item) {
    return item.path.split(Platform.pathSeparator).last;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: RotatedBox(
          quarterTurns: widget.rotation,
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(8),
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Annuler',
          ),
          IconButton(
            onPressed: _currentDirectory != null ? _goUp : null,
            icon: const Icon(Icons.arrow_upward, color: Colors.white),
            tooltip: 'Dossier parent',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentDirectory?.path ?? 'Sélectionner un PDF',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (!_permissionGranted)
                ElevatedButton(
                  onPressed: () => openAppSettings(),
                  child: const Text('Ouvrir les paramètres'),
                ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _requestPermissionAndLoad,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_items.isEmpty) {
      return const Center(
        child: Text(
          'Aucun fichier PDF dans ce dossier',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        final isDirectory = item is Directory;
        final name = _getItemName(item);

        return ListTile(
          leading: Icon(
            isDirectory ? Icons.folder : Icons.picture_as_pdf,
            color: isDirectory ? Colors.amber : Colors.red,
          ),
          title: Text(
            name,
            style: const TextStyle(color: Colors.white),
          ),
          onTap: () => _onItemTap(item),
        );
      },
    );
  }
}
