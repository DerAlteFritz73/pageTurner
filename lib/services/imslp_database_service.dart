import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class ImslpDatabaseService {
  static const _dbName = 'imslp.db';
  static const _dbVersion = 1;
  static const _assetPath = 'assets/db/$_dbName';

  Database? _db;
  bool _hasFts5 = false;

  bool get hasFts5 => _hasFts5;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<String> get _dbPath async {
    final dir = await getApplicationDocumentsDirectory();
    final leggioDir = Directory(p.join(dir.path, 'leggio'));
    if (!await leggioDir.exists()) {
      await leggioDir.create(recursive: true);
    }
    return p.join(leggioDir.path, _dbName);
  }

  Future<Database> _open() async {
    final path = await _dbPath;

    if (!await File(path).exists()) {
      final hasAsset = await _copyFromAssets(path);
      if (!hasAsset) {
        return _createEmpty(path);
      }
    }

    final db = await openDatabase(path, version: _dbVersion);
    _hasFts5 = await _checkFts5(db);
    return db;
  }

  Future<bool> _checkFts5(Database db) async {
    try {
      await db.rawQuery("SELECT * FROM imslp_work_fts WHERE imslp_work_fts MATCH 'test' LIMIT 0");
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _copyFromAssets(String destPath) async {
    try {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await File(destPath).writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Database> _createEmpty(String path) async {
    final db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
    _hasFts5 = await _checkFts5(db);
    return db;
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS imslp_composer (
        id INTEGER PRIMARY KEY,
        imslp_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        permlink TEXT NOT NULL,
        born_year INTEGER,
        died_year INTEGER,
        nationality TEXT,
        time_period TEXT,
        synced_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_composer_name ON imslp_composer(name)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS imslp_work (
        id INTEGER PRIMARY KEY,
        imslp_id TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        composer TEXT NOT NULL,
        catalog_number TEXT NOT NULL DEFAULT '',
        page_id INTEGER NOT NULL,
        permlink TEXT NOT NULL,
        work_key TEXT,
        instrumentation TEXT,
        piece_style TEXT,
        year_composed TEXT,
        year_composed_int INTEGER,
        year_published TEXT,
        tags TEXT,
        page_type TEXT,
        movements TEXT,
        genre_cats TEXT,
        language TEXT,
        alternative_title TEXT,
        average_duration TEXT,
        librettist TEXT,
        dedication TEXT,
        first_performance TEXT,
        composer_id INTEGER,
        duration_seconds INTEGER,
        first_perf_date TEXT,
        first_perf_location TEXT,
        files_json TEXT,
        detail_synced_at TEXT,
        synced_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_composer ON imslp_work(composer)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_page_id ON imslp_work(page_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_style ON imslp_work(piece_style)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_year ON imslp_work(year_composed_int)');

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS imslp_work_fts USING fts5(
          title,
          composer,
          catalog_number,
          alternative_title,
          instrumentation,
          tags,
          genre_cats,
          content='imslp_work',
          content_rowid='id'
        )
      ''');
    } catch (_) {
      // FTS5 not available on this device — search falls back to LIKE
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS imslp_edition (
        id INTEGER PRIMARY KEY,
        work_id INTEGER NOT NULL,
        page_id INTEGER NOT NULL,
        image_type TEXT,
        url TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_edition_work ON imslp_edition(work_id)');
  }

  Future<bool> get isAvailable async {
    try {
      final db = await database;
      final result =
          await db.rawQuery('SELECT COUNT(*) as cnt FROM imslp_work');
      return (result.first['cnt'] as int) > 0;
    } catch (_) {
      return false;
    }
  }

  Future<int> get workCount async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM imslp_work');
    return result.first['cnt'] as int;
  }

  Future<int> get composerCount async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM imslp_composer');
    return result.first['cnt'] as int;
  }

  Future<void> downloadFrom(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final path = await _dbPath;

    // Close any open connection before replacing the file
    await close();

    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);

    if (response.statusCode != 200) {
      throw HttpException(
        'Échec du téléchargement: ${response.statusCode}',
        uri: Uri.parse(url),
      );
    }

    final total = response.contentLength ?? -1;
    var received = 0;
    final sink = File(path).openWrite();

    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }

    await sink.close();

    // Rebuild FTS index for compatibility with device SQLite version
    await _rebuildFts(path);
  }

  Future<void> _rebuildFts(String path) async {
    final db = await openDatabase(path);
    try {
      await db.execute('DROP TABLE IF EXISTS imslp_work_fts');
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS imslp_work_fts USING fts5(
          title,
          composer,
          catalog_number,
          alternative_title,
          instrumentation,
          tags,
          genre_cats,
          content='imslp_work',
          content_rowid='id'
        )
      ''');
      await db.execute(
        "INSERT INTO imslp_work_fts(imslp_work_fts) VALUES('rebuild')",
      );
    } catch (_) {
      // FTS5 not available — search will use LIKE fallback
    } finally {
      await db.close();
    }
  }

  bool _cancelSync = false;

  void cancelSync() {
    _cancelSync = true;
  }

  Future<void> syncFromApi({
    void Function(int count)? onProgress,
  }) async {
    _cancelSync = false;
    final db = await database;
    final now = DateTime.now().toIso8601String();
    int start = 0;
    int totalInserted = 0;

    while (!_cancelSync) {
      final uri = Uri.parse(
        'https://imslp.org/imslpscripts/API.ISCR.php'
        '?account=worklist/disclaimer=accepted/sort=id/type=2'
        '/start=$start/retformat=json',
      );

      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw HttpException(
          'IMSLP API: ${response.statusCode}',
          uri: uri,
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      final entries = <Map<String, dynamic>>[];
      for (final key in data.keys) {
        if (int.tryParse(key) == null) continue;
        final value = data[key];
        if (value is Map<String, dynamic> && value['type'] == '2') {
          entries.add(value);
        }
      }

      if (entries.isEmpty) break;

      final batch = db.batch();
      for (final entry in entries) {
        final iv = entry['intvals'];
        if (iv is! Map<String, dynamic>) continue;
        batch.rawInsert(
          'INSERT OR IGNORE INTO imslp_work '
          '(imslp_id, title, composer, catalog_number, page_id, permlink, synced_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            entry['id'] as String? ?? '',
            iv['worktitle'] as String? ?? '',
            iv['composer'] as String? ?? '',
            iv['icatno'] as String? ?? '',
            int.tryParse(iv['pageid']?.toString() ?? '') ?? 0,
            entry['permlink'] as String? ?? '',
            now,
          ],
        );
      }
      await batch.commit(noResult: true);

      totalInserted += entries.length;
      onProgress?.call(totalInserted);

      start += entries.length;
      if (entries.length < 300) break;

      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (totalInserted > 0 && _hasFts5) {
      await db.execute(
        "INSERT INTO imslp_work_fts(imslp_work_fts) VALUES('rebuild')",
      );
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
