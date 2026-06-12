import 'package:flutter/material.dart';

import '../models/imslp_models.dart';
import '../services/imslp_db_search_service.dart';
import '../services/imslp_service.dart';

class ImslpWorkDetailPage extends StatefulWidget {
  final ImslpWork work;
  final ImslpDbSearchService searchService;
  final ImslpService imslpService;

  const ImslpWorkDetailPage({
    super.key,
    required this.work,
    required this.searchService,
    required this.imslpService,
  });

  @override
  State<ImslpWorkDetailPage> createState() => _ImslpWorkDetailPageState();
}

class _ImslpWorkDetailPageState extends State<ImslpWorkDetailPage> {
  List<ImslpEdition>? _editions;
  List<ImslpFileInfo>? _onlineFiles;
  bool _isLoadingEditions = true;
  bool _isLoadingOnline = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _loadEditions();
  }

  Future<void> _loadEditions() async {
    try {
      final editions =
          await widget.searchService.findEditions(widget.work.id);
      if (mounted) {
        setState(() {
          _editions = editions;
          _isLoadingEditions = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingEditions = false);
    }
  }

  Future<void> _loadOnlineFiles() async {
    setState(() => _isLoadingOnline = true);
    try {
      final files =
          await widget.imslpService.getWorkFiles(widget.work.imslpId);
      if (mounted) {
        setState(() {
          _onlineFiles = files;
          _isLoadingOnline = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingOnline = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString().replaceFirst("Exception: ", "")}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadFile(ImslpFileInfo file) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

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
      final path =
          await widget.imslpService.downloadPdf(file.url, file.displayName);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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

  @override
  Widget build(BuildContext context) {
    final w = widget.work;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: Text(w.composer,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(w.displayTitle,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(w.composer,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 15)),
          const SizedBox(height: 16),

          _buildMetadata(),

          const SizedBox(height: 24),

          // Editions from local DB
          const Text('Éditions (base locale)',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_isLoadingEditions)
            const Center(child: CircularProgressIndicator())
          else if (_editions == null || _editions!.isEmpty)
            const Text('Aucune édition dans la base locale',
                style: TextStyle(color: Colors.white38, fontSize: 13))
          else
            ..._editions!.map(_buildEditionTile),

          const SizedBox(height: 24),

          // Online files (fetch from IMSLP)
          Row(
            children: [
              const Expanded(
                child: Text('Fichiers IMSLP (en ligne)',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ),
              if (_onlineFiles == null && !_isLoadingOnline)
                TextButton.icon(
                  onPressed: _loadOnlineFiles,
                  icon: const Icon(Icons.cloud_download,
                      color: Colors.lightBlueAccent, size: 18),
                  label: const Text('Charger',
                      style: TextStyle(
                          color: Colors.lightBlueAccent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isLoadingOnline)
            const Center(child: CircularProgressIndicator())
          else if (_onlineFiles != null)
            ..._onlineFiles!.map(_buildFileTile),
        ],
      ),
    );
  }

  Widget _buildMetadata() {
    final w = widget.work;
    final items = <MapEntry<String, String>>[];

    if (w.yearComposed != null) {
      items.add(MapEntry('Composé', w.yearComposed!));
    }
    if (w.instrumentation != null) {
      items.add(MapEntry('Instrumentation', w.instrumentation!));
    }
    if (w.workKey != null) items.add(MapEntry('Tonalité', w.workKey!));
    if (w.pieceStyle != null) items.add(MapEntry('Style', w.pieceStyle!));
    if (w.language != null) items.add(MapEntry('Langue', w.language!));
    if (w.averageDuration != null) {
      items.add(MapEntry('Durée', w.averageDuration!));
    }
    if (w.dedication != null) {
      items.add(MapEntry('Dédicace', w.dedication!));
    }
    if (w.firstPerformance != null) {
      items.add(MapEntry('Première', w.firstPerformance!));
    }
    if (w.librettist != null) {
      items.add(MapEntry('Librettiste', w.librettist!));
    }
    if (w.movements != null) {
      items.add(MapEntry('Mouvements', w.movements!));
    }
    if (w.genreCats != null) items.add(MapEntry('Genres', w.genreCats!));

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: items
            .map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(e.key,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 12)),
                      ),
                      Expanded(
                        child: Text(e.value,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildEditionTile(ImslpEdition edition) {
    return ListTile(
      dense: true,
      leading: Icon(
        edition.imageType == 'Manuscript'
            ? Icons.edit_note
            : Icons.picture_as_pdf,
        color: edition.imageType == 'Manuscript'
            ? Colors.amber
            : Colors.red,
        size: 20,
      ),
      title: Text(
        edition.url ?? 'Édition #${edition.id}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: edition.imageType != null
          ? Text(edition.imageType!,
              style:
                  const TextStyle(color: Colors.white38, fontSize: 11))
          : null,
    );
  }

  Widget _buildFileTile(ImslpFileInfo file) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
      title: Text(
        file.displayName,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        icon: const Icon(Icons.download, color: Colors.lightBlueAccent),
        onPressed: _isDownloading ? null : () => _downloadFile(file),
      ),
    );
  }
}
