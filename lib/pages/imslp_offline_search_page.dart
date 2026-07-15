import 'package:flutter/material.dart';

import '../models/imslp_models.dart';
import '../services/imslp_database_service.dart';
import '../services/imslp_db_search_service.dart';
import '../services/imslp_service.dart';
import '../widgets/imslp_filter_panel.dart';
import 'imslp_work_detail_page.dart';
import 'imslp_composer_page.dart';

class ImslpOfflineSearchPage extends StatefulWidget {
  const ImslpOfflineSearchPage({super.key});

  @override
  State<ImslpOfflineSearchPage> createState() => _ImslpOfflineSearchPageState();
}

class _ImslpOfflineSearchPageState extends State<ImslpOfflineSearchPage> {
  final _dbService = ImslpDatabaseService();
  late final ImslpDbSearchService _searchService;
  final _imslpService = ImslpService();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  SearchResult _result = SearchResult.empty();
  WorkFilters _filters = const WorkFilters();
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _error;
  int _currentPage = 1;
  static const _perPage = 30;

  List<String> _availableStyles = [];
  List<String> _availableLanguages = [];
  List<String> _availableKeys = [];

  // DB sync/download state
  bool _dbAvailable = true;
  bool _isSyncing = false;
  int _syncCount = 0;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String? _downloadError;
  final _urlController = TextEditingController(text: 'https://android.kreilos.fr/imslp.db');

  @override
  void initState() {
    super.initState();
    _searchService = ImslpDbSearchService(_dbService);
    _scrollController.addListener(_onScroll);
    _checkDbAvailability();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _urlController.dispose();
    _imslpService.dispose();
    _dbService.close();
    super.dispose();
  }

  Future<void> _checkDbAvailability() async {
    final available = await _dbService.isAvailable;
    if (mounted) {
      setState(() => _dbAvailable = available);
      if (available) _loadFilterOptions();
    }
  }

  Future<void> _syncFromImslp() async {
    setState(() {
      _isSyncing = true;
      _syncCount = 0;
      _downloadError = null;
    });

    try {
      await _dbService.syncFromApi(
        onProgress: (count) {
          if (mounted) setState(() => _syncCount = count);
        },
      );

      if (mounted) {
        final available = await _dbService.isAvailable;
        setState(() {
          _dbAvailable = available;
          _isSyncing = false;
        });
        if (available) {
          _searchService = ImslpDbSearchService(_dbService);
          _loadFilterOptions();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadError = 'Erreur: $e';
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _downloadDb() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _downloadError = null;
    });

    try {
      await _dbService.downloadFrom(
        url,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      // Reopen the database and check
      await _dbService.close();
      final available = await _dbService.isAvailable;

      if (mounted) {
        setState(() {
          _dbAvailable = available;
          _isDownloading = false;
        });
        if (available) {
          _searchService = ImslpDbSearchService(_dbService);
          _loadFilterOptions();
        } else {
          setState(() =>
              _downloadError = 'Base téléchargée mais vide ou invalide');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadError = 'Erreur: $e';
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _loadFilterOptions() async {
    try {
      final styles = await _searchService.findDistinctStyles();
      final languages = await _searchService.findDistinctLanguages();
      final keys = await _searchService.findDistinctKeys();
      if (mounted) {
        setState(() {
          _availableStyles = styles;
          _availableLanguages = languages;
          _availableKeys = keys;
        });
      }
    } catch (_) {}
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _currentPage < _result.pages) {
      _loadMore();
    }
  }

  Future<void> _onSearch() async {
    _currentPage = 1;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _searchService.searchByQuery(
        _searchController.text.trim(),
        _filters,
        page: 1,
        perPage: _perPage,
      );
      if (mounted) {
        setState(() {
          _result = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _result.pages) return;
    setState(() => _isLoadingMore = true);

    try {
      _currentPage++;
      final more = await _searchService.searchByQuery(
        _searchController.text.trim(),
        _filters,
        page: _currentPage,
        perPage: _perPage,
      );
      if (mounted) {
        setState(() {
          _result = SearchResult(
            works: [..._result.works, ...more.works],
            composerMatches: _result.composerMatches,
            total: _result.total,
            pages: _result.pages,
            mode: _result.mode,
          );
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      _currentPage--;
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _onComposerTap(ComposerMatch composer) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImslpComposerPage(
          composerName: composer.name,
          searchService: _searchService,
          imslpService: _imslpService,
        ),
      ),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _onWorkTap(ImslpWork work) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImslpWorkDetailPage(
          work: work,
          searchService: _searchService,
          imslpService: _imslpService,
        ),
      ),
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('IMSLP', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_result.total > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_result.total} résultats',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Compositeur, titre, numéro de catalogue...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon:
                            const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _result = SearchResult.empty();
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

          ImslpFilterPanel(
            filters: _filters,
            onChanged: (f) {
              setState(() => _filters = f);
              if (_searchController.text.trim().isNotEmpty || !f.isEmpty) {
                _onSearch();
              }
            },
            availableStyles: _availableStyles,
            availableLanguages: _availableLanguages,
            availableKeys: _availableKeys,
          ),

          const Divider(color: Colors.white12, height: 1),

          Expanded(child: _buildContent()),
        ],
      ),
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

    if (_result.mode == 'empty') {
      return _buildEmptyState();
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (_result.composerMatches.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text('Compositeurs',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _result.composerMatches.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final c = _result.composerMatches[i];
                      return ActionChip(
                        label: Text('${c.name} (${c.workCount})',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                        backgroundColor: Colors.grey[800],
                        side: const BorderSide(color: Colors.white24),
                        onPressed: () => _onComposerTap(c),
                      );
                    },
                  ),
                ),
                const Divider(color: Colors.white12, height: 16),
              ],
            ),
          ),

        if (_result.works.isNotEmpty)
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= _result.works.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final work = _result.works[index];
                return Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.music_note,
                          color: Colors.white54),
                      title: Text(
                        work.displayTitle,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(work.composer,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                          if (work.instrumentation != null)
                            Text(work.instrumentation!,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (work.yearComposed != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(work.yearComposed!,
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 11)),
                            ),
                          const Icon(Icons.chevron_right,
                              color: Colors.white38),
                        ],
                      ),
                      onTap: () => _onWorkTap(work),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                  ],
                );
              },
              childCount:
                  _result.works.length + (_isLoadingMore ? 1 : 0),
            ),
          ),

