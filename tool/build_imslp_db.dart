import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart';

const _apiBase = 'https://imslp.org/imslpscripts/API.ISCR.php'
    '?account=worklist/disclaimer=accepted/sort=id/retformat=json';

void main() async {
  final dbPath = 'assets/db/imslp.db';
  final file = File(dbPath);
  if (file.existsSync()) file.deleteSync();

  final db = sqlite3.open(dbPath);
  _createSchema(db);

  stdout.writeln('Fetching IMSLP catalog...');

  // Sync composers (type=1)
  final composerCount = await _syncType(db, 1);
  stdout.writeln('Composers: $composerCount');

  // Sync works (type=2)
  final workCount = await _syncType(db, 2);
  stdout.writeln('Works: $workCount');

  // Rebuild FTS index
  stdout.writeln('Building full-text search index...');
  db.execute("INSERT INTO imslp_work_fts(imslp_work_fts) VALUES('rebuild')");

  // Compact
  stdout.writeln('Compacting database...');
  db.execute('VACUUM');

  db.dispose();

  final size = File(dbPath).lengthSync();
  stdout.writeln('Done: ${(size / 1024 / 1024).toStringAsFixed(1)} MB');
}

void _createSchema(Database db) {
  db.execute('PRAGMA journal_mode = OFF');
  db.execute('PRAGMA synchronous = OFF');

  db.execute('''
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
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_composer_name ON imslp_composer(name)');

  db.execute('''
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
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_work_composer ON imslp_work(composer)');
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_work_page_id ON imslp_work(page_id)');
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_work_style ON imslp_work(piece_style)');
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_work_year ON imslp_work(year_composed_int)');

  db.execute('''
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

  db.execute('''
    CREATE TABLE IF NOT EXISTS imslp_edition (
      id INTEGER PRIMARY KEY,
      work_id INTEGER NOT NULL,
      page_id INTEGER NOT NULL,
      image_type TEXT,
      url TEXT
    )
  ''');
  db.execute(
      'CREATE INDEX IF NOT EXISTS idx_edition_work ON imslp_edition(work_id)');
}

Future<int> _syncType(Database db, int type) async {
  int start = 0;
  int total = 0;
  final now = DateTime.now().toIso8601String();

  final insertComposer = type == 1
      ? db.prepare(
          'INSERT OR IGNORE INTO imslp_composer '
          '(imslp_id, name, permlink, synced_at) VALUES (?, ?, ?, ?)')
      : null;
  final insertWork = type == 2
      ? db.prepare(
          'INSERT OR IGNORE INTO imslp_work '
          '(imslp_id, title, composer, catalog_number, page_id, permlink, synced_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)')
      : null;

  while (true) {
    final uri = Uri.parse('$_apiBase/type=$type/start=$start');
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      stderr.writeln('API error ${response.statusCode} at start=$start');
      break;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    var count = 0;

    db.execute('BEGIN');
    for (final key in data.keys) {
      if (int.tryParse(key) == null) continue;
      final entry = data[key];
      if (entry is! Map<String, dynamic>) continue;

      if (type == 1 && entry['type'] == '1') {
        final id = entry['id'] as String? ?? '';
        final name = id.startsWith('Category:') ? id.substring(9) : id;
        insertComposer!.execute([
          id,
          name,
          entry['permlink'] as String? ?? '',
          now,
        ]);
        count++;
      } else if (type == 2 && entry['type'] == '2') {
        final iv = entry['intvals'];
        if (iv is! Map<String, dynamic>) continue;
        insertWork!.execute([
          entry['id'] as String? ?? '',
          iv['worktitle'] as String? ?? '',
          iv['composer'] as String? ?? '',
          iv['icatno'] as String? ?? '',
          int.tryParse(iv['pageid']?.toString() ?? '') ?? 0,
          entry['permlink'] as String? ?? '',
          now,
        ]);
        count++;
      }
    }
    db.execute('COMMIT');

    total += count;
    stdout.write('\r  ${type == 1 ? "Composers" : "Works"}: $total');

    if (count < 300) break;
    start += count;

    await Future.delayed(const Duration(milliseconds: 200));
  }

  stdout.writeln();
  insertComposer?.dispose();
  insertWork?.dispose();
  return total;
}
