import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdfx/pdfx.dart';

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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        await _openPdf(result.files.single.path!);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur lors de la sélection: $e';
      });
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
