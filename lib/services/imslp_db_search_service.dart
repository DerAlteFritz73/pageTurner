import '../models/imslp_models.dart';
import 'imslp_database_service.dart';

class ImslpDbSearchService {
  final ImslpDatabaseService _dbService;

  ImslpDbSearchService(this._dbService);

  // ---------------------------------------------------------------------------
  // Instrumentation abbreviation map (ported from ImslpWorkRepository.php)
  // ---------------------------------------------------------------------------

  static const _abbrToLong = {
    'fl': 'flute',
    'flt': 'flute',
    'pic': 'piccolo',
    'ob': 'oboe',
    'ca': 'anglais',
    'cl': 'clarinet',
    'bn': 'bassoon',
    'fag': 'bassoon',
    'cbn': 'contrabassoon',
    'hn': 'horn',
    'cor': 'horn',
    'tp': 'trumpet',
    'tpt': 'trumpet',
    'tb': 'trombone',
    'tba': 'tuba',
    'vn': 'violin',
    'va': 'viola',
    'vc': 'cello',
    'cb': 'bass',
    'bc': 'continuo',
    'hpd': 'harpsichord',
    'cem': 'cembalo',
    'org': 'organ',
    'pf': 'piano',
    'pno': 'piano',
    'kbd': 'keyboard',
    'rec': 'recorder',
    'lute': 'lute',
    'gt': 'guitar',
    'vdg': 'gamba',
    'gam': 'gamba',
    'str': 'strings',
    'sop': 'soprano',
    'mez': 'mezzo',
    'alt': 'alto',
    'ten': 'tenor',
    'bar': 'baritone',
    'bas': 'bass',
  };

  // ---------------------------------------------------------------------------
  // Search by query (with auto composer detection)
  // ---------------------------------------------------------------------------

  Future<SearchResult> searchByQuery(
    String query,
    WorkFilters filters, {
    int page = 1,
    int perPage = 30,
  }) async {
    if (query.trim().isEmpty && filters.isEmpty) {
      return SearchResult.empty();
    }

    if (query.trim().isNotEmpty) {
      final composers = await findComposersLike(query, filters);
      if (composers.length == 1 &&
          composers.first.name.toLowerCase() == query.toLowerCase()) {
        return searchByComposer(composers.first.name, filters,
            page: page, perPage: perPage);
      }

      final total = await _countTitleSearch(query, filters);
      final works = await _titleSearch(query, filters, page, perPage);
      return SearchResult(
        works: works,
        composerMatches: composers,
        total: total,
        pages: (total / perPage).ceil(),
        mode: 'search',
      );
    }

    return searchByFilters(filters, page: page, perPage: perPage);
  }

  // ---------------------------------------------------------------------------
  // Search by composer
  // ---------------------------------------------------------------------------

  Future<SearchResult> searchByComposer(
    String composer,
    WorkFilters filters, {
    int page = 1,
    int perPage = 30,
  }) async {
    final db = await _dbService.database;
    final where = _buildFilterWhere(filters);
    final args = <dynamic>[composer, ...where.args];

    final countResult = await db.rawQuery(
      'SELECT COUNT(DISTINCT w.id) AS cnt FROM imslp_work w '
      '${where.joins} WHERE w.composer = ? ${where.clause}',
      args,
    );
    final total = countResult.first['cnt'] as int;

    final offset = (page - 1) * perPage;
    final rows = await db.rawQuery(
      'SELECT DISTINCT w.* FROM imslp_work w '
      '${where.joins} WHERE w.composer = ? ${where.clause} '
      'ORDER BY w.title LIMIT ? OFFSET ?',
      [...args, perPage, offset],
    );

    return SearchResult(
      works: rows.map(ImslpWork.fromMap).toList(),
      total: total,
      pages: (total / perPage).ceil(),
      mode: 'composer',
    );
  }

  // ---------------------------------------------------------------------------
  // Search by filters only
  // ---------------------------------------------------------------------------

  Future<SearchResult> searchByFilters(
    WorkFilters filters, {
    int page = 1,
    int perPage = 30,
  }) async {
    if (filters.isEmpty) return SearchResult.empty();

    final db = await _dbService.database;
    final where = _buildFilterWhere(filters);

    final countResult = await db.rawQuery(
      'SELECT COUNT(DISTINCT w.id) AS cnt FROM imslp_work w '
      '${where.joins} WHERE 1=1 ${where.clause}',
      where.args,
    );
    final total = countResult.first['cnt'] as int;

    final offset = (page - 1) * perPage;
    final rows = await db.rawQuery(
      'SELECT DISTINCT w.* FROM imslp_work w '
      '${where.joins} WHERE 1=1 ${where.clause} '
      'ORDER BY w.composer, w.title LIMIT ? OFFSET ?',
      [...where.args, perPage, offset],
    );

    return SearchResult(
      works: rows.map(ImslpWork.fromMap).toList(),
      total: total,
      pages: (total / perPage).ceil(),
      mode: 'filter',
    );
  }