        if (_result.works.isEmpty && _result.composerMatches.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off,
                      color: Colors.white24, size: 64),
                  const SizedBox(height: 12),
                  const Text('Aucun résultat',
                      style: TextStyle(color: Colors.white38)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    if (!_dbAvailable) {
      return _buildDbSetup();
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.library_music, color: Colors.white24, size: 64),
          const SizedBox(height: 12),
          const Text('Recherchez des partitions',
              style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 4),
          FutureBuilder<int>(
            future: _dbService.workCount,
            builder: (_, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              return Text(
                '${snap.data} œuvres dans la base',
                style:
                    const TextStyle(color: Colors.white24, fontSize: 12),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDbSetup() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_download, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Base IMSLP non disponible',
              style: TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Téléchargez la base de données SQLite\n'
              'pour rechercher des partitions hors ligne.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            if (_isDownloading) ...[
              LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                backgroundColor: Colors.white12,
                color: Colors.lightBlueAccent,
              ),
              const SizedBox(height: 8),
              Text(
                _downloadProgress > 0
                    ? '${(_downloadProgress * 100).toStringAsFixed(0)} %'
                    : 'Téléchargement…',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ] else if (_isSyncing) ...[
              const LinearProgressIndicator(
                backgroundColor: Colors.white12,
                color: Colors.lightBlueAccent,
              ),
              const SizedBox(height: 8),
              Text(
                '$_syncCount œuvres synchronisées…',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _dbService.cancelSync();
                  setState(() => _isSyncing = false);
                },
                child: const Text('Annuler',
                    style: TextStyle(color: Colors.white54)),
              ),
            ] else ...[
              TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'URL de la base SQLite',
                  labelStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _urlController.text.trim().isNotEmpty
                    ? _downloadDb
                    : null,
                icon: const Icon(Icons.download),
                label: const Text('Télécharger'),
                style: FilledButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              ExpansionTile(
                title: const Text('Synchroniser depuis IMSLP',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
                iconColor: Colors.white38,
                collapsedIconColor: Colors.white38,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        const Text(
                          'Télécharge le catalogue directement depuis '
                          'imslp.org. Nécessite une connexion internet '
                          'et peut prendre plusieurs minutes.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _syncFromImslp,
                          icon: const Icon(Icons.sync),
                          label: const Text('Synchroniser'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],

            if (_downloadError != null) ...[
              const SizedBox(height: 12),
              Text(
                _downloadError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
