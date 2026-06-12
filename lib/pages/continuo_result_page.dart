import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../continuo/models/chord.dart';
import '../continuo/models/score.dart';
import '../continuo/services/figured_bass_interpreter.dart';
import '../widgets/score_viewer.dart';

class ContinuoResultPage extends StatefulWidget {
  final Score score;
  final String musicXml;
  final String sourceFileName;

  const ContinuoResultPage({
    super.key,
    required this.score,
    required this.musicXml,
    required this.sourceFileName,
  });

  @override
  State<ContinuoResultPage> createState() => _ContinuoResultPageState();
}

class _ContinuoResultPageState extends State<ContinuoResultPage> {
  String? _savedPath;
  late final List<_ChordRef> _chordIndex;

  @override
  void initState() {
    super.initState();
    _chordIndex = _buildChordIndex();
  }

  List<_ChordRef> _buildChordIndex() {
    final refs = <_ChordRef>[];
    for (final m in widget.score.measures) {
      for (var i = 0; i < m.realizedChords.length; i++) {
        refs.add(_ChordRef(
          chord: m.realizedChords[i],
          measureNum: m.number,
          noteIndex: i,
        ));
      }
    }
    return refs;
  }

  void _onScoreElementTap(String elementId) {
    // Parse chord-N or bass-N from the xml:id
    final match = RegExp(r'^(?:chord|bass)-(\d+)$').firstMatch(elementId);
    if (match == null) return;

    final idx = int.parse(match.group(1)!);
    if (idx < 0 || idx >= _chordIndex.length) return;

    final ref = _chordIndex[idx];
    if (ref.chord.bass.isRest) return;
    _showChordInspector(ref.chord, ref.measureNum, ref.noteIndex);
  }

  Future<void> _exportMusicXml() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final baseName = widget.sourceFileName.replaceAll(
          RegExp(r'\.(xml|musicxml|mxl)$', caseSensitive: false), '');
      final outPath = '${dir.path}/leggio/${baseName}_realise.musicxml';
      final outFile = File(outPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(widget.musicXml);

      setState(() => _savedPath = outPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exporté: $outPath'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur d\'export: $e')),
        );
      }
    }
  }

  void _showChordInspector(Chord chord, int measureNum, int noteIndex) {
    final trace = chord.decisionTrace;
    if (trace.isEmpty) return;

    final info = trace[0];
    final scaleDeg = info['scaleDegree'];
    final motionIn = info['motionIn'] ?? '';
    final figSrc = info['figuresSource'] ?? '';
    final steps = info['steps'] as List? ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Text(
                  chord.chordSymbol.isNotEmpty ? chord.chordSymbol : '—',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mesure $measureNum, note ${noteIndex + 1}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      Text(
                        '${chord.bass.step}${chord.bass.octave}'
                        '  ·  degré $scaleDeg  ·  $motionIn',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Figures source chip
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  label: Text(
                    figSrc == 'file'
                        ? 'Chiffrage du fichier'
                        : 'Chiffrage calculé',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor: figSrc == 'file'
                      ? Colors.green[800]
                      : Colors.indigo[700],
                  labelStyle: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Figures & voices
            Text(
              'Chiffres: ${chord.figures.map((f) => f.toString()).join(' ')}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Voix: ${chord.upperVoices.map((n) => '${n.step}${n.octave}').join(' — ')}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const Divider(color: Colors.white24, height: 24),

            // Decision trace
            const Text('Trace de décision',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...steps.map<Widget>((step) {
              if (step is Map<String, dynamic>) {
                return _buildTraceRowFromMap(step);
              }
              return const SizedBox.shrink();
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTraceRowFromMap(Map<String, dynamic> step) {
    final test = step['test'] as String? ?? '';
    final passed = step['passed'] as bool? ?? false;
    final isDecision = step['isDecision'] as bool? ?? false;
    final rule = step['rule'] as String?;
    final source = step['source'] as String?;

    // Look up historical citations for this rule
    final citations =
        rule != null ? FiguredBassInterpreter.ruleCitations(rule) : <RuleCitation>[];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isDecision
                    ? Icons.check_circle
                    : passed
                        ? Icons.arrow_forward
                        : Icons.close,
                size: 16,
                color: isDecision
                    ? Colors.green
                    : passed
                        ? Colors.white38
                        : Colors.red[300],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      test,
                      style: TextStyle(
                        color: isDecision ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight:
                            isDecision ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    if (rule != null)
                      Text(rule,
                          style: const TextStyle(
                              color: Colors.lightBlueAccent, fontSize: 11)),
                    if (source != null)
                      Text(source,
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            ],
          ),
          // Historical citations
          if (citations.isNotEmpty && isDecision)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 4),
              child: Column(
                children: citations.map((c) => _buildCitationCard(c)).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCitationCard(RuleCitation citation) {
    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        iconColor: Colors.white38,
        collapsedIconColor: Colors.white38,
        title: Text(
          citation.author,
          style: const TextStyle(
              color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          citation.ref,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          // Original text
          if (citation.text.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                citation.lang == 'fr' ? '« ${citation.text} »' : citation.text,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontStyle:
                      citation.lang != 'en' ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          // Translation
          if (citation.translation.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                citation.translation,
                style:
                    const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          // Full reference
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              citation.ref,
              style: const TextStyle(
                  color: Colors.white30,
                  fontSize: 10,
                  fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: Text(widget.score.title ?? 'Réalisation'),
        actions: [
          IconButton(
            onPressed: _exportMusicXml,
            icon: const Icon(Icons.save_alt),
            tooltip: 'Exporter MusicXML',
          ),
          IconButton(
            onPressed: () => _showChordList(context),
            icon: const Icon(Icons.list_alt),
            tooltip: 'Accords',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ScoreViewer(
              musicXml: widget.musicXml,
              onElementTap: _onScoreElementTap,
            ),
          ),
          Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${widget.score.tonic()} '
                  '${widget.score.keyMode == "minor" ? "mineur" : "majeur"}'
                  '  ·  ${widget.score.measures.length} mesures',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const Spacer(),
                if (_savedPath != null)
                  const Icon(Icons.check, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Text(
                  'Toucher une note pour inspecter',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showChordList(BuildContext context) {
    final chords =
        _chordIndex.where((r) => !r.chord.bass.isRest).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${chords.length} accords',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                itemCount: chords.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final ref = chords[index];
                  final c = ref.chord;
                  final voices = c.upperVoices
                      .map((n) => '${n.step}${n.octave}')
                      .join(' ');
                  return ListTile(
                    dense: true,
                    leading: Text(
                      c.chordSymbol.isNotEmpty ? c.chordSymbol : '—',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    title: Text(
                      '${c.bass.step}${c.bass.octave}  →  $voices',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13),
                    ),
                    subtitle: Text(
                      'Mesure ${ref.measureNum}',
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                    trailing: const Icon(Icons.info_outline,
                        color: Colors.white38),
                    onTap: () {
                      Navigator.of(context).pop();
                      _showChordInspector(
                          c, ref.measureNum, ref.noteIndex);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChordRef {
  final Chord chord;
  final int measureNum;
  final int noteIndex;

  const _ChordRef({
    required this.chord,
    required this.measureNum,
    required this.noteIndex,
  });
}
