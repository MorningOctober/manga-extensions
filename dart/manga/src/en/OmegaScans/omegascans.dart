import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class OmegaScans extends MProvider {
  OmegaScans({required this.source});

  MSource source;
  final Client client = Client();

  static const _defaultPerPage = "20";
  static const _fallbackPageImageUrl = "https://omegascans.org/favicon.ico";
  static const List<String> _blockedAssetHostSuffixes = ["bato.to"];
  static const List<String> _blockedAssetPathFragments = [
    "/amsta/img/btoto/logo-batoto.png",
  ];
  static const List<Map<String, String>> _availableTags = [
    {"name": "Drama", "id": "2"},
    {"name": "Harem", "id": "8"},
    {"name": "Fantasy", "id": "3"},
    {"name": "Romance", "id": "1"},
    {"name": "MILF", "id": "16"},
  ];

  @override
  bool get supportsLatest => true;

  @override
  String? get baseUrl => source.baseUrl;

  @override
  Map<String, String> get headers => _headers;

  Map<String, String> get _headers => {
    "Accept": "*/*",
    "Referer": source.baseUrl ?? "https://omegascans.org",
  };

  Uri _apiUri(String path, [Map<String, String>? queryParameters]) {
    final base = "${source.apiUrl ?? "https://api.omegascans.org"}$path";
    if (queryParameters == null || queryParameters.isEmpty) {
      return Uri.parse(base);
    }

    final query = queryParameters.entries
        .map(
          (entry) =>
              "${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}",
        )
        .join("&");
    return Uri.parse("$base?$query");
  }

  Future<MPages> _fetchSeriesPage(
    int page, {
    required String query,
    required String orderBy,
    required String order,
    required String status,
    required List<String> tagIds,
  }) async {
    final normalizedPage = _normalizePage(page);
    final res = await client.get(
      _apiUri("/query", {
        "perPage": _defaultPerPage,
        "series_type": "Comic",
        "query_string": query,
        "orderBy": orderBy,
        "adult": "true",
        "order": order,
        "status": status,
        "tags_ids": _encodeTagIds(tagIds),
        "page": normalizedPage.toString(),
      }),
      headers: _headers,
    );

    final jsonResponse = _asMap(_decodeJsonSafe(res.body));
    final data = _asList(jsonResponse["data"]);
    final meta = _asMap(jsonResponse["meta"]);

    final currentPage =
        int.tryParse("${meta["current_page"] ?? normalizedPage}") ??
        normalizedPage;
    final lastPage =
        int.tryParse("${meta["last_page"] ?? currentPage}") ?? currentPage;

    final mangaList = <MManga>[];
    for (final raw in data) {
      mangaList.add(_mapSeriesToManga(raw));
    }

    return MPages(mangaList, currentPage < lastPage);
  }

  MManga _mapSeriesToManga(dynamic raw) {
    final item = _asMap(raw);
    final slug = _asString(item["series_slug"]);
    final manga = MManga();
    final author = _firstNotEmpty([
      _asString(item["author"]),
      _asString(item["studio"]),
    ]);
    final statusList = [
      {
        "ongoing": 0,
        "completed": 1,
        "hiatus": 2,
        "dropped": 3,
        "canceled": 3,
        "cancelled": 3,
      },
    ];

    manga.name = _firstNotEmpty([
      _asString(item["title"]),
      _asString(item["name"]),
      slug,
    ]);
    manga.imageUrl = _toAbsoluteUrl(_asString(item["thumbnail"]));
    manga.link = slug.isEmpty ? "" : "/series/$slug";
    manga.description = _cleanDescriptionText(_asString(item["description"]));
    manga.author = author;
    manga.artist = author;
    manga.genre = _extractGenres(item["tags"]);
    manga.status = parseStatus(
      _asString(item["status"]).toLowerCase(),
      statusList,
    );

    return manga;
  }

  @override
  Future<MPages> getPopular(int page) async {
    return _fetchSeriesPage(
      page,
      query: "",
      orderBy: "total_views",
      order: "desc",
      status: "All",
      tagIds: const [],
    );
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return _fetchSeriesPage(
      page,
      query: "",
      orderBy: "updated_at",
      order: "desc",
      status: "All",
      tagIds: const [],
    );
  }

  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String queryString = query;
    String orderBy = "created_at";
    String order = "desc";
    String status = "All";
    final tagIds = <String>[];

    for (final filter in filterList.filters) {
      if (filter.type == "SearchFilter") {
        final value = _asString(filter.state);
        if (value.isNotEmpty) queryString = value;
      } else if (filter.type == "OrderByFilter") {
        if (filter.state >= 0 && filter.state < filter.values.length) {
          orderBy = _asString(filter.values[filter.state].value);
        }
      } else if (filter.type == "OrderFilter") {
        if (filter.state >= 0 && filter.state < filter.values.length) {
          order = _asString(filter.values[filter.state].value);
        }
      } else if (filter.type == "StatusFilter") {
        if (filter.state >= 0 && filter.state < filter.values.length) {
          status = _asString(filter.values[filter.state].value);
        }
      } else if (filter.type == "TagsFilter") {
        final values = _asList(filter.state);
        for (final item in values) {
          if (item is CheckBoxFilter && item.state == true) {
            final id = _asString(item.value);
            if (id.isNotEmpty) tagIds.add(id);
          }
        }
      }
    }

    return _fetchSeriesPage(
      page,
      query: queryString,
      orderBy: orderBy,
      order: order,
      status: status,
      tagIds: tagIds,
    );
  }

  @override
  Future<MManga> getDetail(String url) async {
    final slug = _extractSeriesSlug(url);
    if (slug.isEmpty) return MManga();
    final res = await client.get(_apiUri("/series/$slug"), headers: _headers);

    final data = _asMap(_decodeJsonSafe(res.body));
    final manga = MManga();
    final statusList = [
      {
        "ongoing": 0,
        "completed": 1,
        "hiatus": 2,
        "dropped": 3,
        "canceled": 3,
        "cancelled": 3,
      },
    ];

    final title = _firstNotEmpty([
      _asString(data["title"]),
      _asString(data["name"]),
      slug,
    ]);
    final description = _buildDescription(data);
    final author = _firstNotEmpty([
      _asString(data["author"]),
      _asString(data["studio"]),
    ]);

    manga.name = title;
    manga.link = "/series/$slug";
    manga.imageUrl = _toAbsoluteUrl(_asString(data["thumbnail"]));
    manga.description = description;
    manga.author = author;
    manga.artist = author;
    manga.genre = _extractGenres(data["tags"]);
    manga.status = parseStatus(
      _asString(data["status"]).toLowerCase(),
      statusList,
    );
    final chapters = await _getChapters(slug, fallbackTitle: title);
    manga.chapters = chapters;
    if (chapters.isNotEmpty) {
      final first = chapters.first;
      print(
        "OmegaScans/getDetail slug=$slug chapters=${chapters.length} firstName=${first.name} firstUrl=${first.url}",
      );
    } else {
      print("OmegaScans/getDetail slug=$slug chapters=0");
    }

    return manga;
  }

  Future<List<MChapter>> _getChapters(
    String seriesSlug, {
    String? fallbackTitle,
  }) async {
    if (seriesSlug.isEmpty) return [];

    final chapters = await _getChaptersFromEndpoint(seriesSlug);
    if (chapters.isNotEmpty) return chapters;

    if (fallbackTitle != null && fallbackTitle.trim().isNotEmpty) {
      final queryFallback = await _getChaptersFromQuery(
        fallbackTitle,
        preferredSlug: seriesSlug,
      );
      if (queryFallback.isNotEmpty) return queryFallback;
    }

    return [];
  }

  Future<List<MChapter>> _getChaptersFromEndpoint(String seriesSlug) async {
    final res = await client.get(
      _apiUri("/chapter/all/$seriesSlug"),
      headers: _headers,
    );

    final decoded = _decodeJsonSafe(res.body);
    var rawChapters = _asList(decoded);
    if (rawChapters.isEmpty) {
      final payload = _asMap(decoded);
      rawChapters = _asList(payload["chapters"]);
      if (rawChapters.isEmpty) rawChapters = _asList(payload["data"]);
      if (rawChapters.isEmpty) rawChapters = _asList(payload["results"]);
    }

    final mapped = _mapChapters(rawChapters, seriesSlug);
    if (mapped.isNotEmpty) return mapped;

    return _mapChaptersFromRawBody(res.body, seriesSlug);
  }

  Future<List<MChapter>> _getChaptersFromQuery(
    String query, {
    required String preferredSlug,
  }) async {
    final res = await client.get(
      _apiUri("/query", {
        "perPage": _defaultPerPage,
        "series_type": "Comic",
        "query_string": query,
        "orderBy": "updated_at",
        "adult": "true",
        "order": "desc",
        "status": "All",
        "tags_ids": "[]",
        "page": "1",
      }),
      headers: _headers,
    );

    final payload = _asMap(_decodeJsonSafe(res.body));
    final seriesList = _asList(payload["data"]);
    if (seriesList.isEmpty) return [];

    Map<String, dynamic> series = _asMap(seriesList.first);
    for (final raw in seriesList) {
      final candidate = _asMap(raw);
      if (_asString(candidate["series_slug"]) == preferredSlug) {
        series = candidate;
        break;
      }
    }

    final slug = _firstNotEmpty([
      _asString(series["series_slug"]),
      preferredSlug,
    ]);
    if (slug.isEmpty) return [];

    final merged = <dynamic>[
      ..._asList(series["free_chapters"]),
      ..._asList(series["paid_chapters"]),
    ];
    return _mapChapters(merged, slug);
  }

  List<MChapter> _mapChapters(List<dynamic> rawChapters, String seriesSlug) {
    final chapters = <MChapter>[];
    final seen = <String>{};

    for (final raw in rawChapters) {
      final chapter = _asMap(raw);
      final chapterSlug = _asString(chapter["chapter_slug"]);
      if (chapterSlug.isEmpty || seen.contains(chapterSlug)) continue;
      seen.add(chapterSlug);

      final chapterName = _firstNotEmpty([
        _asString(chapter["chapter_name"]),
        _asString(chapter["name"]),
        chapterSlug,
      ]);
      final chapterTitle = _asString(chapter["chapter_title"]);
      final price = int.tryParse("${chapter["price"] ?? 0}") ?? 0;

      final item = MChapter();
      item.name = chapterTitle.isEmpty
          ? chapterName
          : "$chapterName - $chapterTitle";
      item.url = "$seriesSlug||$chapterSlug";
      item.dateUpload = _parseDateUpload(chapter["created_at"]);
      item.thumbnailUrl = _toAbsoluteUrl(
        _asString(chapter["chapter_thumbnail"]),
      );
      if (price > 0) {
        item.description = "Premium chapter ($price coins)";
      }
      chapters.add(item);
    }

    return chapters;
  }

  List<MChapter> _mapChaptersFromRawBody(String rawBody, String seriesSlug) {
    if (rawBody.trim().isEmpty) return [];

    final slugMatches = RegExp(
      r'"chapter_slug"\s*:\s*"([^"]+)"',
    ).allMatches(rawBody).toList();
    if (slugMatches.isEmpty) return [];

    final nameMatches = RegExp(
      r'"chapter_name"\s*:\s*"([^"]*)"',
    ).allMatches(rawBody).toList();
    final titleMatches = RegExp(
      r'"chapter_title"\s*:\s*(?:"([^"]*)"|null)',
    ).allMatches(rawBody).toList();
    final dateMatches = RegExp(
      r'"created_at"\s*:\s*"([^"]+)"',
    ).allMatches(rawBody).toList();
    final thumbnailMatches = RegExp(
      r'"chapter_thumbnail"\s*:\s*(?:"([^"]*)"|null)',
    ).allMatches(rawBody).toList();
    final priceMatches = RegExp(
      r'"price"\s*:\s*(\d+)',
    ).allMatches(rawBody).toList();

    final chapters = <MChapter>[];
    final seen = <String>{};

    for (var i = 0; i < slugMatches.length; i++) {
      final chapterSlug = _decodeHtmlEntities(
        slugMatches[i].group(1) ?? "",
      ).trim();
      if (chapterSlug.isEmpty || seen.contains(chapterSlug)) continue;
      seen.add(chapterSlug);

      final chapterName = i < nameMatches.length
          ? _decodeHtmlEntities(nameMatches[i].group(1) ?? "").trim()
          : "";
      final chapterTitle = i < titleMatches.length
          ? _decodeHtmlEntities(titleMatches[i].group(1) ?? "").trim()
          : "";
      final createdAt = i < dateMatches.length ? dateMatches[i].group(1) : null;
      final thumbnail = i < thumbnailMatches.length
          ? _decodeHtmlEntities(thumbnailMatches[i].group(1) ?? "").trim()
          : "";
      final price = i < priceMatches.length
          ? int.tryParse(priceMatches[i].group(1) ?? "0") ?? 0
          : 0;

      final fallbackName = chapterSlug.replaceAll("-", " ").trim();
      final displayName = chapterTitle.isEmpty
          ? _firstNotEmpty([chapterName, fallbackName, chapterSlug])
          : "${_firstNotEmpty([chapterName, fallbackName, chapterSlug])} - $chapterTitle";

      final item = MChapter();
      item.name = displayName;
      item.url = "$seriesSlug||$chapterSlug";
      item.dateUpload = _parseDateUpload(createdAt);
      item.thumbnailUrl = _toAbsoluteUrl(thumbnail);
      if (price > 0) {
        item.description = "Premium chapter ($price coins)";
      }
      chapters.add(item);
    }

    return chapters;
  }

  @override
  Future<List<String>> getPageList(String url) async {
    final ref = _extractChapterRef(url);
    if (ref.seriesSlug.isEmpty || ref.chapterSlug.isEmpty) {
      return _fallbackPageList();
    }

    try {
      final res = await client.get(
        _apiUri("/chapter/${ref.seriesSlug}/${ref.chapterSlug}"),
        headers: _headers,
      );
      final data = _asMap(_decodeJsonSafe(res.body));
      if (data["paywall"] == true) return _fallbackPageList();

      final chapter = _asMap(data["chapter"]);
      final chapterData = _asMap(chapter["chapter_data"]);
      final images = _asList(chapterData["images"]);

      final pages = <String>[];
      for (final image in images) {
        final imageUrl = _extractImageUrl(image);
        if (imageUrl.isEmpty) continue;
        final normalizedUrl = _toAbsoluteUrl(imageUrl);
        if (normalizedUrl.isEmpty) continue;
        pages.add(normalizedUrl);
      }

      return pages.isNotEmpty ? pages : _fallbackPageList();
    } catch (_) {
      return _fallbackPageList();
    }
  }

  @override
  Future<String> getHtmlContent(String name, String url) async {
    return "";
  }

  @override
  Future<String> cleanHtmlContent(String html) async {
    return html;
  }

  @override
  Future<List<Video>> getVideoList(String url) async {
    return [];
  }

  String _buildDescription(Map<String, dynamic> data) {
    final description = _cleanDescriptionText(_asString(data["description"]));
    final alternativeTitles = _extractAlternativeTitles(data);
    if (alternativeTitles.isEmpty) return description;

    final altBlock = "Alternative Titles:\n${alternativeTitles.join("\n")}";
    if (description.isEmpty) return altBlock;
    return "$description\n-----\n$altBlock";
  }

  List<String> _extractGenres(dynamic tagsRaw) {
    final tags = _asList(tagsRaw);
    return tags
        .map((tag) {
          if (tag is Map) return _asString(tag["name"]);
          return _asString(tag);
        })
        .where((name) => name.isNotEmpty)
        .toList();
  }

  dynamic _decodeJsonSafe(String raw) {
    try {
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  dynamic _normalizeBridgedValue(dynamic value) {
    if (value == null) return null;
    if (value is Map || value is List) return value;

    if (value is String) {
      final trimmed = value.trim();
      final maybeJson =
          (trimmed.startsWith("{") && trimmed.endsWith("}")) ||
          (trimmed.startsWith("[") && trimmed.endsWith("]"));
      if (maybeJson) {
        final decoded = _decodeJsonSafe(trimmed);
        if (decoded != null) return decoded;
      }
    }

    try {
      final normalized = json.decode(json.encode(value));
      if (normalized != null) return normalized;
    } catch (_) {}

    try {
      // ignore: avoid_dynamic_calls
      final toJsonValue = (value as dynamic).toJson();
      if (toJsonValue != null) return toJsonValue;
    } catch (_) {}

    return value;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    value = _normalizeBridgedValue(value);
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    value = _normalizeBridgedValue(value);
    if (value is List<dynamic>) return value;
    if (value is List) return List<dynamic>.from(value);
    return <dynamic>[];
  }

  String _asString(dynamic value) => value?.toString().trim() ?? "";

  String _decodeHtmlEntities(String input) {
    if (input.isEmpty) return input;
    var value = input;

    final named = <String, String>{
      "&amp;": "&",
      "&lt;": "<",
      "&gt;": ">",
      "&quot;": "\"",
      "&#39;": "'",
      "&apos;": "'",
      "&nbsp;": " ",
      "&hellip;": "...",
      "&ldquo;": "\"",
      "&rdquo;": "\"",
      "&lsquo;": "'",
      "&rsquo;": "'",
      "&mdash;": "-",
      "&ndash;": "-",
    };
    named.forEach((entity, char) {
      value = value.replaceAll(entity, char);
    });

    value = value.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final codePoint = int.tryParse(match.group(1)!);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });
    value = value.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final codePoint = int.tryParse(match.group(1)!, radix: 16);
      return codePoint == null
          ? match.group(0)!
          : String.fromCharCode(codePoint);
    });

    return value;
  }

  String _cleanDescriptionText(String htmlLikeText) {
    var value = _decodeHtmlEntities(htmlLikeText).trim();
    if (value.isEmpty) return value;

    value = value.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), "\n");
    value = value.replaceAll(RegExp(r'</p\s*>', caseSensitive: false), "\n\n");
    value = value.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), "");
    value = value.replaceAll(RegExp(r'<[^>]+>'), "");
    value = value.replaceAll(RegExp(r'\n{3,}'), "\n\n");
    return value.trim();
  }

  List<String> _extractAlternativeTitles(Map<String, dynamic> data) {
    final titles = <String>[];

    void addTitle(dynamic raw) {
      final value = _decodeHtmlEntities(_asString(raw)).trim();
      if (value.isNotEmpty) titles.add(value);
    }

    void addFromList(dynamic raw) {
      final values = _asList(raw);
      for (final item in values) {
        addTitle(item);
      }
    }

    void addFromString(dynamic raw) {
      if (raw is! String) return;
      final value = _decodeHtmlEntities(raw).trim();
      if (value.isEmpty) return;
      final splitValues = value
          .split(RegExp(r'\s*[•|\n]\s*'))
          .map((title) => title.trim())
          .where((title) => title.isNotEmpty)
          .toList();
      if (splitValues.isNotEmpty) {
        titles.addAll(splitValues);
      } else {
        titles.add(value);
      }
    }

    addFromList(data["alt_titles"]);
    addFromList(data["alternative_titles"]);
    addFromList(data["alternative_names"]);
    addFromList(data["alternativeNames"]);

    addFromString(data["alternative_titles"]);
    addFromString(data["alternative_names"]);
    addFromString(data["alternativeNames"]);

    final seen = <String>{};
    final unique = <String>[];
    for (final title in titles) {
      if (seen.add(title)) unique.add(title);
    }
    return unique;
  }

  String _encodeTagIds(List<String> tagIds) {
    final ids = tagIds
        .map((id) => id.trim())
        .where((id) => RegExp(r"^\d+$").hasMatch(id))
        .toSet()
        .toList();
    if (ids.isEmpty) return "[]";
    return "[${ids.join(",")}]";
  }

  int _normalizePage(int page) => page < 1 ? 1 : page;

  String _firstNotEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) return value;
    }
    return "";
  }

  String _toAbsoluteUrl(String value) {
    if (value.isEmpty) return value;
    if (value.startsWith("http://") || value.startsWith("https://")) {
      return _sanitizeRemoteAssetUrl(value);
    }
    if (value.startsWith("//")) return _sanitizeRemoteAssetUrl("https:$value");
    final base = source.baseUrl ?? "https://omegascans.org";
    if (value.startsWith("/")) return _sanitizeRemoteAssetUrl("$base$value");
    return _sanitizeRemoteAssetUrl("$base/$value");
  }

  String _sanitizeRemoteAssetUrl(String value) {
    final url = value.trim();
    if (url.isEmpty) return "";

    final uri = Uri.tryParse(url);
    if (uri == null) return "";
    if (uri.scheme != "http" && uri.scheme != "https") return "";
    if (uri.host.trim().isEmpty) return "";

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    if (_isBlockedAssetHost(host) || _isBlockedAssetPath(path)) {
      return "";
    }

    return url;
  }

  bool _isBlockedAssetHost(String host) {
    for (final suffix in _blockedAssetHostSuffixes) {
      if (host == suffix || host.endsWith(".$suffix")) return true;
    }
    return false;
  }

  bool _isBlockedAssetPath(String path) {
    for (final fragment in _blockedAssetPathFragments) {
      if (path.contains(fragment)) return true;
    }
    return false;
  }

  String? _parseDateUpload(dynamic raw) {
    final value = _asString(raw);
    if (value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    return parsed?.millisecondsSinceEpoch.toString();
  }

  String _extractSeriesSlug(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return value;

    if (value.contains("||")) {
      return value.split("||").first.trim();
    }

    final absolute = RegExp(
      r'omegascans\.org\/series\/([^\/?#]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (absolute != null) return absolute.group(1)!;

    final cleaned = value.split("?").first.split("#").first;
    final segments = cleaned.split("/").where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return cleaned;

    final seriesIndex = segments.lastIndexOf("series");
    if (seriesIndex != -1 && seriesIndex + 1 < segments.length) {
      return segments[seriesIndex + 1];
    }

    return segments.last;
  }

  _ChapterRef _extractChapterRef(String raw) {
    final value = raw.trim();
    if (value.contains("||")) {
      final parts = value.split("||");
      return _ChapterRef(
        seriesSlug: parts.first.trim(),
        chapterSlug: parts.length > 1 ? parts[1].trim() : "",
      );
    }

    final absolute = RegExp(
      r'omegascans\.org\/series\/([^\/?#]+)\/([^\/?#]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (absolute != null) {
      return _ChapterRef(
        seriesSlug: absolute.group(1)!,
        chapterSlug: absolute.group(2)!,
      );
    }

    final absoluteApiStyle = RegExp(
      r'omegascans\.org\/chapter\/([^\/?#]+)\/([^\/?#]+)',
      caseSensitive: false,
    ).firstMatch(value);
    if (absoluteApiStyle != null) {
      return _ChapterRef(
        seriesSlug: absoluteApiStyle.group(1)!,
        chapterSlug: absoluteApiStyle.group(2)!,
      );
    }

    final cleaned = value.split("?").first.split("#").first;
    final segments = cleaned.split("/").where((s) => s.isNotEmpty).toList();
    final seriesIndex = segments.lastIndexOf("series");
    if (seriesIndex != -1 && seriesIndex + 2 < segments.length) {
      return _ChapterRef(
        seriesSlug: segments[seriesIndex + 1],
        chapterSlug: segments[seriesIndex + 2],
      );
    }

    final chapterIndex = segments.lastIndexOf("chapter");
    if (chapterIndex != -1 && chapterIndex + 2 < segments.length) {
      return _ChapterRef(
        seriesSlug: segments[chapterIndex + 1],
        chapterSlug: segments[chapterIndex + 2],
      );
    }

    return const _ChapterRef(seriesSlug: "", chapterSlug: "");
  }

  String _extractImageUrl(dynamic raw) {
    if (raw is String) return raw.trim();
    final map = _asMap(raw);
    if (map.isNotEmpty) {
      return _firstNotEmpty([
        _asString(map["url"]),
        _asString(map["image"]),
        _asString(map["src"]),
      ]);
    }
    return "";
  }

  List<String> _fallbackPageList() {
    final fallback = _toAbsoluteUrl(_fallbackPageImageUrl);
    if (fallback.isEmpty) return [_fallbackPageImageUrl];
    return [fallback];
  }

  @override
  List<dynamic> getFilterList() {
    return [
      TextFilter("SearchFilter", "Search..."),
      SelectFilter("OrderByFilter", "Order by", 0, [
        SelectFilterOption("Created at", "created_at"),
        SelectFilterOption("Updated at", "updated_at"),
        SelectFilterOption("Popularity", "total_views"),
        SelectFilterOption("Title", "title"),
      ]),
      SelectFilter("OrderFilter", "Direction", 0, [
        SelectFilterOption("Descending", "desc"),
        SelectFilterOption("Ascending", "asc"),
      ]),
      SelectFilter("StatusFilter", "Status", 0, [
        SelectFilterOption("All", "All"),
        SelectFilterOption("Ongoing", "Ongoing"),
        SelectFilterOption("Hiatus", "Hiatus"),
        SelectFilterOption("Dropped", "Dropped"),
        SelectFilterOption("Completed", "Completed"),
      ]),
      SeparatorFilter(),
      GroupFilter(
        "TagsFilter",
        "Tags",
        _availableTags
            .map(
              (tag) =>
                  CheckBoxFilter(_asString(tag["name"]), _asString(tag["id"])),
            )
            .toList(),
      ),
    ];
  }

  @override
  List<dynamic> getSourcePreferences() => [];
}

class _ChapterRef {
  final String seriesSlug;
  final String chapterSlug;

  const _ChapterRef({required this.seriesSlug, required this.chapterSlug});
}

// ignore: main_first_positional_parameter_type
OmegaScans main(MSource source) {
  return OmegaScans(source: source);
}
