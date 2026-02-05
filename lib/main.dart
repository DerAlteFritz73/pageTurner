import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

import 'models/annotation.dart';
import 'services/display_manager_service.dart';
import 'widgets/drawing_canvas.dart';
import 'widgets/presentation_display.dart';

void main() {
  runApp(const LeggioApp());
}

@pragma('vm:entry-point')
void secondaryDisplayMain() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PresentationDisplayScreen(),
    ),
  );
}

class LeggioApp extends StatelessWidget {
  const LeggioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Leggio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PdfViewerPage(),
    );
  }
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

  // Swipe / zoom state
  final TransformationController _transformationController = TransformationController();
  bool _isZoomed = false;

  // Annotation state
  String? _currentPdfPath;
  AnnotationData? _annotationData;
  bool _isDrawingMode = false;
  bool _isEraserMode = false;
  Color _currentColor = Colors.red;
  double _currentThickness = 4.0;

  // Available colors and thickness options
  static const List<Color> _colorOptions = [
    Colors.black,
    Colors.red,
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
  ];
  static const List<double> _thicknessOptions = [2.0, 4.0, 8.0];

  @override
  void initState() {
    super.initState();
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
      });
      _displayService.sendStrokeAdded(stroke);
    }
  }

  void _onStrokeErased(String strokeId) {
    if (_annotationData != null) {
      setState(() {
        _annotationData!.removeStroke(strokeId);
      });
      _displayService.sendStrokeRemoved(strokeId);
    }
  }

  void _toggleDrawingMode() {
    setState(() {
      _isDrawingMode = !_isDrawingMode;
      if (_isDrawingMode) {
        _isEraserMode = false;
      }
    });
  }

  void _toggleEraserMode() {
    setState(() {
      _isEraserMode = !_isEraserMode;
      if (_isEraserMode) {
        _isDrawingMode = false;
      }
    });
  }

  void _showColorPicker() {
    showDialog(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _effectiveRotation,
        child: AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text('Couleur', style: TextStyle(color: Colors.white)),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _colorOptions.map((color) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _currentColor = color;
                  });
                  Navigator.of(context).pop();
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _currentColor == color
                          ? Colors.white
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _cycleThickness() {
    setState(() {
      final currentIndex = _thicknessOptions.indexOf(_currentThickness);
      final nextIndex = (currentIndex + 1) % _thicknessOptions.length;
      _currentThickness = _thicknessOptions[nextIndex];
    });
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
      _isDrawingMode = false;
      _isEraserMode = false;
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
        width: page.width * 2,
        height: page.height * 2,
        format: PdfPageImageFormat.png,
        backgroundColor: '#FFFFFF',
      );
      await page.close();

      setState(() {
        _pageImage = pageImage;
        _currentPage = pageIndex;
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

  void _previousPage() {
    if (_currentPage > 0) {
      _renderPage(_currentPage - 1);
    }
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _renderPage(_currentPage + 1);
    }
  }

  void _rotateRight() {
    setState(() {
      _rotation = (_rotation + 1) % 4; // Cycle: 0 -> 1 -> 2 -> 3 -> 0
    });
    _syncFullStateToPresentation();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _buildLayout(),
      ),
    );
  }

  Widget _buildLayout() {
    final content = Expanded(child: _buildContent());
    final controls = _buildControls();

    // When secondary display is connected, phone always uses portrait layout
    final effectiveRotation = _effectiveRotation;

    // For 90° and 270° rotations, use horizontal layout with controls on the side
    if (effectiveRotation == 1) {
      // 90° clockwise - controls on left (visual bottom when reading rotated content)
      return Row(
        children: [
          controls,
          content,
        ],
      );
    } else if (effectiveRotation == 3) {
      // 270° clockwise - controls on right (visual bottom when reading rotated content)
      return Row(
        children: [
          content,
          controls,
        ],
      );
    } else {
      // 0° or 180° - controls at physical bottom
      return Column(
        children: [
          content,
          controls,
        ],
      );
    }
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

    // Disable InteractiveViewer when in drawing/eraser mode
    final canInteract = !_isDrawingMode && !_isEraserMode;
    final canSwipe = canInteract && !_isZoomed && _document != null;

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
        maxScale: canInteract ? 4.0 : 1.0,
        panEnabled: canInteract && _isZoomed,
        scaleEnabled: canInteract,
        child: Center(
        child: RotatedBox(
          quarterTurns: _effectiveRotation,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: [
                  Image.memory(
                    _pageImage!.bytes,
                    fit: BoxFit.contain,
                  ),
                  Positioned.fill(
                    child: DrawingCanvas(
                      strokes: _currentPageStrokes,
                      isDrawingMode: _isDrawingMode,
                      isEraserMode: _isEraserMode,
                      currentColor: _currentColor,
                      currentThickness: _currentThickness,
                      currentPageIndex: _currentPage,
                      rotation: _effectiveRotation,
                      onStrokeComplete: _onStrokeComplete,
                      onStrokeErased: _onStrokeErased,
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

    final rotateButton = RotatedBox(
      quarterTurns: isVertical ? _rotation : 0,
      child: IconButton(
        onPressed: _rotateRight,
        icon: Icon(
          Icons.rotate_right,
          color: _hasSecondaryDisplay ? Colors.lightBlueAccent : Colors.white,
        ),
        tooltip: _hasSecondaryDisplay
            ? 'Écran externe: ${_rotation * 90}°'
            : '${_rotation * 90}°',
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
    final penButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _toggleDrawingMode,
              icon: Icon(
                Icons.edit,
                color: _isDrawingMode ? _currentColor : Colors.white,
              ),
              tooltip: 'Dessiner',
            ),
          )
        : const SizedBox.shrink();

    final colorButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _showColorPicker,
              icon: Icon(
                Icons.palette,
                color: _currentColor,
              ),
              tooltip: 'Couleur',
            ),
          )
        : const SizedBox.shrink();

    final thicknessButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _cycleThickness,
              icon: Icon(
                _currentThickness <= 2.0
                    ? Icons.line_weight
                    : _currentThickness <= 4.0
                        ? Icons.horizontal_rule
                        : Icons.maximize,
                color: Colors.white,
              ),
              tooltip: 'Épaisseur',
            ),
          )
        : const SizedBox.shrink();

    final eraserButton = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: IconButton(
              onPressed: _toggleEraserMode,
              icon: Icon(
                Icons.auto_fix_high,
                color: _isEraserMode ? Colors.yellow : Colors.white,
              ),
              tooltip: 'Gomme',
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

    final separator = _document != null
        ? RotatedBox(
            quarterTurns: isVertical ? _rotation : 0,
            child: Container(
              width: isVertical ? 24 : 1,
              height: isVertical ? 1 : 24,
              color: Colors.white38,
              margin: EdgeInsets.symmetric(
                horizontal: isVertical ? 0 : 8,
                vertical: isVertical ? 8 : 0,
              ),
            ),
          )
        : const SizedBox.shrink();

    if (isVertical) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: Colors.black54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            previousButton,
            const SizedBox(height: 8),
            openButton,
            const SizedBox(height: 8),
            rotateButton,
            const SizedBox(height: 8),
            pageCounter,
            const SizedBox(height: 8),
            nextButton,
            if (_document != null) ...[
              separator,
              penButton,
              const SizedBox(height: 4),
              colorButton,
              const SizedBox(height: 4),
              thicknessButton,
              const SizedBox(height: 4),
              eraserButton,
              const SizedBox(height: 4),
              clearButton,
            ],
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        color: Colors.black54,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            previousButton,
            const SizedBox(width: 8),
            openButton,
            const SizedBox(width: 8),
            rotateButton,
            const SizedBox(width: 8),
            pageCounter,
            const SizedBox(width: 8),
            nextButton,
            if (_document != null) ...[
              separator,
              penButton,
              colorButton,
              thicknessButton,
              eraserButton,
              clearButton,
            ],
          ],
        ),
      );
    }
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
