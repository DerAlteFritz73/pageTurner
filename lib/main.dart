import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const PdfRotateApp());
}

class PdfRotateApp extends StatelessWidget {
  const PdfRotateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Rotate',
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

class _PdfViewerPageState extends State<PdfViewerPage> {
  PdfDocument? _document;
  PdfPageImage? _pageImage;
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoading = false;
  String? _errorMessage;
  int _rotation = 1; // 0=0°, 1=90°, 2=180°, 3=270° (défaut: 90°)

  @override
  void dispose() {
    _document?.close();
    super.dispose();
  }

  Future<void> _pickAndOpenPdf() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => RotatedBox(
        quarterTurns: _rotation,
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

    if (choice == null) return;

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _document?.close();
      final document = await PdfDocument.openFile(path);

      setState(() {
        _document = document;
        _totalPages = document.pagesCount;
        _currentPage = 0;
      });

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

    setState(() {
      _isLoading = true;
    });

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

    // For 90° and 270° rotations, use horizontal layout with controls on the side
    if (_rotation == 1) {
      // 90° clockwise - controls on left (visual bottom when reading rotated content)
      return Row(
        children: [
          controls,
          content,
        ],
      );
    } else if (_rotation == 3) {
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
          quarterTurns: _rotation,
          child: const Text(
            'Aucun PDF sélectionné',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: RotatedBox(
          quarterTurns: _rotation,
          child: Image.memory(
            _pageImage!.bytes,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final isVertical = _rotation == 1 || _rotation == 3;

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
        icon: const Icon(Icons.rotate_right),
        color: Colors.white,
        tooltip: '${_rotation * 90}°',
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
