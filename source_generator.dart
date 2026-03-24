import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart/manga/manga_source_list.dart';
import 'model/source.dart';

void main() {
  final jsSources = _searchJsSources(Directory("javascript"));
  genManga(
    jsSources.where((element) => element.itemType!.name == "manga").toList(),
  );
}

void genManga(List<Source> jsMangasourceList) {
  List<Source> mangaSources = [];
  mangaSources.addAll(dartMangasourceList);
  mangaSources.addAll(jsMangasourceList);
  final List<Map<String, dynamic>> jsonList = mangaSources
      .map((source) => source.toJson())
      .toList();
  final jsonString = jsonEncode(jsonList);

  final file = File('index.json');
  file.writeAsStringSync(jsonString);

  log('JSON file created: ${file.path}');
}

List<Source> _searchJsSources(Directory dir) {
  List<Source> sourceList = [];
  final jsFiles = dir.listSync(recursive: true, followLinks: false).whereType<File>().where(
    (file) => file.path.endsWith('.js'),
  );

  final sourceRegex = RegExp(
    r'\b(?:const|let|var)\s+mangayomiSources\s*=\s*(\[[\s\S]*?\])\s*;?',
    multiLine: true,
  );

  for (final file in jsFiles) {
    final content = file.readAsStringSync();
    final match = sourceRegex.firstMatch(content);
    if (match == null) {
      continue;
    }

    final defaultSource = Source();
    for (var sourceJson in _decodeSourceList(match.group(1)!, file.path)) {
      final langs = sourceJson["langs"] as List?;
      Source source = Source.fromJson(sourceJson)
        ..sourceCodeLanguage = 1
        ..appMinVerReq = sourceJson["appMinVerReq"] ?? defaultSource.appMinVerReq
        ..sourceCodeUrl =
            "https://raw.githubusercontent.com/morningoctober/mangayomi-extensions/$branchName/javascript/${sourceJson["pkgPath"] ?? sourceJson["pkgName"]}";
      if (sourceJson["id"] != null) {
        source = source..id = int.tryParse("${sourceJson["id"]}");
      }
      if (langs?.isNotEmpty ?? false) {
        for (var lang in langs!) {
          final id = sourceJson["ids"]?[lang] as int?;
          sourceList.add(
            Source.fromJson(source.toJson())
              ..lang = lang
              ..id = id ?? 'mangayomi-js-"$lang"."${source.name}"'.hashCode,
          );
        }
      } else {
        sourceList.add(source);
      }
    }
  }
  return sourceList;
}

List<Map<String, dynamic>> _decodeSourceList(
  String rawArrayLiteral,
  String filePath,
) {
  try {
    return (jsonDecode(rawArrayLiteral) as List).cast<Map<String, dynamic>>();
  } catch (_) {
    // Fallback for JS object literals with unquoted keys and trailing commas.
  }

  // Accept JS object literals used in source files: unquoted keys and trailing commas.
  final withQuotedKeys = rawArrayLiteral.replaceAllMapped(
    RegExp(r'([\[{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:'),
    (m) => '${m.group(1)}"${m.group(2)}":',
  );
  final withoutTrailingCommas = withQuotedKeys.replaceAllMapped(
    RegExp(r',(\s*[}\]])'),
    (m) => m.group(1)!,
  );
  try {
    return (jsonDecode(withoutTrailingCommas) as List)
        .cast<Map<String, dynamic>>();
  } catch (e) {
    log('Failed to parse source metadata list in $filePath: $e');
    return [];
  }
}
