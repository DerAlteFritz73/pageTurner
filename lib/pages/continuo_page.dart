import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../continuo/services/continuo_realizer.dart';
import '../continuo/services/figured_bass_interpreter.dart';
import '../continuo/services/harmony_analyzer.dart';
import '../continuo/services/music_xml_parser.dart';
import '../continuo/services/music_xml_serializer.dart';
import '../continuo/services/voice_leading_engine.dart';
import 'continuo_result_page.dart';

class ContinuoPage extends StatefulWidget {
  const ContinuoPage({super.key});

  @override
  State<ContinuoPage> createState() => _ContinuoPageState();
}

class _ContinuoPageState extends State<ContinuoPage> {
  String? _filePath;
  String? _fileName;
  String? _xmlContent;
  int _numVoices = 4;
  bool _isProcessing = false;
  String? _error;

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'musicxml', 'mxl'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final content = await File(path).readAsString();
        setState(() {
          _filePath = path;
          _fileName = result.files.single.name;
          _xmlContent = content;
          _error = null;
        });
      }
    } catch (e) {
      setState(() => _error = 'Erreur de lecture: $e');
    }
  }

  Future<void> _realize() async {
    if (_xmlContent == null) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      final parser = MusicXmlParser();
      final score = parser.parse(_xmlContent!);

      final realizer = ContinuoRealizer(
        interpreter: const FiguredBassInterpreter(),
        analyzer: HarmonyAnalyzer(),
        voiceLeading: VoiceLeadingEngine(),
      );
      final realized = realizer.realize(score, numVoices: _numVoices);

      const serializer = MusicXmlSerializer();
      final outputXml = serializer.serialize(realized);

      if (!mounted) return;

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContinuoResultPage(
            score: realized,
            musicXml: outputXml,
            sourceFileName: _fileName ?? 'score',
          ),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Erreur de réalisation: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        title: const Text('Basse continue'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File picker card
            Card(
              color: Colors.grey[900],
              child: InkWell(
                onTap: _isProcessing ? null : _pickFile,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        _filePath != null
                            ? Icons.music_note
                            : Icons.file_open,
                        size: 48,
                        color: _filePath != null
                            ? Colors.lightBlueAccent
                            : Colors.white54,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _fileName ?? 'Choisir un fichier MusicXML',
                        style: TextStyle(
                          color: _filePath != null
                              ? Colors.white
                              : Colors.white54,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_filePath != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _filePath!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Score info (after parsing)
            if (_xmlContent != null) _buildScoreInfo(),

            const SizedBox(height: 24),

            // Voice count selector
            Card(
              color: Colors.grey[900],
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.white70),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Nombre de voix',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 3, label: Text('3')),
                        ButtonSegment(value: 4, label: Text('4')),
                      ],
                      selected: {_numVoices},
                      onSelectionChanged: _isProcessing
                          ? null
                          : (val) =>
                              setState(() => _numVoices = val.first),
                      style: ButtonStyle(
                        foregroundColor:
                            WidgetStateProperty.all(Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Realize button
            FilledButton.icon(
              onPressed:
                  _xmlContent != null && !_isProcessing ? _realize : null,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_fix_high),
              label: Text(
                _isProcessing ? 'Réalisation...' : 'Réaliser',
                style: const TextStyle(fontSize: 18),
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.deepPurple,
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreInfo() {
    try {
      final parser = MusicXmlParser();
      final score = parser.parse(_xmlContent!);
      final tonic = score.tonic();
      final mode = score.keyMode == 'minor' ? 'mineur' : 'majeur';
      final measures = score.measures.length;
      final bassCount = score.measures
          .fold<int>(0, (sum, m) => sum + m.bassNotes.length);

      return Card(
        color: Colors.grey[850],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (score.title != null)
                Text(
                  score.title!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
              if (score.composer != null)
                Text(score.composer!,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Text(
                '$tonic $mode  ·  $measures mesures  ·  $bassCount notes',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13),
              ),
              Text(
                '${score.beats}/${score.beatType}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }
}
