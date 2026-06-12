import 'dart:convert';

class ImslpComposer {
  final int id;
  final String imslpId;
  final String name;
  final String permlink;
  final int? bornYear;
  final int? diedYear;
  final String? nationality;
  final String? timePeriod;

  const ImslpComposer({
    required this.id,
    required this.imslpId,
    required this.name,
    required this.permlink,
    this.bornYear,
    this.diedYear,
    this.nationality,
    this.timePeriod,
  });

  factory ImslpComposer.fromMap(Map<String, dynamic> map) => ImslpComposer(
        id: map['id'] as int,
        imslpId: map['imslp_id'] as String,
        name: map['name'] as String,
        permlink: map['permlink'] as String,
        bornYear: map['born_year'] as int?,
        diedYear: map['died_year'] as int?,
        nationality: map['nationality'] as String?,
        timePeriod: map['time_period'] as String?,
      );

  String get lifespan {
    if (bornYear == null && diedYear == null) return '';
    return '(${bornYear ?? '?'}–${diedYear ?? '?'})';
  }
}

class ImslpWork {
  final int id;
  final String imslpId;
  final String title;
  final String composer;
  final String catalogNumber;
  final int pageId;
  final String permlink;
  final String? workKey;
  final String? instrumentation;
  final String? pieceStyle;
  final String? yearComposed;
  final int? yearComposedInt;
  final String? yearPublished;
  final String? tags;
  final String? pageType;
  final String? movements;
  final String? genreCats;
  final String? language;
  final String? alternativeTitle;
  final String? averageDuration;
  final String? librettist;
  final String? dedication;
  final String? firstPerformance;
  final int? composerId;
  final int? durationSeconds;
  final String? firstPerfDate;
  final String? firstPerfLocation;
  final List<Map<String, dynamic>>? filesJson;

  const ImslpWork({
    required this.id,
    required this.imslpId,
    required this.title,
    required this.composer,
    required this.catalogNumber,
    required this.pageId,
    required this.permlink,
    this.workKey,
    this.instrumentation,
    this.pieceStyle,
    this.yearComposed,
    this.yearComposedInt,
    this.yearPublished,
    this.tags,
    this.pageType,
    this.movements,
    this.genreCats,
    this.language,
    this.alternativeTitle,
    this.averageDuration,
    this.librettist,
    this.dedication,
    this.firstPerformance,
    this.composerId,
    this.durationSeconds,
    this.firstPerfDate,
    this.firstPerfLocation,
    this.filesJson,
  });

  factory ImslpWork.fromMap(Map<String, dynamic> map) {
    List<Map<String, dynamic>>? files;
    final raw = map['files_json'];
    if (raw is String && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        files = decoded.cast<Map<String, dynamic>>();
      }
    }

    return ImslpWork(
      id: map['id'] as int,
      imslpId: map['imslp_id'] as String,
      title: map['title'] as String,
      composer: map['composer'] as String,
      catalogNumber: map['catalog_number'] as String? ?? '',
      pageId: map['page_id'] as int,
      permlink: map['permlink'] as String,
      workKey: map['work_key'] as String?,
      instrumentation: map['instrumentation'] as String?,
      pieceStyle: map['piece_style'] as String?,
      yearComposed: map['year_composed'] as String?,
      yearComposedInt: map['year_composed_int'] as int?,
      yearPublished: map['year_published'] as String?,
      tags: map['tags'] as String?,
      pageType: map['page_type'] as String?,
      movements: map['movements'] as String?,
      genreCats: map['genre_cats'] as String?,
      language: map['language'] as String?,
      alternativeTitle: map['alternative_title'] as String?,
      averageDuration: map['average_duration'] as String?,
      librettist: map['librettist'] as String?,
      dedication: map['dedication'] as String?,
      firstPerformance: map['first_performance'] as String?,
      composerId: map['composer_id'] as int?,
      durationSeconds: map['duration_seconds'] as int?,
      firstPerfDate: map['first_perf_date'] as String?,
      firstPerfLocation: map['first_perf_location'] as String?,
      filesJson: files,
    );
  }

  bool get hasDetail => yearComposed != null || instrumentation != null;

  String get displayTitle {
    if (catalogNumber.isNotEmpty) return '$title, $catalogNumber';
    return title;
  }
}

class ImslpEdition {
  final int id;
  final int workId;
  final int pageId;
  final String? imageType;
  final String? url;

  const ImslpEdition({
    required this.id,
    required this.workId,
    required this.pageId,
    this.imageType,
    this.url,
  });

  factory ImslpEdition.fromMap(Map<String, dynamic> map) => ImslpEdition(
        id: map['id'] as int,
        workId: map['work_id'] as int,
        pageId: map['page_id'] as int,
        imageType: map['image_type'] as String?,
        url: map['url'] as String?,
      );
}

class WorkFilters {
  final String instrumentation;
  final String style;
  final String genre;
  final String key;
  final String language;
  final bool includeManuscripts;
  final int? yearFrom;
  final int? yearTo;

  const WorkFilters({
    this.instrumentation = '',
    this.style = '',
    this.genre = '',
    this.key = '',
    this.language = '',
    this.includeManuscripts = true,
    this.yearFrom,
    this.yearTo,
  });

  bool get isEmpty =>
      instrumentation.isEmpty &&
      style.isEmpty &&
      genre.isEmpty &&
      key.isEmpty &&
      language.isEmpty &&
      includeManuscripts &&
      yearFrom == null &&
      yearTo == null;

  WorkFilters copyWith({
    String? instrumentation,
    String? style,
    String? genre,
    String? key,
    String? language,
    bool? includeManuscripts,
    int? yearFrom,
    int? yearTo,
    bool clearYearFrom = false,
    bool clearYearTo = false,
  }) =>
      WorkFilters(
        instrumentation: instrumentation ?? this.instrumentation,
        style: style ?? this.style,
        genre: genre ?? this.genre,
        key: key ?? this.key,
        language: language ?? this.language,
        includeManuscripts: includeManuscripts ?? this.includeManuscripts,
        yearFrom: clearYearFrom ? null : (yearFrom ?? this.yearFrom),
        yearTo: clearYearTo ? null : (yearTo ?? this.yearTo),
      );
}
