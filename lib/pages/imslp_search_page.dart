import 'package:flutter/material.dart';
import '../services/imslp_service.dart';

enum _SearchMode { composer, work, instrumentation }

class ImslpSearchPage extends StatefulWidget {
  const ImslpSearchPage({super.key});

  @override
  State<ImslpSearchPage> createState() => _ImslpSearchPageState();
}

class _ImslpSearchPageState extends State<ImslpSearchPage> {
  final _service = ImslpService();
  final _searchController = TextEditingController();
  _SearchMode _mode = _SearchMode.work;

  List<ImslpResult> _results = [];
  List<String> _categories = [];
  String? _selectedCategory;
  bool _isLoading = false;
  bool _isDownloading = false;
  String? _error;

  @override
  void dispose() {
    _searchController.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
      _results = [];
      _categories = [];
      _selectedCategory = null;
    });

    try {
      switch (_mode) {
        case _SearchMode.composer:
          _results = await _service.searchWorks(query, limit: 50);
        case _SearchMode.work:
          _results = await _service.searchWorks(query, limit: 50);
        case _SearchMode.instrumentation:
          _categories =
              await _service.searchInstrumentCategories(query);
      }
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _onCategoryTap(String category) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedCategory = category;
      _results = [];
    });

    try {
      _results = await _service.getCategoryWorks(category, limit: 50);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _onWorkTap(ImslpResult work) async {
    // Show bottom sheet with loading, then files
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (ctx) => _WorkFilesSheet(
        work: work,
        service: _service,
        onDownload: _downloadAndOpen,
      ),
    );
  }

  Future<void> _downloadAndOpen(ImslpFileInfo file) async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    // Show download snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              ),
              SizedBox(width: 12),
              Text('Téléchargement en cours...'),
            ],
          ),
          duration: Duration(seconds: 30),
        ),
      );
    }

    try {
      final path = await _service.downloadPdf(file.url, file.displayName);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Pop the bottom sheet if still showing
        Navigator.of(context).popUntil((route) => route.isFirst);
        // Return the downloaded file path to the caller
        Navigator.of(context).pop(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Erreur: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) setState(() => _isDownloading = false);
  }

  String _categoryDisplayName(String category) {
    return category.replaceFirst('Category:', '');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('Recherche IMSLP',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: _searchHint,
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _categories = [];
                            _selectedCategory = null;
                            _error = null;
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[850],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _onSearch(),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Mode selector chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildModeChip('Compositeur', _SearchMode.composer),
                const SizedBox(width: 8),
                _buildModeChip('Œuvre', _SearchMode.work),
                const SizedBox(width: 8),
                _buildModeChip('Instrumentation', _SearchMode.instrumentation),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Back to categories button (when viewing category works)
          if (_selectedCategory != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _selectedCategory = null;
                    _results = [];
                  });
                },
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back,
                        color: Colors.lightBlueAccent, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _categoryDisplayName(_selectedCategory!),
                        style: const TextStyle(
                            color: Colors.lightBlueAccent, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const Divider(color: Colors.white12, height: 1),

          // Content area
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  String get _searchHint {
    switch (_mode) {
      case _SearchMode.composer:
        return 'Nom du compositeur...';
      case _SearchMode.work:
        return 'Titre de l\'œuvre...';
      case _SearchMode.instrumentation:
        return 'Instrument (piano, violin, flute...)';
    }
  }

  Widget _buildModeChip(String label, _SearchMode mode) {
    final selected = _mode == mode;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12,
          color: selected ? Colors.black : Colors.white70)),
      selected: selected,
      selectedColor: Colors.lightBlueAccent,
      backgroundColor: Colors.grey[800],
      onSelected: (_) {
        setState(() {
          _mode = mode;
          _results = [];
          _categories = [];
          _selectedCategory = null;
          _error = null;
        });
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _onSearch,
                child: const Text('Réessayer',
                    style: TextStyle(color: Colors.lightBlueAccent)),
              ),
            ],
          ),
        ),
      );
    }

    // Instrumentation mode: show categories if no category selected
    if (_mode == _SearchMode.instrumentation &&
        _selectedCategory == null) {
      if (_categories.isEmpty) {
        return _buildEmptyState();
      }
      return ListView.separated(
        itemCount: _categories.length,
        separatorBuilder: (_, __) =>
            const Divider(color: Colors.white12, height: 1),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          return ListTile(
            leading:
                const Icon(Icons.category, color: Colors.lightBlueAccent),
            title: Text(
              _categoryDisplayName(cat),
              style: const TextStyle(color: Colors.white),
            ),
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white38),
            onTap: () => _onCategoryTap(cat),
          );
        },
      );
    }

    // Work results
    if (_results.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Colors.white12, height: 1),
      itemBuilder: (context, index) {
        final result = _results[index];
        return ListTile(
          leading: const Icon(Icons.music_note, color: Colors.white54),
          title: Text(
            result.workName,
            style: const TextStyle(color: Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: result.composerName.isNotEmpty
              ? Text(
                  result.composerName,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12),
                )
              : (result.snippet != null
                  ? Text(
                      result.snippet!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null),
          trailing:
              const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: () => _onWorkTap(result),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasQuery ? Icons.search_off : Icons.library_music,
            color: Colors.white24,
            size: 64,
          ),
          const SizedBox(height: 12),
          Text(
            hasQuery
                ? 'Aucun résultat'
                : 'Recherchez des partitions sur IMSLP',
            style: const TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

class _WorkFilesSheet extends StatefulWidget {
  final ImslpResult work;
  final ImslpService service;
  final Future<void> Function(ImslpFileInfo) onDownload;

  const _WorkFilesSheet({
    required this.work,
    required this.service,
    required this.onDownload,
  });

  @override
  State<_WorkFilesSheet> createState() => _WorkFilesSheetState();
}

class _WorkFilesSheetState extends State<_WorkFilesSheet> {
  List<ImslpFileInfo>? _files;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    try {
      final files = await widget.service.getWorkFiles(widget.work.title);
      if (mounted) {
        setState(() {
          _files = files;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.work.workName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (widget.work.composerName.isNotEmpty)
                    Text(
                      widget.work.composerName,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 14),
                    ),
                ],
              ),
            ),

            const Divider(color: Colors.white12),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(_error!,
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center),
                          ),
                        )
                      : _files == null || _files!.isEmpty
                          ? const Center(
                              child: Text(
                                'Aucun fichier PDF disponible',
                                style: TextStyle(color: Colors.white38),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollController,
                              itemCount: _files!.length,
                              separatorBuilder: (_, __) => const Divider(
                                  color: Colors.white12, height: 1),
                              itemBuilder: (context, index) {
                                final file = _files![index];
                                return ListTile(
                                  leading: const Icon(
                                      Icons.picture_as_pdf,
                                      color: Colors.red),
                                  title: Text(
                                    file.displayName,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.download,
                                        color: Colors.lightBlueAccent),
                                    onPressed: () =>
                                        widget.onDownload(file),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        );
      },
    );
  }
}
