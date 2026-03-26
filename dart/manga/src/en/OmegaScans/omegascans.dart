import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class OmegaScans extends MProvider {
  OmegaScans({required this.source});

  MSource source;
  final Client client = Client();

  static const _defaultPerPage = "20";
  static const _availableTags = [
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
    final uri = Uri.parse(base);
    if (queryParameters == null) return uri;
    return uri.replace(queryParameters: queryParameters);
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

    final list = data.map(_mapSeriesToManga).toList();
    return MPages(list, currentPage < lastPage);
  }

  MManga _mapSeriesToManga(dynamic raw) {
    final item = _asMap(raw);
    final slug = _asString(item["series_slug"]);
    final manga = MManga();

    manga.name = _firstNotEmpty([
      _asString(item["title"]),
      _asString(item["name"]),
      slug,
    ]);
    manga.imageUrl = _toAbsoluteUrl(_asString(item["thumbnail"]));
    manga.link = slug.isEmpty ? "" : "/series/$slug";

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
    manga.chapters = await _getChapters(slug);

    return manga;
  }

  Future<List<MChapter>> _getChapters(String seriesSlug) async {
    if (seriesSlug.isEmpty) return [];
    final res = await client.get(
      _apiUri("/chapter/all/$seriesSlug"),
      headers: _headers,
    );
    final data = _asList(_decodeJsonSafe(res.body));
    final chapters = <MChapter>[];

    for (final raw in data) {
      final chapter = _asMap(raw);
      final chapterSlug = _asString(chapter["chapter_slug"]);
      if (chapterSlug.isEmpty) continue;

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

  @override
  Future<List<String>> getPageList(String url) async {
    final ref = _extractChapterRef(url);
    if (ref.seriesSlug.isEmpty || ref.chapterSlug.isEmpty) return [];
    final res = await client.get(
      _apiUri("/chapter/${ref.seriesSlug}/${ref.chapterSlug}"),
      headers: _headers,
    );
    final data = _asMap(_decodeJsonSafe(res.body));

    if (data["paywall"] == true) return [];

    final chapter = _asMap(data["chapter"]);
    final chapterData = _asMap(chapter["chapter_data"]);
    final images = _asList(chapterData["images"]);

    final pages = <String>[];
    for (final image in images) {
      final imageUrl = _extractImageUrl(image);
      if (imageUrl.isEmpty) continue;
      pages.add(_toAbsoluteUrl(imageUrl));
    }

    return pages;
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
    final description = _asString(data["description"]);
    final alternativeNames = _asString(data["alternative_names"]);
    if (alternativeNames.isEmpty) return description;
    if (description.isEmpty) return "Alternative names:\n$alternativeNames";
    return "$description\n\nAlternative names:\n$alternativeNames";
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

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  List<dynamic> _asList(dynamic value) {
    if (value is List<dynamic>) return value;
    if (value is List) return List<dynamic>.from(value);
    return <dynamic>[];
  }

  String _asString(dynamic value) => value?.toString().trim() ?? "";

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
    if (value.startsWith("http://") || value.startsWith("https://"))
      return value;
    if (value.startsWith("//")) return "https:$value";
    final base = source.baseUrl ?? "https://omegascans.org";
    if (value.startsWith("/")) return "$base$value";
    return "$base/$value";
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

    final cleaned = value.split("?").first.split("#").first;
    final segments = cleaned.split("/").where((s) => s.isNotEmpty).toList();
    final seriesIndex = segments.lastIndexOf("series");
    if (seriesIndex != -1 && seriesIndex + 2 < segments.length) {
      return _ChapterRef(
        seriesSlug: segments[seriesIndex + 1],
        chapterSlug: segments[seriesIndex + 2],
      );
    }

    return const _ChapterRef(seriesSlug: "", chapterSlug: "");
  }

  String _extractImageUrl(dynamic raw) {
    if (raw is String) return raw.trim();
    if (raw is Map<String, dynamic>) {
      return _firstNotEmpty([
        _asString(raw["url"]),
        _asString(raw["image"]),
        _asString(raw["src"]),
      ]);
    }
    return "";
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
              (tag) => CheckBoxFilter(
                _asString(tag["name"]),
                _asString(tag["id"]),
              ),
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