  // ---------------------------------------------------------------------------
  // Composer search (for suggestion cards)
  // ---------------------------------------------------------------------------

  Future<List<ComposerMatch>> findComposersLike(
    String query,
    WorkFilters filters, {
    int limit = 20,
  }) async {
    final db = await _dbService.database;
    final where = _buildFilterWhere(filters);
    final likePattern = '%${_escapeLike(query)}%';

    final rows = await db.rawQuery(
      'SELECT w.composer AS name, COUNT(w.id) AS work_count '
      'FROM imslp_work w ${where.joins} '
      'WHERE w.composer LIKE ? ${where.clause} '
      'GROUP BY w.composer ORDER BY work_count DESC LIMIT ?',
      [likePattern, ...where.args, limit],
    );

    return rows
        .map((r) => ComposerMatch(
              name: r['name'] as String,
              workCount: r['work_count'] as int,
            ))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Composer detail
  // ---------------------------------------------------------------------------

  Future<ImslpComposer?> findComposerByName(String name) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT * FROM imslp_composer WHERE name = ? LIMIT 1',
      [name],
    );
    if (rows.isEmpty) return null;
    return ImslpComposer.fromMap(rows.first);
  }

  Future<List<ImslpComposer>> searchComposers(String query,
      {int limit = 20}) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT * FROM imslp_composer WHERE name LIKE ? ORDER BY name LIMIT ?',
      ['%${_escapeLike(query)}%', limit],
    );
    return rows.map(ImslpComposer.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Work detail + editions
  // ---------------------------------------------------------------------------

  Future<ImslpWork?> findWorkById(int id) async {
    final db = await _dbService.database;
    final rows =
        await db.rawQuery('SELECT * FROM imslp_work WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    return ImslpWork.fromMap(rows.first);
  }

  Future<List<ImslpEdition>> findEditions(int workId) async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT * FROM imslp_edition WHERE work_id = ? ORDER BY id',
      [workId],
    );
    return rows.map(ImslpEdition.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Distinct filter values (for filter panel dropdowns)
  // ---------------------------------------------------------------------------

  Future<List<String>> findDistinctStyles() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT piece_style FROM imslp_work '
      'WHERE piece_style IS NOT NULL AND piece_style != \'\' '
      'ORDER BY piece_style',
    );
    return rows.map((r) => r['piece_style'] as String).toList();
  }

  Future<List<String>> findDistinctLanguages() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT language FROM imslp_work '
      'WHERE language IS NOT NULL AND language != \'\' '
      'ORDER BY language',
    );
    return rows.map((r) => r['language'] as String).toList();
  }

  Future<List<String>> findDistinctKeys() async {
    final db = await _dbService.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT work_key FROM imslp_work '
      'WHERE work_key IS NOT NULL AND work_key != \'\' '
      'ORDER BY work_key',
    );
    return rows.map((r) => r['work_key'] as String).toList();
  }

  // ---------------------------------------------------------------------------
  // Private: title search via FTS5
  // ---------------------------------------------------------------------------

  Future<int> _countTitleSearch(String query, WorkFilters filters) async {
    final db = await _dbService.database;
    final where = _buildFilterWhere(filters);
    final ftsQuery = _dbService.hasFts5 ? _toFts5Query(query) : '';

    if (ftsQuery.isNotEmpty) {
      final rows = await db.rawQuery(
        'SELECT COUNT(DISTINCT w.id) AS cnt FROM imslp_work w '
        'JOIN imslp_work_fts ON w.id = imslp_work_fts.rowid '
        '${where.joins} '
        'WHERE imslp_work_fts MATCH ? ${where.clause}',
        [ftsQuery, ...where.args],
      );
      return rows.first['cnt'] as int;
    }

    final like = '%${_escapeLike(query)}%';
    final rows = await db.rawQuery(
      'SELECT COUNT(DISTINCT w.id) AS cnt FROM imslp_work w '
      '${where.joins} '
      'WHERE (w.title LIKE ? OR w.catalog_number LIKE ?) ${where.clause}',
      [like, like, ...where.args],
    );
    return rows.first['cnt'] as int;
  }

  Future<List<ImslpWork>> _titleSearch(
      String query, WorkFilters filters, int page, int perPage) async {
    final db = await _dbService.database;
    final where = _buildFilterWhere(filters);
    final offset = (page - 1) * perPage;
    final ftsQuery = _dbService.hasFts5 ? _toFts5Query(query) : '';

    if (ftsQuery.isNotEmpty) {
      final rows = await db.rawQuery(
        'SELECT DISTINCT w.* FROM imslp_work w '
        'JOIN imslp_work_fts ON w.id = imslp_work_fts.rowid '
        '${where.joins} '
        'WHERE imslp_work_fts MATCH ? ${where.clause} '
        'ORDER BY w.composer, w.title LIMIT ? OFFSET ?',
        [ftsQuery, ...where.args, perPage, offset],
      );
      return rows.map(ImslpWork.fromMap).toList();
    }

    final like = '%${_escapeLike(query)}%';
    final rows = await db.rawQuery(
      'SELECT DISTINCT w.* FROM imslp_work w '
      '${where.joins} '
      'WHERE (w.title LIKE ? OR w.catalog_number LIKE ?) ${where.clause} '
      'ORDER BY w.composer, w.title LIMIT ? OFFSET ?',
      [like, like, ...where.args, perPage, offset],
    );
    return rows.map(ImslpWork.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Private: FTS5 query builder
  // ---------------------------------------------------------------------------

  String _toFts5Query(String query) {
    final terms = query.trim().split(RegExp(r'\s+'));
    final valid = terms.where((t) => t.length >= 3).toList();
    if (valid.isEmpty) return '';

    return valid
        .map((t) => '${t.replaceAll(RegExp(r'[+\-><()"~*@]'), '')}*')
        .join(' AND ');
  }

  // ---------------------------------------------------------------------------
  // Private: filter WHERE clause builder
  // ---------------------------------------------------------------------------

  _WhereClause _buildFilterWhere(WorkFilters f) {
    final parts = <String>[];
    final args = <dynamic>[];
    var joins = '';

    if (f.instrumentation.isNotEmpty) {
      final expanded = _expandInstrumentation(f.instrumentation);
      if (expanded.isNotEmpty) {
        if (_dbService.hasFts5) {
          final ftsQuery = expanded.map((t) => '$t*').join(' AND ');
          parts.add(
            '(w.id IN (SELECT rowid FROM imslp_work_fts WHERE imslp_work_fts MATCH ?))',
          );
          args.add(ftsQuery);
        } else {
          for (final term in expanded) {
            parts.add('w.instrumentation LIKE ?');
            args.add('%${_escapeLike(term)}%');
          }
        }
      }
    }

    if (f.style.isNotEmpty) {
      parts.add('w.piece_style = ?');
      args.add(f.style);
    }

    if (f.genre.isNotEmpty) {
      parts.add('w.genre_cats LIKE ?');
      args.add('%${_escapeLike(f.genre)}%');
    }

    if (f.language.isNotEmpty) {
      parts.add('w.language LIKE ?');
      args.add('%${_escapeLike(f.language)}%');
    }

    if (f.key.isNotEmpty) {
      parts.add('w.work_key LIKE ?');
      args.add('%${_escapeLike(f.key)}%');
    }

    if (f.yearFrom != null) {
      parts.add(
        '(w.year_composed_int IS NOT NULL AND w.year_composed_int >= ?)',
      );
      args.add(f.yearFrom);
    }

    if (f.yearTo != null) {
      parts.add(
        '(w.year_composed_int IS NOT NULL AND w.year_composed_int <= ?)',
      );
      args.add(f.yearTo);
    }

    if (!f.includeManuscripts) {
      joins = 'JOIN imslp_edition e ON e.work_id = w.id '
          "AND e.image_type != 'Manuscript' ";
    }

    final clause =
        parts.isEmpty ? '' : 'AND ${parts.join(' AND ')}';
    return _WhereClause(clause: clause, args: args, joins: joins);
  }

  List<String> _expandInstrumentation(String input) {
    final normalised =
        input.trim().replaceAllMapped(RegExp(r'(\d+)\s+([a-z]{1,4})\b', caseSensitive: false),
            (m) => '${m[1]}${m[2]}');
    final tokens = normalised
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final expanded = <String>[];
    for (final token in tokens) {
      final key = token.replaceAll(RegExp(r'^\d+'), '').toLowerCase();
      final long = _abbrToLong[key];
      if (long != null && !expanded.contains(long)) {
        expanded.add(long);
      } else if (token.length >= 3) {
        expanded.add(token.toLowerCase());
      }
    }
    return expanded;
  }

  String _escapeLike(String s) => s
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_')
      .replaceAll(r'\', r'\\');
}

// ---------------------------------------------------------------------------
// Helper types
// ---------------------------------------------------------------------------

class _WhereClause {
  final String clause;
  final List<dynamic> args;
  final String joins;
  const _WhereClause({
    required this.clause,
    required this.args,
    required this.joins,
  });
}

class ComposerMatch {
  final String name;
  final int workCount;
  const ComposerMatch({required this.name, required this.workCount});
}

class SearchResult {
  final List<ImslpWork> works;
  final List<ComposerMatch> composerMatches;
  final int total;
  final int pages;
  final String mode;

  const SearchResult({
    required this.works,
    this.composerMatches = const [],
    required this.total,
    required this.pages,
    required this.mode,
  });

  factory SearchResult.empty() => const SearchResult(
        works: [],
        total: 0,
        pages: 0,
        mode: 'empty',
      );
}
