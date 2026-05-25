import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

class HunspellDictionary {
  final String locale;
  final Set<String> _words = {};

  HunspellDictionary(this.locale);

  bool get isLoaded => _words.isNotEmpty;
  int get wordCount => _words.length;

  bool hasWord(String word) => _words.contains(word.toLowerCase());

  bool hasWordStartingWith(String prefix) {
    final p = prefix.toLowerCase();
    return _words.any((w) => w.startsWith(p));
  }

  Future<void> loadFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final data = _decodeBytes(bytes, locale);
    _parseLines(data);
  }

  void _parseLines(String data) {
    final lines = data.split('\n');
    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final slashIdx = line.indexOf('/');
      final word = slashIdx >= 0 ? line.substring(0, slashIdx) : line;
      _words.add(word.toLowerCase());
    }
  }

  void loadFromDecodedData(String data) => _parseLines(data);

  void unload() => _words.clear();

  /// Dekoduje bajty .dic z odpowiednim kodowaniem dla danego locale.
  static String _decodeBytes(List<int> bytes, String locale) {
    // Najpierw próbujemy UTF-8
    final utf8Str = utf8.decode(bytes, allowMalformed: true);
    if (!utf8Str.contains('\uFFFD')) return utf8Str;

    // Jeśli znaleziono znaki zastępcze, dekodujemy jako Latin-1
    // i korygujemy dla znanych kodowań
    final latin1Str = latin1.decode(bytes);
    return _fixEncoding(latin1Str, locale);
  }

  /// Koryguje ciąg z Latin-1 na właściwe kodowanie specyficzne dla locale.
  static String _fixEncoding(String s, String locale) {
    // ISO-8859-2 (Central European: pl, cs, sk, hu, ro)
    if (['pl', 'cs', 'sk', 'hu', 'ro'].contains(locale)) {
      return s.split('').map((ch) {
        final corrected = _latin2ToLatin1Fix[ch.codeUnitAt(0)];
        return corrected != null ? String.fromCharCode(corrected) : ch;
      }).join();
    }
    // ISO-8859-7 (Greek)
    if (locale == 'el') {
      return s.split('').map((ch) {
        final corrected = _latin7ToLatin1Fix[ch.codeUnitAt(0)];
        return corrected != null ? String.fromCharCode(corrected) : ch;
      }).join();
    }
    // ISO-8859-9 (Turkish)
    if (locale == 'tr') {
      return s.split('').map((ch) {
        final corrected = _latin9ToLatin1Fix[ch.codeUnitAt(0)];
        return corrected != null ? String.fromCharCode(corrected) : ch;
      }).join();
    }
    // KOI8-R / Windows-1251 (Russian, Ukrainian) – pomijamy konwersję,
    // cyrylica i tak nie będzie pasować do ASCII tokenów
    return s;
  }

  /// Mapa: Latin-1 code point → Latin-2 (ISO-8859-2) code point.
  /// Tylko bajty które różnią się między Latin-1 a Latin-2.
  static const Map<int, int> _latin2ToLatin1Fix = {
    0xA1: 0x0104, // ¡ → Ą
    0xA2: 0x02D8, // ¢ → ˘
    0xA3: 0x0141, // £ → Ł
    0xA5: 0x013D, // ¥ → Ľ
    0xA6: 0x015A, // ¦ → Ś
    0xA9: 0x0160, // © → Š
    0xAA: 0x015E, // ª → Ş
    0xAB: 0x0164, // « → Ť
    0xAC: 0x0179, // ¬ → Ź
    0xAE: 0x017D, // ® → Ž
    0xAF: 0x017B, // ¯ → Ż
    0xB1: 0x0105, // ± → ą
    0xB2: 0x02DB, // ² → ˛
    0xB3: 0x0142, // ³ → ł
    0xB5: 0x013E, // µ → ľ
    0xB6: 0x015B, // ¶ → ś
    0xB7: 0x02C7, // · → ˇ
    0xB9: 0x0161, // ¹ → š
    0xBA: 0x015F, // º → ş
    0xBB: 0x0165, // » → ť
    0xBC: 0x017A, // ¼ → ź
    0xBD: 0x02DD, // ½ → ˝
    0xBE: 0x017E, // ¾ → ž
    0xBF: 0x017C, // ¿ → ż
    0xC0: 0x0154, // À → Ŕ
    0xC3: 0x0102, // Ã → Ă
    0xC5: 0x0139, // Å → Ĺ
    0xC6: 0x0106, // Æ → Ć
    0xC8: 0x010C, // È → Č
    0xCA: 0x0118, // Ê → Ę
    0xCC: 0x011A, // Ì → Ě
    0xCF: 0x010E, // Ï → Ď
    0xD0: 0x0110, // Ð → Đ
    0xD1: 0x0143, // Ñ → Ń
    0xD2: 0x0147, // Ò → Ň
    0xD5: 0x0150, // Õ → Ő
    0xD8: 0x0158, // Ø → Ř
    0xD9: 0x016E, // Ù → Ů
    0xDB: 0x0170, // Û → Ű
    0xDE: 0x0162, // Þ → Ţ
    0xE0: 0x0155, // à → ŕ
    0xE3: 0x0103, // ã → ă
    0xE5: 0x013A, // å → ĺ
    0xE6: 0x0107, // æ → ć
    0xE8: 0x010D, // è → č
    0xEA: 0x0119, // ê → ę
    0xEC: 0x011B, // ì → ě
    0xEF: 0x010F, // ï → ď
    0xF0: 0x0111, // ð → đ
    0xF1: 0x0144, // ñ → ń
    0xF2: 0x0148, // ò → ň
    0xF5: 0x0151, // õ → ő
    0xF8: 0x0159, // ø → ř
    0xF9: 0x016F, // ù → ů
    0xFB: 0x0171, // û → ű
    0xFE: 0x0163, // þ → ţ
    0xFF: 0x02D9, // ÿ → ˙
  };

  /// Mapa: Latin-1 → ISO-8859-7 (Greek)
  static const Map<int, int> _latin7ToLatin1Fix = {
    0xA1: 0x2018, // ¡ → ‘
    0xA2: 0x2019, // ¢ → ’
    0xA6: 0x03A9, // ¦ → Ω
    0xA9: 0x00A9, // © (same)
    0xAB: 0x00AB, // « (same)
    0xAE: 0x00AE, // ® (same)
    0xAF: 0x2015, // ¯ → ―
    0xB0: 0x00B0, // ° (same)
    0xB4: 0x0384, // ´ → ΄
    0xB5: 0x0385, // µ → ΅
    0xB6: 0x0386, // ¶ → Ά
    0xB7: 0x00B7, // · (same)
    0xB8: 0x0388, // ¸ → Έ
    0xB9: 0x0389, // ¹ → Ή
    0xBA: 0x038A, // º → Ί
    0xBB: 0x038C, // » → Ό
    0xBD: 0x038E, // ½ → Ύ
    0xBF: 0x0390, // ¿ → ΐ
    0xC0: 0x0391, // À → Α
    0xC1: 0x0392, // Á → Β
    0xC2: 0x0393, // Â → Γ
    0xC3: 0x0394, // Ã → Δ
    0xC4: 0x0395, // Ä → Ε
    0xC5: 0x0396, // Å → Ζ
    0xC6: 0x0397, // Æ → Η
    0xC7: 0x0398, // Ç → Θ
    0xC8: 0x0399, // È → Ι
    0xC9: 0x039A, // É → Κ
    0xCA: 0x039B, // Ê → Λ
    0xCB: 0x039C, // Ë → Μ
    0xCC: 0x039D, // Ì → Ν
    0xCD: 0x039E, // Í → Ξ
    0xCE: 0x039F, // Î → Ο
    0xCF: 0x03A0, // Ï → Π
    0xD0: 0x03A1, // Ð → Ρ
    0xD3: 0x03A3, // Ó → Σ
    0xD4: 0x03A4, // Ô → Τ
    0xD5: 0x03A5, // Õ → Υ
    0xD6: 0x03A6, // Ö → Φ
    0xD7: 0x03A7, // × → Χ
    0xD8: 0x03A8, // Ø → Ψ
    0xD9: 0x03A9, // Ù → Ω
    0xDA: 0x03AA, // Ú → Ϊ
    0xDB: 0x03AB, // Û → Ϋ
    0xDC: 0x03AC, // Ü → ά
    0xDD: 0x03AD, // Ý → έ
    0xDE: 0x03AE, // Þ → ή
    0xDF: 0x03AF, // ß → ί
    0xE0: 0x03B0, // à → ΰ
    0xE1: 0x03B1, // á → α
    0xE2: 0x03B2, // â → β
    0xE3: 0x03B3, // ã → γ
    0xE4: 0x03B4, // ä → δ
    0xE5: 0x03B5, // å → ε
    0xE6: 0x03B6, // æ → ζ
    0xE7: 0x03B7, // ç → η
    0xE8: 0x03B8, // è → θ
    0xE9: 0x03B9, // é → ι
    0xEA: 0x03BA, // ê → κ
    0xEB: 0x03BB, // ë → λ
    0xEC: 0x03BC, // ì → μ
    0xED: 0x03BD, // í → ν
    0xEE: 0x03BE, // î → ξ
    0xEF: 0x03BF, // ï → ο
    0xF0: 0x03C0, // ð → π
    0xF1: 0x03C1, // ñ → ρ
    0xF2: 0x03C2, // ò → ς
    0xF3: 0x03C3, // ó → σ
    0xF4: 0x03C4, // ô → τ
    0xF5: 0x03C5, // õ → υ
    0xF6: 0x03C6, // ö → φ
    0xF7: 0x03C7, // ÷ → χ
    0xF8: 0x03C8, // ø → ψ
    0xF9: 0x03C9, // ù → ω
    0xFA: 0x03CA, // ú → ϊ
    0xFB: 0x03CB, // û → ϋ
    0xFC: 0x03CC, // ü → ό
    0xFD: 0x03CD, // ý → ύ
    0xFE: 0x03CE, // þ → ώ
  };

  /// Mapa: Latin-1 → ISO-8859-9 (Turkish)
  static const Map<int, int> _latin9ToLatin1Fix = {
    0xD0: 0x011E, // Ð → Ğ
    0xDD: 0x0130, // Ý → İ
    0xDE: 0x015E, // Þ → Ş
    0xF0: 0x011F, // ð → ğ
    0xFD: 0x0131, // ý → ı
    0xFE: 0x015F, // þ → ş
  };
}

