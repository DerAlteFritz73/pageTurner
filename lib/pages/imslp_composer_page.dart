import 'package:flutter/material.dart';

import '../models/imslp_models.dart';
import '../services/imslp_db_search_service.dart';
import '../services/imslp_service.dart';
import 'imslp_work_detail_page.dart';

class ImslpComposerPage extends StatefulWidget {
  final String composerName;
  final ImslpDbSearchService searchService;
  final ImslpService imslpService;

  const ImslpComposerPage({
    super.key,
    required this.composerName,
    required this.searchService,
    required this.imslpService,
  });

  @override
  State<ImslpComposerPage> createState() => _ImslpComposerPageState();
}

class _ImslpComposerPageState extends State<ImslpComposerPage> {
  ImslpComposer? _composer;
  List<ImslpWork> _works = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  int _totalPages = 0;
  int _totalWorks = 0;
  static const _perPage = 30;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _currentPage < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    try {
      final composer =
          await widget.searchService.findComposerByName(widget.composerName);
      final result = await widget.searchService.searchByComposer(
        widget.composerName,
        const WorkFilters(),
        page: 1,
        perPage: _perPage,
      );
      if (mounted) {
        setState(() {
          _composer = composer;
          _works = result.works;
          _totalPages = result.pages;
          _totalWorks = result.total;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _currentPage >= _totalPages) return;
    setState(() => _isLoadingMore = true);

    try {
      _currentPage++;
      final result = await widget.searchService.searchByComposer(
        widget.composerName,
        const WorkFilters(),
        page: _currentPage,
        perPage: _perPage,
      );
      if (mounted) {
        setState(() {
          _works = [..._works, ...result.works];
          _isLoadingMore = false;
        });
      }
    } catch (_) {
      _currentPage--;
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _onWorkTap(ImslpWork work) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => ImslpWorkDetailPage(
          work: work,
          searchService: widget.searchService,
          imslpService: widget.imslpService,
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
        title: Text(widget.composerName,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                if (_composer != null)
                  SliverToBoxAdapter(child: _buildComposerHeader()),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Œuvres ($_totalWorks)',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= _works.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child:
                              Center(child: CircularProgressIndicator()),
                        );
                      }
                      final work = _works[index];
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.music_note,
                                color: Colors.white54),
                            title: Text(
                              work.displayTitle,
                              style:
                                  const TextStyle(color: Colors.white),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: work.instrumentation != null
                                ? Text(work.instrumentation!,
                                    style: const TextStyle(
                                        color: Colors.white38,
                                        fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (work.yearComposed != null)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: Text(work.yearComposed!,
                                        style: const TextStyle(
                                            color: Colors.white38,
                                            fontSize: 11)),
                                  ),
                                const Icon(Icons.chevron_right,
                                    color: Colors.white38),
                              ],
                            ),
                            onTap: () => _onWorkTap(work),
                          ),
                          const Divider(
                              color: Colors.white12, height: 1),
                        ],
                      );
                    },
                    childCount:
                        _works.length + (_isLoadingMore ? 1 : 0),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildComposerHeader() {
    final c = _composer!;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          if (c.lifespan.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(c.lifespan,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 14)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              if (c.nationality != null)
                _infoChip(Icons.flag, c.nationality!),
              if (c.timePeriod != null)
                _infoChip(Icons.history, c.timePeriod!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white38, size: 14),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
