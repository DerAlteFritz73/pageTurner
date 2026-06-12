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

    return openDatabase(path, version: _dbVersion);
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
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _createSchema(db);
      },
    );
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
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
