import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImslpResult {
  final String title;
  final String? snippet;
  final int? pageId;

  ImslpResult({required this.title, this.snippet, this.pageId});

  String get workName {
    final parenIndex = title.lastIndexOf('(');
    if (parenIndex > 0) return title.substring(0, parenIndex).trim();
    return title;
  }

  String get composerName {
    final parenIndex = title.lastIndexOf('(');
    if (parenIndex > 0 && title.endsWith(')')) {
      return title.substring(parenIndex + 1, title.length - 1).trim();
    }
    return '';
  }
}

class ImslpFileInfo {
  final String name;
  final String url;

  ImslpFileInfo({required this.name, required this.url});

  String get displayName {
    var n = name;
    if (n.startsWith('File:')) n = n.substring(5);
    if (n.startsWith('Image:')) n = n.substring(6);
    return n;
  }
}

class ImslpService {
  static const _apiUrl = 'https://imslp.org/api.php';

  final _client = http.Client();

  Map<String, String> get _headers => {
        'User-Agent': 'Leggio/1.0 (Sheet Music Viewer; Flutter)',
      };

  Future<List<ImslpResult>> searchWorks(String query,
      {int limit = 50}) async {
    final uri = Uri.parse(_apiUrl).replace(queryParameters: {
      'action': 'query',
      'list': 'search',
      'srsearch': query,
      'srnamespace': '0',
      'srlimit': limit.toString(),
      'format': 'json',
      'maxlag': '5',
    });

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Erreur serveur: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data.containsKey('error')) {
      throw Exception(data['error']['info'] ?? 'Erreur API');
    }