class AvailableDictionary {
  final String locale;
  final String name;
  final String dicUrl;
  final String fallbackUrl;

  const AvailableDictionary(this.locale, this.name, this.dicUrl, this.fallbackUrl);
}

class DictionaryService {
  final Map<String, HunspellDictionary> _dicts = {};
  String? baseDir;

  DictionaryService({this.baseDir});

  static const _prefsKey = 'downloaded_dictionaries';

  static const String _githubUrl = 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master';
  static const String _jsdelivrUrl = 'https://cdn.jsdelivr.net/gh/LibreOffice/dictionaries@master';

  static const List<AvailableDictionary> available = [
    AvailableDictionary('en', 'English (US)', '$_jsdelivrUrl/en/en_US.dic', '$_githubUrl/en/en_US.dic'),
    AvailableDictionary('pl', 'Polski', '$_jsdelivrUrl/pl_PL/pl_PL.dic', '$_githubUrl/pl_PL/pl_PL.dic'),
    AvailableDictionary('de', 'Deutsch', '$_jsdelivrUrl/de/de_DE_frami.dic', '$_githubUrl/de/de_DE_frami.dic'),
    AvailableDictionary('fr', 'Français', '$_jsdelivrUrl/fr_FR/fr_FR.dic', '$_githubUrl/fr_FR/fr_FR.dic'),
    AvailableDictionary('es', 'Español', '$_jsdelivrUrl/es/es_ES.dic', '$_githubUrl/es/es_ES.dic'),
    AvailableDictionary('it', 'Italiano', '$_jsdelivrUrl/it_IT/it_IT.dic', '$_githubUrl/it_IT/it_IT.dic'),
    AvailableDictionary('pt', 'Português', '$_jsdelivrUrl/pt_PT/pt_PT.dic', '$_githubUrl/pt_PT/pt_PT.dic'),
    AvailableDictionary('nl', 'Nederlands', '$_jsdelivrUrl/nl_NL/nl_NL.dic', '$_githubUrl/nl_NL/nl_NL.dic'),
    AvailableDictionary('ru', 'Русский', '$_jsdelivrUrl/ru_RU/ru_RU.dic', '$_githubUrl/ru_RU/ru_RU.dic'),
    AvailableDictionary('sv', 'Svenska', '$_jsdelivrUrl/sv_SE/sv_SE.dic', '$_githubUrl/sv_SE/sv_SE.dic'),
    AvailableDictionary('da', 'Dansk', '$_jsdelivrUrl/da_DK/da_DK.dic', '$_githubUrl/da_DK/da_DK.dic'),
    AvailableDictionary('nb', 'Norsk Bokmål', '$_jsdelivrUrl/no/nb_NO.dic', '$_githubUrl/no/nb_NO.dic'),
    AvailableDictionary('cs', 'Čeština', '$_jsdelivrUrl/cs_CZ/cs_CZ.dic', '$_githubUrl/cs_CZ/cs_CZ.dic'),
    AvailableDictionary('sk', 'Slovenčina', '$_jsdelivrUrl/sk_SK/sk_SK.dic', '$_githubUrl/sk_SK/sk_SK.dic'),
    AvailableDictionary('hu', 'Magyar', '$_jsdelivrUrl/hu_HU/hu_HU.dic', '$_githubUrl/hu_HU/hu_HU.dic'),
    AvailableDictionary('ro', 'Română', '$_jsdelivrUrl/ro/ro_RO.dic', '$_githubUrl/ro/ro_RO.dic'),
    AvailableDictionary('uk', 'Українська', '$_jsdelivrUrl/uk_UA/uk_UA.dic', '$_githubUrl/uk_UA/uk_UA.dic'),
    AvailableDictionary('el', 'Ελληνικά', '$_jsdelivrUrl/el_GR/el_GR.dic', '$_githubUrl/el_GR/el_GR.dic'),
    AvailableDictionary('tr', 'Türkçe', '$_jsdelivrUrl/tr_TR/tr_TR.dic', '$_githubUrl/tr_TR/tr_TR.dic'),
  ];

