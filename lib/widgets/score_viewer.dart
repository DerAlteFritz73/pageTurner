import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:verovio_flutter/verovio_flutter.dart';

class ScoreViewer extends StatefulWidget {
  final String musicXml;
  final void Function(String elementId)? onElementTap;

  const ScoreViewer({
    super.key,
    required this.musicXml,
    this.onElementTap,
  });

  @override
  State<ScoreViewer> createState() => _ScoreViewerState();
}

class _ScoreViewerState extends State<ScoreViewer> {
  VerovioAsyncService? _service;
  final List<String> _svgPages = [];
  final List<PageHitMap?> _hitMaps = [];
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initVerovio();
  }

  @override
  void didUpdateWidget(ScoreViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.musicXml != widget.musicXml) {
      _loadScore();
    }
  }

  @override
  void dispose() {
    _service?.dispose();
    super.dispose();
  }

  Future<void> _initVerovio() async {
    try {
      final resourcePath =
          await VerovioResourceManager.ensureVerovioAssetsReady();
      final service =
          await VerovioAsyncService.spawn(resourcePath: resourcePath);
      _service = service;
      await _loadScore();
    } catch (e) {
      setState(() {
        _error = 'Erreur d\'initialisation Verovio: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadScore() async {
    if (_service == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _svgPages.clear();
      _hitMaps.clear();
    });

    try {
      await _service!.loadData(widget.musicXml);
      final pageCount = await _service!.pageCount;

      for (var i = 1; i <= pageCount; i++) {
        if (widget.onElementTap != null) {
          try {
            final result = await _service!.renderPageWithHitMap(i);
            _svgPages.add(result.svg);
            _hitMaps.add(result.hitMap);
          } catch (_) {
            final svg = await _service!.renderToSvg(i);
            _svgPages.add(svg);
            _hitMaps.add(null);
          }
        } else {
          final svg = await _service!.renderToSvg(i);
          _svgPages.add(svg);
          _hitMaps.add(null);
        }
      }

      setState(() {
        _totalPages = pageCount;
        _currentPage = 0;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur de rendu: $e';
        _isLoading = false;
      });
    }
  }

  void _handleTap(TapUpDetails details, BoxConstraints constraints) {
    if (widget.onElementTap == null) return;
    final hitMap =
        _currentPage < _hitMaps.length ? _hitMaps[_currentPage] : null;
    if (hitMap == null) return;

    final viewBox = _parseViewBox(_svgPages[_currentPage]);
    if (viewBox == null) return;

    // Available space inside padding
    final availW = constraints.maxWidth - 16; // 8px padding each side
    final availH = constraints.maxHeight - 16;

    // BoxFit.contain scale
    final scaleX = viewBox.width / availW;
    final scaleY = viewBox.height / availH;
    final scale = scaleX > scaleY ? scaleX : scaleY;

    final renderedW = viewBox.width / scale;
    final renderedH = viewBox.height / scale;
    final offsetX = 8 + (availW - renderedW) / 2;
    final offsetY = 8 + (availH - renderedH) / 2;

    final vbX = (details.localPosition.dx - offsetX) * scale + viewBox.left;
    final vbY = (details.localPosition.dy - offsetY) * scale + viewBox.top;

    // Find smallest element containing the tap point
    String? bestId;
    double bestArea = double.infinity;

    for (final entry in hitMap.byId.entries) {
      final hit = entry.value;
      if (hit.bbox.contains(Offset(vbX, vbY))) {
        final area = hit.bbox.width * hit.bbox.height;
        if (area < bestArea) {
          bestArea = area;
          bestId = entry.key;
        }
      }
    }

    if (bestId != null) {
      widget.onElementTap!(bestId);
    }
  }

  Rect? _parseViewBox(String svg) {
    final match = RegExp(r'viewBox="([^"]*)"').firstMatch(svg);
    if (match == null) return null;
    final parts = match.group(1)!.split(RegExp(r'\s+'));
    if (parts.length != 4) return null;
    try {
      return Rect.fromLTWH(
        double.parse(parts[0]),
        double.parse(parts[1]),
        double.parse(parts[2]),
        double.parse(parts[3]),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Gravure en cours...',
                style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }

    if (_svgPages.isEmpty) {
      return const Center(
        child: Text('Aucune page', style: TextStyle(color: Colors.white70)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: LayoutBuilder(
              builder: (context, constraints) => GestureDetector(
                onTapUp: (details) => _handleTap(details, constraints),
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  height: double.infinity,
                  padding: const EdgeInsets.all(8),
                  child: SvgPicture.string(
                    _svgPages[_currentPage],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_totalPages > 1)
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentPage > 0
                      ? () => setState(() => _currentPage--)
                      : null,
                  icon:
                      const Icon(Icons.chevron_left, color: Colors.white),
                ),
                Text(
                  '${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(color: Colors.white),
                ),
                IconButton(
                  onPressed: _currentPage < _totalPages - 1
                      ? () => setState(() => _currentPage++)
                      : null,
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