    final results = data['query']?['search'] as List? ?? [];
    return results
        .map((r) => ImslpResult(
              title: r['title'] as String,
              snippet: _cleanHtml(r['snippet'] as String?),
              pageId: r['pageid'] as int?,
            ))
        .toList();
  }

  Future<List<String>> searchInstrumentCategories(String instrument) async {
    final results = <String>[];

    // Search for "For <instrument>" categories via allcategories prefix
    final prefixUri = Uri.parse(_apiUrl).replace(queryParameters: {
      'action': 'query',
      'list': 'allcategories',
      'acprefix': 'For $instrument',
      'aclimit': '30',
      'format': 'json',
      'maxlag': '5',
    });

    final prefixResponse = await _client.get(prefixUri, headers: _headers);
    if (prefixResponse.statusCode == 200) {
      final data = jsonDecode(prefixResponse.body) as Map<String, dynamic>;
      final cats = data['query']?['allcategories'] as List? ?? [];
      for (final c in cats) {
        final name = c['*'] as String? ?? c.toString();
        results.add('Category:$name');
      }
    }

    // Also search for "Scores featuring the <instrument>"
    final featUri = Uri.parse(_apiUrl).replace(queryParameters: {
      'action': 'query',
      'list': 'allcategories',
      'acprefix': 'Scores featuring the $instrument',
      'aclimit': '10',
      'format': 'json',
      'maxlag': '5',
    });

    final featResponse = await _client.get(featUri, headers: _headers);
    if (featResponse.statusCode == 200) {
      final data = jsonDecode(featResponse.body) as Map<String, dynamic>;
      final cats = data['query']?['allcategories'] as List? ?? [];
      for (final c in cats) {
        final name = c['*'] as String? ?? c.toString();
        final full = 'Category:$name';
        if (!results.contains(full)) results.add(full);
      }
    }

    return results;
  }

  Future<List<ImslpResult>> getCategoryWorks(String category,
      {int limit = 50, String? continueToken}) async {
    final params = <String, String>{
      'action': 'query',
      'list': 'categorymembers',
      'cmtitle': category,
      'cmnamespace': '0',
      'cmlimit': limit.toString(),
      'format': 'json',
      'maxlag': '5',
    };
    if (continueToken != null) {
      params['cmcontinue'] = continueToken;
    }

    final uri = Uri.parse(_apiUrl).replace(queryParameters: params);
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) {
      throw Exception('Erreur serveur: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final members = data['query']?['categorymembers'] as List? ?? [];
    return members
        .map((m) => ImslpResult(
              title: m['title'] as String,
              pageId: m['pageid'] as int?,
            ))
        .toList();
  }

  Future<List<ImslpFileInfo>> getWorkFiles(String pageTitle) async {
    // Get list of files (images) on the work page
    final imagesUri = Uri.parse(_apiUrl).replace(queryParameters: {
      'action': 'query',
      'titles': pageTitle,
      'prop': 'images',
      'imlimit': '100',
      'format': 'json',
      'maxlag': '5',
    });

    final imagesResponse = await _client.get(imagesUri, headers: _headers);
    if (imagesResponse.statusCode != 200) {
      throw Exception('Erreur serveur: ${imagesResponse.statusCode}');
    }

    final imagesData = jsonDecode(imagesResponse.body) as Map<String, dynamic>;
    final pages = imagesData['query']?['pages'] as Map<String, dynamic>? ?? {};
    if (pages.isEmpty) return [];

    final page = pages.values.first as Map<String, dynamic>;
    final images = (page['images'] as List?)
            ?.map((i) => i['title'] as String)
            .where((t) => t.toLowerCase().endsWith('.pdf'))
            .toList() ??
        [];

    if (images.isEmpty) return [];

    // Get download URLs for each PDF (batch queries of up to 50)
    final files = <ImslpFileInfo>[];
    for (int i = 0; i < images.length; i += 50) {
      final batch = images.skip(i).take(50).join('|');

      final infoUri = Uri.parse(_apiUrl).replace(queryParameters: {
        'action': 'query',
        'titles': batch,
        'prop': 'imageinfo',
        'iiprop': 'url',
        'format': 'json',
        'maxlag': '5',
      });

      final infoResponse = await _client.get(infoUri, headers: _headers);
      if (infoResponse.statusCode != 200) continue;

      final infoData =
          jsonDecode(infoResponse.body) as Map<String, dynamic>;
      final infoPages =
          infoData['query']?['pages'] as Map<String, dynamic>? ?? {};

      for (final entry in infoPages.values) {
        final info = entry as Map<String, dynamic>;
        final imageInfo = info['imageinfo'] as List?;
        if (imageInfo != null && imageInfo.isNotEmpty) {
          final url = imageInfo[0]['url'] as String?;
          final title = info['title'] as String? ?? '';
          if (url != null) {
            files.add(ImslpFileInfo(name: title, url: url));
          }
        }
      }
    }

    return files;
  }

  Future<String> downloadPdf(String url, String filename) async {
    final dir = await _getDownloadDirectory();
    // Sanitize filename
    final safeName = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    final savePath = p.join(dir.path, safeName);

    // Check if already downloaded
    final existing = File(savePath);
    if (await existing.exists() && await existing.length() > 0) {
      return savePath;
    }

    final request = http.Request('GET', Uri.parse(url));
    request.headers.addAll(_headers);
    request.headers['Cookie'] = 'imslpdisclaimeraccepted=yes';

    final streamedResponse = await _client.send(request);
    if (streamedResponse.statusCode != 200) {
      throw Exception(
          'Erreur de téléchargement: ${streamedResponse.statusCode}');
    }

    final file = File(savePath);
    final sink = file.openWrite();
    await streamedResponse.stream.pipe(sink);
    await sink.close();

    // Verify we got a PDF (not an HTML error page)
    final bytes = await file.readAsBytes();
    if (bytes.length < 5 ||
        String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      await file.delete();
      throw Exception(
          'Le fichier téléchargé n\'est pas un PDF valide. '
          'Le serveur a peut-être renvoyé une page d\'erreur.');
    }

    return savePath;
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Leggio/IMSLP');
      await dir.create(recursive: true);
      return dir;
    } else {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docsDir.path, 'Leggio', 'IMSLP'));
      await dir.create(recursive: true);
      return dir;
    }
  }

  String? _cleanHtml(String? html) {
    if (html == null) return null;
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .trim();
  }

  void dispose() {
    _client.close();
  }
}
