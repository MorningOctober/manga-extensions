import '../../../../../model/source.dart';

Source get omegaScansSource => _omegaScansSource;
const _omegaScansVersion = "1.0.14";
const _omegaScansSourceCodeUrl =
    "https://raw.githubusercontent.com/MorningOctober/manga-extensions/$branchName/dart/manga/src/en/OmegaScans/omegascans.dart";
const _omegaScansIconUrl =
    "https://raw.githubusercontent.com/MorningOctober/manga-extensions/$branchName/dart/manga/src/en/OmegaScans/icon.png";
Source _omegaScansSource = Source(
  name: "OmegaScans",
  baseUrl: "https://omegascans.org",
  apiUrl: "https://api.omegascans.org",
  lang: "en",
  typeSource: "single",
  iconUrl: _omegaScansIconUrl,
  sourceCodeUrl: _omegaScansSourceCodeUrl,
  itemType: ItemType.manga,
  version: _omegaScansVersion,
  dateFormat: "yyyy-MM-dd'T'HH:mm:ss.SSSXXX",
  dateFormatLocale: "en",
);