  Set<String> get supportedLocales => _dicts.keys.toSet();

  bool get isLoaded => _dicts.isNotEmpty;

  bool isSupportedLocale(String locale) => _dicts.containsKey(locale);

  bool wordExists(String locale, String word) {
    final dict = _dicts[locale];
    return dict != null && dict.hasWord(word);
  }

  bool wordStartsWith(String locale, String prefix) {
    final dict = _dicts[locale];
    return dict != null && dict.hasWordStartingWith(prefix);
  }

  int wordCount(String locale) => _dicts[locale]?.wordCount ?? 0;

  Future<void> loadAllFromDir(String dirPath) async {
    _dicts.clear();
    final dir = Directory(dirPath);
    if (!await dir.exists()) return;
    final files = await dir.list().toList();
    for (final file in files) {
      final path = file.path;
      if (!path.endsWith('.dic')) continue;
      final name = path.split(Platform.pathSeparator).last;
      final locale = name.replaceAll('.dic', '');
      final dict = HunspellDictionary(locale);
      await dict.loadFromFile(path);
      _dicts[locale] = dict;
    }
  }

  Future<void> loadSingleFromBytes(String locale, List<int> bytes) async {
    final data = HunspellDictionary._decodeBytes(bytes, locale);
    final dict = HunspellDictionary(locale);
    dict.loadFromDecodedData(data);
    _dicts[locale] = dict;
  }

  Future<AvailableDictionary?> downloadDictionary(
      String locale, String dirPath, {void Function(double progress)? onProgress}) async {
    final availableDict = available.where((d) => d.locale == locale).firstOrNull;
    if (availableDict == null) return null;

    final urls = [availableDict.dicUrl, availableDict.fallbackUrl];

    for (final url in urls) {
      final bytes = await _tryDownload(url, onProgress);
      if (bytes != null && bytes.isNotEmpty) {
        final dir = Directory(dirPath);
        if (!await dir.exists()) await dir.create(recursive: true);

        final filePath = '$dirPath/$locale.dic';
        await File(filePath).writeAsBytes(bytes);

        await loadSingleFromBytes(locale, bytes);
        return availableDict;
      }
    }
    return null;
  }

  Future<List<int>?> _tryDownload(String url, void Function(double progress)? onProgress) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return null;

      final totalBytes = response.contentLength ?? -1;
      final bytes = <int>[];
      int received = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        received += chunk.length;
        if (onProgress != null) {
          final p = totalBytes > 0 ? received / totalBytes : received / 2000000.0;
          onProgress(p.clamp(0.0, 1.0));
        }
      }

      return bytes;
    } on TimeoutException {
      return null;
    } catch (e) {
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> removeDictionary(String locale, String dirPath) async {
    _dicts.remove(locale);
    final filePath = '$dirPath/$locale.dic';
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  static Future<Set<String>> getDownloadedLocales() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_prefsKey) ?? []).toSet();
  }

  static Future<void> saveDownloadedLocales(Set<String> locales) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, locales.toList());
  }
}
