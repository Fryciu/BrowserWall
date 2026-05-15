import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes, setEquals;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pathh;
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';

// ─────────────────────────────────────────────
//  MODEL
// ─────────────────────────────────────────────

class TabModel {
  InAppWebViewController? controller;
  String url;
  String title;
  bool loaded;
  bool isPlayingAudio = false;
  TabModel({required this.url, this.title = "Nowa karta", this.loaded = false});
}

// ─────────────────────────────────────────────
//  SERWIS (cała logika biznesowa / backendowa)
// ─────────────────────────────────────────────
enum BlockReason { none, proxy, content, blacklist, timeLimit }

/// Tryb reguły czasowej
enum TimeRuleMode { dailyLimit, timeWindow }

/// Reguła czasowa dla domeny.
/// [mode] = dailyLimit: max [dailyLimitMinutes] minut dziennie
/// [mode] = timeWindow: blokada w godzinach [windowStart]-[windowEnd]
/// [allowedDays] = lista dni tygodnia (1=pn, 7=nd) gdy reguła obowiązuje (puste = wszystkie dni)
class TimeRule {
  final String domain;
  final TimeRuleMode mode;
  final int dailyLimitMinutes; // dla trybu dailyLimit
  final TimeOfDay windowStart; // dla trybu timeWindow
  final TimeOfDay windowEnd; // dla trybu timeWindow
  final List<int> allowedDays; // 1=pn..7=nd, puste=każdy dzień

  const TimeRule({
    required this.domain,
    this.mode = TimeRuleMode.dailyLimit,
    this.dailyLimitMinutes = 30,
    this.windowStart = const TimeOfDay(hour: 8, minute: 0),
    this.windowEnd = const TimeOfDay(hour: 22, minute: 0),
    this.allowedDays = const [],
  });

  Map<String, dynamic> toJson() => {
    'domain': domain,
    'mode': mode.name,
    'dailyLimitMinutes': dailyLimitMinutes,
    'windowStartH': windowStart.hour,
    'windowStartM': windowStart.minute,
    'windowEndH': windowEnd.hour,
    'windowEndM': windowEnd.minute,
    'allowedDays': allowedDays,
  };

  factory TimeRule.fromJson(Map<String, dynamic> j) => TimeRule(
    domain: j['domain'] as String,
    mode: TimeRuleMode.values.firstWhere(
      (e) => e.name == j['mode'],
      orElse: () => TimeRuleMode.dailyLimit,
    ),
    dailyLimitMinutes: j['dailyLimitMinutes'] as int? ?? 30,
    windowStart: TimeOfDay(
      hour: j['windowStartH'] as int? ?? 8,
      minute: j['windowStartM'] as int? ?? 0,
    ),
    windowEnd: TimeOfDay(
      hour: j['windowEndH'] as int? ?? 22,
      minute: j['windowEndM'] as int? ?? 0,
    ),
    allowedDays: List<int>.from(j['allowedDays'] ?? []),
  );

  TimeRule copyWith({
    TimeRuleMode? mode,
    int? dailyLimitMinutes,
    TimeOfDay? windowStart,
    TimeOfDay? windowEnd,
    List<int>? allowedDays,
  }) => TimeRule(
    domain: domain,
    mode: mode ?? this.mode,
    dailyLimitMinutes: dailyLimitMinutes ?? this.dailyLimitMinutes,
    windowStart: windowStart ?? this.windowStart,
    windowEnd: windowEnd ?? this.windowEnd,
    allowedDays: allowedDays ?? this.allowedDays,
  );
}

class BrowserService extends ChangeNotifier {
  String? pendingShortcutUrl;

  // --- Stan ---
  List<TabModel> tabs = [TabModel(url: 'https://www.google.com')];
  int currentTabIndex = 0;

  List<String> blackList = [];

  /// Reguły czasowe: domain -> TimeRule
  Map<String, TimeRule> timeRules = {};

  /// Czas spędzony na domenach dziś (w sekundach): domain -> seconds
  Map<String, int> _todayUsage = {};
  String _todayKey = ''; // klucz daty np. "2024-01-15"

  /// Zwraca ile minut spędzono dziś na domenie
  String _normalizeDomain(String domain) {
    final clean = domain.trim().toLowerCase();
    return clean.startsWith('www.') ? clean.substring(4) : clean;
  }

  int getTodayUsageMinutes(String domain) {
    _ensureTodayKey();
    final bare = _normalizeDomain(domain);
    return (_todayUsage[bare] ?? 0) ~/ 60;
  }

  int getTodayUsageSeconds(String domain) {
    _ensureTodayKey();
    final usageKey = _usageKeyForDomain(domain);
    var seconds = _todayUsage[usageKey] ?? 0;

    // Compatibility with usage stored before rule-key normalization.
    for (final entry in _todayUsage.entries) {
      if (entry.key != usageKey &&
          (entry.key == usageKey || entry.key.endsWith('.$usageKey'))) {
        seconds += entry.value;
      }
    }
    return seconds;
  }

  int getRemainingSecondsForRule(TimeRule rule) {
    if (rule.mode != TimeRuleMode.dailyLimit) return 0;
    final limitSeconds = rule.dailyLimitMinutes * 60;
    final usedSeconds = getTodayUsageSeconds(rule.domain);
    return (limitSeconds - usedSeconds).clamp(0, limitSeconds);
  }

  /// Rejestruje sekundy spędzone na domenie (wywoływane co ~5s przez WebView)
  bool recordUsage(String domain, int seconds) {
    _ensureTodayKey();
    // Normalizuj domenę tak samo jak przy dodawaniu reguł (bez www.)
    final usageKey = _usageKeyForDomain(domain);
    final previousSeconds = _todayUsage[usageKey] ?? 0;
    final nextSeconds = previousSeconds + seconds;
    _todayUsage[usageKey] = nextSeconds;
    _saveUsage();
    // Sprawdź czy limit nie został przekroczony — jeśli tak, odśwież UI
    final dailyRules = _findTimeRules(
      usageKey,
    ).where((rule) => rule.mode == TimeRuleMode.dailyLimit);
    final rule = dailyRules.isEmpty ? null : dailyRules.first;
    if (rule != null) {
      final previousMinutes = previousSeconds ~/ 60;
      final used = nextSeconds ~/ 60;
      if (used >= rule.dailyLimitMinutes &&
          isBlockedByTimeRule('https://$usageKey')) {
        notifyListeners();
        return true;
      }
      if (used != previousMinutes) {
        notifyListeners();
      }
    }
    return false;
  }

  String _usageKeyForDomain(String domain) {
    final normalized = _normalizeDomain(domain);
    return _normalizeDomain(_findTimeRuleDomain(normalized) ?? normalized);
  }

  void _ensureTodayKey() {
    final today = DateTime.now();
    final key = DateFormat('yyyy-MM-dd').format(today);
    if (_todayKey != key) {
      _todayKey = key;
      _todayUsage = {}; // nowy dzień — resetuj liczniki
    }
  }

  bool _ruleMatchesDomain(TimeRule rule, String domain) {
    final normalized = _normalizeDomain(domain);
    final ruleDomain = _normalizeDomain(rule.domain);
    return normalized == ruleDomain || normalized.endsWith('.$ruleDomain');
  }

  List<TimeRule> _findTimeRules(String domain) {
    return timeRules.values
        .where((rule) => _ruleMatchesDomain(rule, domain))
        .toList(growable: false);
  }

  // ignore: unused_element
  TimeRule? _findTimeRule(String domain) {
    final normalized = _normalizeDomain(domain);
    if (timeRules.containsKey(normalized)) return timeRules[normalized];
    // Sprawdź też bez www.
    final bare = _normalizeDomain(domain);
    if (timeRules.containsKey(bare)) return timeRules[bare];
    // Sprawdź czy któraś reguła pasuje jako sufiks domeny
    for (final entry in timeRules.entries) {
      final ruleDomain = _normalizeDomain(entry.key);
      if (normalized.endsWith('.$ruleDomain') || normalized == ruleDomain) {
        return entry.value;
      }
    }
    return null;
  }

  String? _findTimeRuleDomain(String domain) {
    final rules = _findTimeRules(domain);
    if (rules.isNotEmpty) return rules.first.domain;
    return null;
  }

  // ignore: unused_element
  String? _findTimeRuleDomainLegacy(String domain) {
    final normalized = _normalizeDomain(domain);
    if (timeRules.containsKey(normalized)) return normalized;
    for (final entry in timeRules.entries) {
      final ruleDomain = _normalizeDomain(entry.key);
      if (normalized.endsWith('.$ruleDomain') || normalized == ruleDomain) {
        return entry.key;
      }
    }
    return null;
  }

  /// Czy regula czasowa blokuje dostep teraz?
  bool isBlockedByTimeRule(String urlString) {
    final uri = Uri.tryParse(
      urlString.startsWith('http') ? urlString : 'https://$urlString',
    );
    final domain = uri?.host ?? '';
    if (domain.isEmpty) return false;
    final rules = _findTimeRules(domain);
    if (rules.isEmpty) return false;
    return rules.any((rule) => _isTimeRuleActiveNow(rule, domain));
  }

  bool _isTimeRuleActiveNow(TimeRule rule, String domain) {
    final now = DateTime.now();
    final weekday = now.weekday;
    if (rule.allowedDays.isNotEmpty && !rule.allowedDays.contains(weekday)) {
      return false;
    }

    if (rule.mode == TimeRuleMode.dailyLimit) {
      _ensureTodayKey();
      final usageKey = _usageKeyForDomain(domain);
      final usedMinutes = (_todayUsage[usageKey] ?? 0) ~/ 60;
      return usedMinutes >= rule.dailyLimitMinutes;
    }

    final nowMinutes = now.hour * 60 + now.minute;
    final startMinutes = rule.windowStart.hour * 60 + rule.windowStart.minute;
    final endMinutes = rule.windowEnd.hour * 60 + rule.windowEnd.minute;
    if (startMinutes == endMinutes) return true;
    if (startMinutes < endMinutes) {
      return nowMinutes >= startMinutes && nowMinutes < endMinutes;
    }
    return nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  Future<void> addTimeRule(TimeRule rule) async {
    timeRules[_timeRuleKey(rule)] = rule;
    await _saveTimeRules();
    notifyListeners();
  }

  Future<void> removeTimeRule(String domain) async {
    timeRules.remove(domain);
    await _saveTimeRules();
    notifyListeners();
  }

  String _timeRuleKey(TimeRule rule) {
    return '${_normalizeDomain(rule.domain)}|${rule.mode.name}';
  }

  Future<void> _saveTimeRules() async {
    final prefs = await _getPrefs;
    final encoded = json.encode(
      timeRules.map((k, v) => MapEntry(k, v.toJson())),
    );
    await prefs.setString('time_rules', encoded);
  }

  Future<void> _saveUsage() async {
    final prefs = await _getPrefs;
    _ensureTodayKey();
    await prefs.setString('usage_$_todayKey', json.encode(_todayUsage));
  }

  String homePageUrl = 'https://www.google.com';
  static const String _mobileUA =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const String _desktopUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  bool _desktopMode = false;
  bool get desktopMode => _desktopMode;

  String _userAgent = _mobileUA;
  String get userAgent => _userAgent;

  Future<void> setDesktopMode(bool value) async {
    _desktopMode = value;
    _userAgent = value ? _desktopUA : _mobileUA;
    final prefs = await _getPrefs;
    await prefs.setBool('desktop_mode', value);
    // Przeładuj wszystkie otwarte karty z nowym UA
    for (final tab in tabs) {
      if (tab.controller != null) {
        await tab.controller!.setSettings(
          settings: InAppWebViewSettings(userAgent: _userAgent),
        );
        await tab.controller!.reload();
      }
    }
    notifyListeners();
  }

  String searchEngineUrl = ''; // puste = nie wybrano jeszcze
  bool searchEngineSelected = false; // czy użytkownik już wybrał

  /// Własne wyszukiwarki dodane przez użytkownika.
  /// Każdy wpis: {'name': '...', 'url': '...', 'searchUrl': '...', 'safesearch': 'true'/'false'}
  /// searchUrl zawiera %s jako placeholder zapytania, np.
  /// 'https://example.com/search?q=%s'
  List<Map<String, String>> customSearchEngines = [];

  /// Wbudowane wyszukiwarki ukryte przez użytkownika (lista URL-i).
  List<String> hiddenBuiltinEngines = [];

  // Grupy czarnej listy: nazwa grupy → lista wpisów
  // Wpisy z grup są automatycznie synchronizowane z blackList
  // Mapa: oryginalne słowo → lista tłumaczeń (włącznie z oryginałem)
  Map<String, List<String>> _wordTranslations = {};
  Map<String, int> _wordThresholds = {};
  // Postęp pobierania tłumaczeń: słowo → 0.0..1.0 (null = gotowe/nie pobiera)
  final Map<String, double> translationProgress = {};
  // Cache tłumaczeń pornKeywords (ładowany raz)
  Set<String> _pornKeywordsExpanded = {};
  bool _pornKeywordsExpandedLoaded = false;

  Map<String, List<String>> blackListGroups = {
    'Strony': [],
    'Słowa kluczowe': [],
  };
  Set<String> remoteBlockedDomains = {};
  Set<String> remoteBlockedProxy = {};
  List<Map<String, String>> history = [];
  String? savedPassword;
  bool isVerifying = false;
  bool adBlockEnabled = true;
  List<String> adBlockWhitelist = [];
  bool adultFilterEnabled = true;

  /// Języki, w których użytkownik wpisuje słowa do blokowania.
  /// Tłumaczenia są pobierane TYLKO z tych języków.
  List<String> wordInputLanguages = ['pl', 'en'];

  static const Map<String, String> availableWordLanguages = {
    'sq': '🇦🇱 Albański',
    'en': '🇬🇧 Angielski',
    'ar': '🇸🇦 Arabski',
    'az': '🇦🇿 Azerski',
    'be': '🇧🇾 Białoruski',
    'bg': '🇧🇬 Bułgarski',
    'zh': '🇨🇳 Chiński',
    'hr': '🇭🇷 Chorwacki',
    'cs': '🇨🇿 Czeski',
    'da': '🇩🇰 Duński',
    'et': '🇪🇪 Estoński',
    'fi': '🇫🇮 Fiński',
    'fr': '🇫🇷 Francuski',
    'el': '🇬🇷 Grecki',
    'he': '🇮🇱 Hebrajski',
    'es': '🇪🇸 Hiszpański',
    'hi': '🇮🇳 Hinduski',
    'nl': '🇳🇱 Holenderski',
    'id': '🇮🇩 Indonezyjski',
    'ga': '🇮🇪 Irlandzki',
    'is': '🇮🇸 Islandzki',
    'ja': '🇯🇵 Japoński',
    'ko': '🇰🇷 Koreański',
    'lt': '🇱🇹 Litewski',
    'lv': '🇱🇻 Łotewski',
    'no': '🇳🇴 Norweski',
    'de': '🇩🇪 Niemiecki',
    'pl': '🇵🇱 Polski',
    'pt': '🇵🇹 Portugalski',
    'ru': '🇷🇺 Rosyjski',
    'ro': '🇷🇴 Rumuński',
    'sr': '🇷🇸 Serbski',
    'sk': '🇸🇰 Słowacki',
    'sl': '🇸🇮 Słoweński',
    'sv': '🇸🇪 Szwedzki',
    'th': '🇹🇭 Tajski',
    'tr': '🇹🇷 Turecki',
    'uk': '🇺🇦 Ukraiński',
    'hu': '🇭🇺 Węgierski',
    'vi': '🇻🇳 Wietnamski',
    'it': '🇮🇹 Włoski',
  };

  DateTime? _lastAuthTime;
  String? _lastAuthUrl;

  final List<String> pornKeywords = [
    // Ogólne
    "porn", "xxx", "nsfw", "erotic", "adult-content",
    // Hentai / anime
    "hentai", "ecchi", "doujin", "lolicon", "shotacon", "yaoi", "yuri",
    // Znane serwisy
    "redtube", "rule34", "xvideos", "brazzers", "sex-video",
    "xhamster", "xnxx", "spankbang", "tube8", "tnaflix",
    "beeg", "xtube", "faphouse", "slutload",
    "thumbzilla",
    // Slang / kategorie
    "milf", "dilf", "gilf", "cougar",
    "creampie", "gangbang", "bdsm", "fetish",
    "onlyfans", "camgirl", "camboy",
    "livejasmin", "chaturbate", "stripchat", "bongacams", "myfreecams",
    "nude", "nudist",
    "blowjob", "handjob", "footjob", "cum", "orgasm",
    "masturbat", "dildo", "vibrator",
    "sex",
    "hookup", "swingers", "threesome", "foursome",
    "incest", "taboo", "fisting", "squirt",
    "stripping", "striptease",
    "shemale", "tranny", "femdom", "pegging",
    "r34", "hclips",
  ];

  // ── Gettery wygodne ──────────────────────────
  TabModel get currentTab => tabs[currentTabIndex];
  Map<String, List<String>> get wordTranslations => _wordTranslations;
  Map<String, int> get wordThresholds => _wordThresholds;
  Future<SharedPreferences> getPrefsPublic() => _getPrefs;
  String get wordTranslationsJson => json.encode(_wordTranslations);
  bool isTranslating(String word) => translationProgress.containsKey(word);

  Future<void> setWordThreshold(String word, int threshold) async {
    if (threshold < 0) {
      _wordThresholds.remove(word);
    } else {
      _wordThresholds[word] = threshold.clamp(0, 3);
    }
    final prefs = await _getPrefs;
    await prefs.setString(
      'word_thresholds',
      json.encode(_wordThresholds.map((k, v) => MapEntry(k, v))),
    );
    notifyListeners();
  }

  void notifyShortcut() {
    notifyListeners();
  }

  /// Publiczne API do odświeżenia UI (np. po zmianie URL karty)
  void notifyUI() {
    notifyListeners();
  }

  // Dodaj to w klasie BrowserService w browser_service.dart

  Future<void> setWordLanguages(List<String> newLanguages) async {
    wordInputLanguages = newLanguages;
    final prefs = await _getPrefs;
    await prefs.setStringList('word_input_languages', newLanguages);
    notifyListeners(); // Powiadomienie UI o zmianie
  }

  // Zaktualizuj też metodę loadData() lub init(), aby wczytywała te języki przy starcie:
  Future<void> loadLanguages() async {
    final prefs = await _getPrefs;
    final saved = prefs.getStringList('word_input_languages');
    if (saved != null) {
      wordInputLanguages = saved;
    }
  }

  // ── Inicjalizacja ────────────────────────────
  final Completer<void> _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  Future<void> init() async {
    await _initUserAgent();
    final t0 = DateTime.now();
    await loadData();
    print("loadData: ${DateTime.now().difference(t0).inMilliseconds}ms");
    if (!_readyCompleter.isCompleted) _readyCompleter.complete();

    final t1 = DateTime.now();
    loadBlocklists();
    print(
      "loadRemoteBlacklist: ${DateTime.now().difference(t1).inMilliseconds}ms",
    );

    final t2 = DateTime.now();
    await loadTabs();
    print("loadTabs: ${DateTime.now().difference(t2).inMilliseconds}ms");

    final t3 = DateTime.now();
    await loadShortcuts();
    print("loadShortcuts: ${DateTime.now().difference(t3).inMilliseconds}ms");

    // Pobierz tłumaczenia pornKeywords w tle (nie blokuje UI)
    if (!_pornKeywordsExpandedLoaded) {
      Future.microtask(() => initPornKeywordsExpanded());
    }
  }

  SharedPreferences? _prefsInstance;

  Future<SharedPreferences> get _getPrefs async {
    _prefsInstance ??= await SharedPreferences.getInstance();
    return _prefsInstance!;
  }

  void debugPrintPassword() {
    assert(() {
      debugPrint("🔑 Aktualne hasło: $savedPassword");
      return true;
    }());
  }

  Future<void> saveAdBlockWhitelist() async {
    final prefs = await _getPrefs;
    await prefs.setStringList('adblock_whitelist', adBlockWhitelist);
  }

  void addToAdBlockWhitelist(String domain) {
    final clean = domain.toLowerCase().trim();
    if (clean.isNotEmpty && !adBlockWhitelist.contains(clean)) {
      adBlockWhitelist.add(clean);
      saveAdBlockWhitelist();
      notifyListeners();
    }
  }

  void removeFromAdBlockWhitelist(int index) {
    adBlockWhitelist.removeAt(index);
    saveAdBlockWhitelist();
    notifyListeners();
  }

  bool isAdBlockWhitelisted(String url) {
    final uri = Uri.tryParse(url.toLowerCase());
    if (uri == null) return false;
    final host = uri.host;
    return adBlockWhitelist.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    );
  }

  // W BrowserService
  int adBlockVersion = 0; // ← inkrementuj przy zmianie adblockera

  Future<void> setAdBlock(bool value) async {
    final prefs = await _getPrefs;
    await prefs.setBool('adblock_enabled', value);
    adBlockEnabled = value;
    adBlockVersion++; // ← to sygnalizuje że trzeba przebudować WebView
    notifyListeners();
  }

  // ─────────────────────────────────────────────
  //  TŁUMACZENIA SŁÓW (Wiktionary API)
  // ─────────────────────────────────────────────

  /// Pobiera tłumaczenia słowa z Wiktionary API.
  /// Zwraca listę unikalnych słów (oryginał + tłumaczenia) po normalizacji.
  // Etapy postępu — 3 fazy: wyszukiwanie, langlinks, synonim Wiktionary
  // Faza 1 (0-33%): szukaj artykułu Wikipedia dla słowa
  // Faza 2 (33-90%): pobierz langlinks (odpowiedniki w innych językach)
  // Faza 3 (90-100%): Wiktionary synonim fallback

  // Glosbe API jest znacznie lepsze do "wszystkich języków"

  Future<List<String>> fetchTranslations(String word) async {
    final normalized = word.trim();
    if (normalized.isEmpty) return [];

    final results = <String>{};

    try {
      // --- KROK 1: Uniwersalne szukanie ID w Wikidata ---
      // 'wbsearchentities' przeszukuje nazwy we wszystkich językach świata.
      final searchUrl = Uri.parse(
        'https://www.wikidata.org/w/api.php?action=wbsearchentities&search=${Uri.encodeComponent(normalized)}&language=en&format=json&origin=*',
      );

      final searchResp = await http
          .get(searchUrl)
          .timeout(const Duration(seconds: 4));
      String? wikidataId;

      if (searchResp.statusCode == 200) {
        final searchData = json.decode(searchResp.body);
        final searchResults = searchData['search'] as List<dynamic>?;

        if (searchResults != null && searchResults.isNotEmpty) {
          // Bierzemy pierwszy, najbardziej pasujący wynik
          wikidataId = searchResults.first['id'];
        }
      }

      // --- KROK 2: Pobieranie danych encji ---
      if (wikidataId != null) {
        final entityUrl = Uri.parse(
          'https://www.wikidata.org/wiki/Special:EntityData/$wikidataId.json',
        );

        final entityResp = await http
            .get(entityUrl)
            .timeout(const Duration(seconds: 5));

        if (entityResp.statusCode == 200) {
          final entityData = json.decode(entityResp.body);
          final entity = entityData['entities'][wikidataId];

          // 1. Pobieranie LABELS (Główne nazwy we wszystkich językach)
          final labels = entity['labels'] as Map<String, dynamic>?;
          if (labels != null) {
            for (var labelData in labels.values) {
              final val = labelData['value'] as String;
              _processAndAdd(val, results);
            }
          }

          // 2. Pobieranie ALIASES (Synonimy we wszystkich językach)
          final aliases = entity['aliases'] as Map<String, dynamic>?;
          if (aliases != null) {
            for (var langAliases in aliases.values) {
              for (var aliasData in langAliases) {
                final val = aliasData['value'] as String;
                _processAndAdd(val, results);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Błąd API: $e');
    }

    return results.toList();
  }

  void _processAndAdd(String val, Set<String> results) {
    final clean = val.toLowerCase().trim();
    if (clean.length > 1 &&
        !clean.contains(':') &&
        !RegExp(r'Q\d+').hasMatch(clean)) {
      // Ignoruj techniczne ID Wikidata
      results.add(clean);
    }
  }

  /// Pobiera i zapisuje tłumaczenia dla słowa użytkownika.
  /// Zwraca listę tłumaczeń (do wyświetlenia w UI).
  Future<List<String>> fetchAndSaveTranslations(String word) async {
    final translations = await fetchTranslations(word);
    _wordTranslations[word] = translations;
    final prefs = await _getPrefs;
    await prefs.setString('word_translations', json.encode(_wordTranslations));
    return translations;
  }

  /// Inicjalizuje rozszerzoną listę pornKeywords w tle (raz).
  Future<void> initPornKeywordsExpanded() async {
    if (_pornKeywordsExpandedLoaded) return;
    _pornKeywordsExpandedLoaded = true; // zapobiegaj podwójnemu wywołaniu

    // Zacznij od samych znormalizowanych pornKeywords
    final expanded = <String>{};
    for (final w in pornKeywords) {
      expanded.add(_normalize(w));
    }

    // Pobierz tłumaczenia tylko dla "prawdziwych" słów (nie nazwy serwisów)
    // Serwisy jak "xvideos", "redtube" itp. pomijamy — są specyficzne
    final wordsToTranslate = pornKeywords
        .where(
          (w) =>
              !w.contains(RegExp(r'[0-9]')) && // bez cyfr
              w.length >= 4 && // min 4 znaki
              !w.contains('-') && // bez myślnika
              !_isSiteName(w), // nie jest nazwą serwisu
        )
        .toList();

    debugPrint(
      '🌐 Pobieranie tłumaczeń dla ${wordsToTranslate.length} słów kluczowych...',
    );

    for (final word in wordsToTranslate) {
      try {
        final trans = await fetchTranslations(word);
        expanded.addAll(trans);
        // Zapisz też do _wordTranslations żeby były widoczne w dialogu
        if (trans.isNotEmpty) {
          _wordTranslations[word] = trans;
        }
        await Future.delayed(const Duration(milliseconds: 200)); // rate limit
      } catch (_) {}
    }

    _pornKeywordsExpanded = expanded;
    final prefs = await _getPrefs;
    await prefs.setStringList('porn_keywords_expanded', expanded.toList());
    // Zapisz też słownik tłumaczeń
    await prefs.setString('word_translations', json.encode(_wordTranslations));
    debugPrint('✅ pornKeywords expanded: ${expanded.length} słów');
  }

  // Nazwy własne i marki których NIE wolno dodać jako tłumaczenia
  static const _blockedExpansions = {
    'google',
    'youtube',
    'facebook',
    'twitter',
    'instagram',
    'wikipedia',
    'amazon',
    'apple',
    'microsoft',
    'netflix',
    'gmail',
    'yahoo',
    'bing',
    'reddit',
    'tiktok',
    'snapchat',
    'android',
    'iphone',
    'ipad',
    'windows',
    'linux',
    'macos',
    'chrome',
    'safari',
    'firefox',
    'opera',
    'edge',
    'disney',
    'spotify',
    'paypal',
    'ebay',
    'alibaba',
  };

  bool _isSiteName(String w) {
    const siteNames = {
      'redtube',
      'xvideos',
      'xhamster',
      'xnxx',
      'spankbang',
      'tube8',
      'tnaflix',
      'beeg',
      'xtube',
      'faphouse',
      'slutload',
      'thumbzilla',
      'onlyfans',
      'livejasmin',
      'chaturbate',
      'stripchat',
      'bongacams',
      'myfreecams',
      'brazzers',
      'hclips',
      'rule34',
      'r34',
    };
    return siteNames.contains(w);
  }

  /// Sprawdza czy URL zawiera jakiekolwiek słowo z rozszerzonej listy
  bool _matchesPornKeywordsExpanded(String normalizedUrl) {
    for (final baseWord in pornKeywords) {
      if (_fuzzyMatchesUrl(baseWord, normalizedUrl)) {
        debugPrint('🚨 MATCH baseWord: $baseWord → $normalizedUrl');
        return true;
      }
      final trans = _wordTranslations[baseWord];
      if (trans != null) {
        for (final t in trans) {
          if (_fuzzyMatchesUrl(t, normalizedUrl)) {
            debugPrint(
              '🚨 MATCH translation: $t (z: $baseWord) → $normalizedUrl',
            );
            return true;
          }
        }
      }
    }
    return false;
  }

  /// Sprawdza czy URL pasuje do któregoś słowa z blacklisty (+ tłumaczenia)
  bool _matchesBlacklistExpanded(String normalizedUrl) {
    for (final entry in blackList) {
      final override = _wordThresholds[entry];
      if (override == 0) {
        if (normalizedUrl.contains(entry.toLowerCase())) return true;
      } else {
        if (normalizedUrl.contains(entry.toLowerCase()) ||
            _fuzzyMatchesUrl(entry, normalizedUrl, overrideThreshold: override))
          return true;
      }
      final translations = _wordTranslations[entry];
      if (translations != null) {
        for (final t in translations) {
          final overrideTrans = _wordThresholds[t];
          if (_fuzzyMatchesUrl(
            t,
            normalizedUrl,
            overrideThreshold: overrideTrans,
          ))
            return true;
        }
      }
    }
    return false;
  }

  /// Zwraca dopasowane słowo z blacklisty (+ tłumaczenia) lub null
  String? _matchedBlacklistWord(String normalizedUrl) {
    for (final entry in blackList) {
      final override = _wordThresholds[entry];
      final baseMatch = override == 0
          ? normalizedUrl.contains(entry.toLowerCase())
          : (normalizedUrl.contains(entry.toLowerCase()) ||
                _fuzzyMatchesUrl(
                  entry,
                  normalizedUrl,
                  overrideThreshold: override,
                ));
      if (baseMatch) return entry;
      final translations = _wordTranslations[entry];
      if (translations != null) {
        for (final t in translations) {
          final overrideTrans = _wordThresholds[t];
          if (_fuzzyMatchesUrl(
            t,
            normalizedUrl,
            overrideThreshold: overrideTrans,
          ))
            return '$entry ($t)';
        }
      }
    }
    return null;
  }

  Future<void> _initUserAgent() async {
    try {
      final info = DeviceInfoPlugin();
      final android = await info.androidInfo;
      final model = android.model; // np. "Samsung Galaxy S23"
      final version = android.version.release; // np. "14"
      _userAgent =
          'Mozilla/5.0 (Linux; Android $version; $model) '
          'AppleWebKit/537.36 (KHTML, like Gecko) '
          'Chrome/120.0.0.0 Mobile Safari/537.36';
      debugPrint('📱 User Agent: $_userAgent');
    } catch (e) {
      debugPrint('⚠️ Nie udało się pobrać modelu urządzenia: $e');
      // Zostaje domyślny _userAgent
    }
  }

  Future<void> loadBlocklists() async {
    final prefs = await _getPrefs;

    final savedAdult = prefs.getStringList('remote_blocked_domains');
    if (savedAdult != null && savedAdult.isNotEmpty) {
      remoteBlockedDomains = savedAdult.toSet();
      notifyListeners();
    }

    final savedProxy = prefs.getStringList('remote_blocked_proxy');
    if (savedProxy != null && savedProxy.isNotEmpty) {
      remoteBlockedProxy = savedProxy.toSet();
    }

    _updateBlocklistsInBackground(prefs);
  }

  Future<void> _updateBlocklistsInBackground(SharedPreferences prefs) async {
    final configs = [
      (
        url: "https://raw.githubusercontent.com/tiuxo/hosts/master/porn",
        prefsKey: 'remote_blocked_domains',
        fallback: <String>{
          "rule34.xxx",
          "paheal.net",
          "gelbooru.com",
          "nhentai.net",
          "e621.net",
          "pornhub.com",
          "xvideos.com",
          "redtube.com",
          "xhamster.com",
        },
        current: remoteBlockedDomains,
        isAdult: true,
      ),
      (
        url:
            "https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/doh-vpn-proxy-bypass.txt",
        prefsKey: 'remote_blocked_proxy',
        fallback: <String>{
          "hide.me",
          "proxysite.com",
          "croxyproxy.com",
          "proxyfree.net",
          "kproxy.com",
          "ultrasurf.us",
          "nordvpn.com",
          "expressvpn.com",
          "surfshark.com",
          "protonvpn.com",
          "mullvad.net",
        },
        current: remoteBlockedProxy,
        isAdult: false,
      ),
    ];

    for (final config in configs) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 15);
        final request = await client.getUrl(Uri.parse(config.url));
        final response = await request.close();
        final content = await response.transform(utf8.decoder).join();

        final Set<String> fetched = {...config.fallback};
        for (var line in content.split('\n')) {
          final trimmed = line.trim().toLowerCase();
          // Format "0.0.0.0 domena" (lista porno)
          if (trimmed.startsWith('0.0.0.0')) {
            final domain = trimmed.replaceFirst('0.0.0.0', '').trim();
            if (domain.isNotEmpty) fetched.add(domain);
            // Format "domena" (lista vpn/proxy)
          } else if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
            fetched.add(trimmed);
          }
        }

        if (!setEquals(config.current, fetched)) {
          debugPrint(
            "${config.prefsKey} zaktualizowana: ${fetched.length} domen",
          );
          if (config.isAdult) {
            remoteBlockedDomains = fetched;
            notifyListeners();
          } else {
            remoteBlockedProxy = fetched;
          }
          await prefs.setStringList(config.prefsKey, fetched.toList());
        } else {
          debugPrint("${config.prefsKey} bez zmian");
        }
      } catch (e) {
        debugPrint("Błąd pobierania ${config.prefsKey}: $e");
        if (config.isAdult && remoteBlockedDomains.isEmpty) {
          remoteBlockedDomains = config.fallback;
        } else if (!config.isAdult && remoteBlockedProxy.isEmpty) {
          remoteBlockedProxy = config.fallback;
        }
      }
    }
  }

  // ── Skróty ───────────────────────────────────
  List<Map<String, String>> shortcuts = [];

  Future<void> loadShortcuts() async {
    try {
      final prefs = await _getPrefs;
      final data = prefs.getString('shortcuts');

      if (data != null) {
        final List<dynamic> decoded = json.decode(data);

        // Bezpieczna konwersja dynamicznych map na Map<String, String>
        shortcuts = decoded.map((item) {
          final map = item as Map<String, dynamic>;
          return map.map((key, value) => MapEntry(key, value.toString()));
        }).toList();

        notifyListeners(); // Pamiętaj o odświeżeniu UI po załadowaniu!
      }
    } catch (e) {
      print("Błąd podczas ładowania skrótów: $e");
      shortcuts = []; // Reset w razie błędu danych
    }
  }

  Future<void> saveShortcut(String name, String url) async {
    shortcuts.add({'name': name, 'url': url});
    final prefs = await _getPrefs;
    await prefs.setString('shortcuts', json.encode(shortcuts));

    notifyListeners();
  }

  Future<void> removeShortcut(int index) async {
    shortcuts.removeAt(index);
    final prefs = await _getPrefs;
    await prefs.setString('shortcuts', json.encode(shortcuts));
    notifyListeners();
  }

  bool isShortcutProtected(String url) {
    return getBlockReason(url) != BlockReason.none;
  }

  // Dodaj to do klasy BrowserService

  /// Zwraca true, jeśli nawigacja powinna zostać przerwana (strona zablokowana)
  bool shouldBlockRequest(String url) {
    final reason = getBlockReason(url);

    // Jeśli to proxy - blokuj zawsze
    if (reason == BlockReason.proxy) return true;

    // Jeśli to pornografia lub blacklist - blokuj, chyba że mamy aktywną sesję auth
    if (reason == BlockReason.content || reason == BlockReason.blacklist) {
      if (canSkipAuth(url)) return false;
      return true;
    }

    // Reguła czasowa — zawsze blokuj (bez możliwości ominięcia hasłem)
    if (reason == BlockReason.timeLimit) return true;

    return false;
  }

  Future<void> removeHistoryEntries(List<Map<String, String>> entries) async {
    history.removeWhere((e) => entries.contains(e));
    final prefs = await _getPrefs;
    await prefs.setString('browser_history', json.encode(history));
    notifyListeners();
  }

  bool incognitoMode = false;

  Future<void> toggleIncognito() async {
    incognitoMode = !incognitoMode;
    final prefs = await _getPrefs;
    await prefs.setBool('incognito_mode', incognitoMode);
    notifyListeners();
  }

  Future<void> clearAllHistory() async {
    history.clear();
    final prefs = await _getPrefs;
    await prefs.remove('browser_history');
    notifyListeners();
  }

  Future<void> clearHistoryForDay(String day) async {
    if (day == 'Nieznana data') {
      // Usuń wszystkie wpisy bez daty
      history.removeWhere((e) => e['date'] == null || e['date']!.isEmpty);
    } else {
      history.removeWhere((e) => e['date'] == day);
    }
    final prefs = await _getPrefs;
    await prefs.setString('browser_history', json.encode(history));
    notifyListeners();
  }

  Future<void> clearHistoryOlderThan(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    history.removeWhere((e) {
      final date = DateTime.tryParse(e['date'] ?? '');
      return date != null && date.isBefore(cutoff);
    });
    final prefs = await _getPrefs;
    await prefs.setString('browser_history', json.encode(history));
    notifyListeners();
  }

  /// Pobiera plik PDF korzystając z sesji WebView (cookies, nagłówki, sesja).
  /// Metoda 1: fetch() przez JS w kontekście WebView — omija ochronę botów.
  /// Metoda 2: fallback przez HttpClient z pełnymi nagłówkami (inne serwery).
  // Dodaj te importy na górze, jeśli ich nie ma:
  // import 'package:flutter_inappwebview/flutter_inappwebview.dart';
  // import 'dart:io';

  /// Pobiera plik PDF przez fetch() wewnątrz WebView — pełny kontekst przeglądarki.
  /// Fallback: HttpClient z nagłówkami (dla serwerów bez JS challenge).
  Future<String?> downloadFileWithFullHeaders({
    required InAppWebViewController? controller,
    required String url,
    String? refererUrl,
  }) async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      final request = await client.getUrl(Uri.parse(url));

      final userAgent = _userAgent;

      request.headers.set('User-Agent', userAgent);
      request.headers.set('Accept', 'application/pdf,*/*;q=0.8');
      request.headers.set(
        'Accept-Language',
        'pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7',
      );
      request.headers.set('Sec-Fetch-Dest', 'document');
      request.headers.set('Sec-Fetch-Mode', 'navigate');
      request.headers.set('Sec-Fetch-Site', 'same-origin');
      request.headers.set('Upgrade-Insecure-Requests', '1');

      // Referer = strona z której pochodzi pobieranie
      final ref =
          refererUrl ??
          (controller != null ? (await controller.getUrl())?.toString() : null);
      if (ref != null) request.headers.set('Referer', ref);

      // Cookies z WebView
      final cookieManager = CookieManager.instance();
      final cookies = await cookieManager.getCookies(url: WebUri(url));
      if (cookies.isNotEmpty) {
        request.headers.set(
          'Cookie',
          cookies.map((c) => '${c.name}=${c.value}').join('; '),
        );
      }

      final response = await request.close();

      if (response.statusCode == 200) {
        final bytes = await consolidateHttpClientResponseBytes(response);
        String fileName =
            "document_${DateTime.now().millisecondsSinceEpoch}.pdf";
        final disp = response.headers.value('content-disposition');
        if (disp != null && disp.contains('filename=')) {
          fileName = disp.split('filename=').last.replaceAll('"', '').trim();
        }
        if (!fileName.toLowerCase().endsWith('.pdf')) fileName += '.pdf';
        final dir = await getTemporaryDirectory();
        final file = File(pathh.join(dir.path, fileName));
        await file.writeAsBytes(bytes);
        print("✅ Pobieranie udane: ${file.path}");
        return file.path;
      } else {
        print("❌ Pobieranie nieudane. Status: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      print("❌ Błąd pobierania: $e");
      return null;
    }
  }

  Future<String?> downloadViaJsInWebView({
    required InAppWebViewController controller,
    required String url,
  }) async {
    try {
      final completer = Completer<String?>();

      // Handler odbierający base64 z JS
      controller.addJavaScriptHandler(
        handlerName: 'pdfDownloadResult',
        callback: (args) async {
          controller.removeJavaScriptHandler(handlerName: 'pdfDownloadResult');
          if (args.isEmpty) {
            completer.complete(null);
            return;
          }
          try {
            final Map<String, dynamic> parsed = json.decode(args[0] as String);
            if (parsed.containsKey('base64')) {
              final bytes = base64Decode(parsed['base64'] as String);
              String fileName =
                  "document_${DateTime.now().millisecondsSinceEpoch}.pdf";
              final cd = parsed['cd'] as String? ?? '';
              if (cd.contains('filename=')) {
                fileName = cd
                    .split('filename=')
                    .last
                    .replaceAll('"', '')
                    .replaceAll("'", '')
                    .trim();
              }
              if (!fileName.toLowerCase().endsWith('.pdf')) fileName += '.pdf';
              final dir = await getTemporaryDirectory();
              final file = File(pathh.join(dir.path, fileName));
              await file.writeAsBytes(bytes);
              print("✅ JS fetch udany: ${file.path}");
              completer.complete(file.path);
            } else {
              print("❌ JS fetch błąd: ${parsed['error']}");
              completer.complete(null);
            }
          } catch (e) {
            print("❌ Parse błąd: $e");
            completer.complete(null);
          }
        },
      );

      // Fetch w kontekście aktualnej strony — pełna sesja, cookies, origin
      await controller.evaluateJavascript(
        source:
            '''
      (async function() {
        try {
          const resp = await fetch(${json.encode(url)}, {
            credentials: "include",
            headers: { "Accept": "application/pdf,*/*" }
          });
          if (!resp.ok) {
            window.flutter_inappwebview.callHandler(
              "pdfDownloadResult", JSON.stringify({error: resp.status}));
            return;
          }
          const buf = await resp.arrayBuffer();
          const bytes = new Uint8Array(buf);
          let bin = "";
          const chunk = 8192;
          for (let i = 0; i < bytes.length; i += chunk) {
            bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
          }
          const b64 = btoa(bin);
          const cd = resp.headers.get("content-disposition") || "";
          window.flutter_inappwebview.callHandler(
            "pdfDownloadResult", JSON.stringify({base64: b64, cd: cd}));
        } catch(e) {
          window.flutter_inappwebview.callHandler(
            "pdfDownloadResult", JSON.stringify({error: e.toString()}));
        }
      })();
    ''',
      );

      return await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          controller.removeJavaScriptHandler(handlerName: 'pdfDownloadResult');
          print("❌ JS fetch timeout");
          return null;
        },
      );
    } catch (e) {
      print("❌ downloadViaJsInWebView błąd: $e");
      return null;
    }
  }

  /// Pomocnicza funkcja do wyciągania nazwy pliku z nagłówka lub URL
  Future<void> loadData() async {
    final t0 = DateTime.now();
    final p = await SharedPreferences.getInstance();
    debugPrint(
      "prefs getInstance: ${DateTime.now().difference(t0).inMilliseconds}ms",
    );

    final t1 = DateTime.now();
    savedPassword = p.getString('user_password');
    adBlockEnabled = p.getBool('adblock_enabled') ?? true;
    adultFilterEnabled = p.getBool('adult_filter_enabled') ?? true;
    incognitoMode = p.getBool('incognito_mode') ?? false;
    blackList =
        p.getStringList('blocked_pages') ?? ["facebook.com", "instagram.com"];

    // Wczytaj grupy
    final groupsData = p.getString('blacklist_groups');
    if (groupsData != null) {
      try {
        final decoded = json.decode(groupsData) as Map<String, dynamic>;
        blackListGroups = decoded.map(
          (k, v) => MapEntry(k, List<String>.from(v as List)),
        );
      } catch (_) {}
    } else {
      // Pierwsza migracja: wpisz istniejące wpisy do grupy "Strony"
      blackListGroups = {
        'Strony': List<String>.from(blackList),
        'Słowa kluczowe': [],
      };
    }
    adBlockWhitelist = p.getStringList('adblock_whitelist') ?? [];
    homePageUrl = p.getString('home_page_url') ?? 'https://www.google.com';

    // Wczytaj cache tłumaczeń słów użytkownika
    final transData = p.getString('word_translations');
    if (transData != null) {
      try {
        final decoded = json.decode(transData) as Map<String, dynamic>;
        _wordTranslations = decoded.map(
          (k, v) => MapEntry(k, List<String>.from(v as List)),
        );
      } catch (_) {}
    }

    // Wczytaj cache tłumaczeń pornKeywords — filtruj zatrute wpisy
    final pornExpanded = p.getStringList('porn_keywords_expanded');
    if (pornExpanded != null && pornExpanded.isNotEmpty) {
      final baseNormalized = pornKeywords.map(_normalize).toSet();
      _pornKeywordsExpanded = pornExpanded.where((w) {
        // Zawsze przepuść słowa bazowe
        if (baseNormalized.contains(w)) return true;
        // Odrzuć nazwy własne i śmieci z Wikidata
        if (_blockedExpansions.contains(w)) return false;
        if (w.length > 20) return false;
        if (w.contains(' ')) return false;
        if (RegExp(r'[0-9]').hasMatch(w)) return false;
        return true;
      }).toSet();
      // Jeśli filtrowanie usunęło więcej niż 20% — wymusz przebudowę cache
      if (_pornKeywordsExpanded.length < pornExpanded.length * 0.8) {
        debugPrint(
          '⚠️ pornKeywords cache zatrute (${pornExpanded.length - _pornKeywordsExpanded.length} usuniętych), przebudowuję...',
        );
        _pornKeywordsExpandedLoaded = false;
        await p.remove('porn_keywords_expanded');
      } else {
        _pornKeywordsExpandedLoaded = true;
      }
    }
    final threshData = p.getString('word_thresholds');
    if (threshData != null) {
      try {
        final decoded = json.decode(threshData) as Map<String, dynamic>;
        _wordThresholds = decoded.map(
          (k, v) => MapEntry(k, (v as num).toInt()),
        );
      } catch (_) {}
    }
    searchEngineUrl = p.getString('search_engine_url') ?? '';
    searchEngineSelected = p.getBool('search_engine_selected') ?? false;
    _desktopMode = p.getBool('desktop_mode') ?? false;
    if (_desktopMode) _userAgent = _desktopUA;

    // Wczytaj reguły czasowe
    final timeRulesData = p.getString('time_rules');
    if (timeRulesData != null) {
      try {
        final decoded = json.decode(timeRulesData) as Map<String, dynamic>;
        timeRules = decoded.map(
          (k, v) => MapEntry(k, TimeRule.fromJson(v as Map<String, dynamic>)),
        );
        timeRules = Map.fromEntries(
          timeRules.values.map((rule) => MapEntry(_timeRuleKey(rule), rule)),
        );
      } catch (_) {}
    }

    // Migracja: przenieś domeny z grupy 'Strony' do timeRules z limitem 0
    // Uruchamia się tylko raz (gdy time_rules_migrated nie jest ustawione)
    if (!(p.getBool('time_rules_migrated') ?? false)) {
      final strony = blackListGroups['Strony'] ?? [];
      for (final domain in strony) {
        final clean = domain
            .trim()
            .replaceAll('https://', '')
            .replaceAll('http://', '')
            .replaceAll('www.', '')
            .split('/')
            .first;
        final migratedRule = TimeRule(
          domain: clean,
          mode: TimeRuleMode.dailyLimit,
          dailyLimitMinutes: 0,
        );
        if (clean.isNotEmpty &&
            !timeRules.containsKey(_timeRuleKey(migratedRule))) {
          timeRules[_timeRuleKey(migratedRule)] = migratedRule;
        }
      }
      // Wyczyść grupę Strony
      blackListGroups['Strony'] = [];
      if (timeRules.isNotEmpty) {
        final encoded = json.encode(
          timeRules.map((k, v) => MapEntry(k, v.toJson())),
        );
        await p.setString('time_rules', encoded);
      }
      await p.setBool('time_rules_migrated', true);
    }

    // Wczytaj dzisiejsze zużycie
    _ensureTodayKey();
    final usageData = p.getString('usage_$_todayKey');
    if (usageData != null) {
      try {
        final raw = json.decode(usageData) as Map;
        _todayUsage = raw.map(
          (k, v) => MapEntry(k.toString(), (v as num).toInt()),
        );
      } catch (_) {}
    }

    // Wczytaj własne wyszukiwarki użytkownika
    final customEnginesData = p.getString('custom_search_engines');
    if (customEnginesData != null) {
      try {
        final decoded = json.decode(customEnginesData) as List<dynamic>;
        customSearchEngines = decoded
            .map((e) => Map<String, String>.from(e as Map))
            .toList();
      } catch (_) {}
    }

    // Wczytaj ukryte wbudowane wyszukiwarki
    hiddenBuiltinEngines = p.getStringList('hidden_builtin_engines') ?? [];

    debugPrint(
      "prefs read basic: ${DateTime.now().difference(t1).inMilliseconds}ms",
    );
    p.setBool("download_enabled", true);
    downloadEnabled = p.getBool('download_enabled') ?? false;
    blockedExtensions =
        p.getStringList('blocked_extensions') ??
        ["apk", "exe", "bat", "cmd", "sh", "msi", "dmg"];

    wordInputLanguages =
        p.getStringList('word_input_languages') ?? ['pl', 'en'];

    final t2 = DateTime.now();
    final historyData = p.getString('browser_history');
    if (historyData != null) {
      final decoded = json.decode(historyData) as List<dynamic>;
      history = decoded.map((e) => Map<String, String>.from(e as Map)).toList();
    }
    debugPrint(
      "prefs read history: ${DateTime.now().difference(t2).inMilliseconds}ms",
    );

    notifyListeners();
  }

  // ── Czarna lista ─────────────────────────────
  Future<void> setHomePage(String url) async {
    final prefs = await _getPrefs;
    homePageUrl = url.trim();
    await prefs.setString('home_page_url', homePageUrl);
    notifyListeners();
  }

  Future<void> setSearchEngine(String url) async {
    searchEngineUrl = url;
    searchEngineSelected = true; // Ustawiamy na true po wyborze

    final prefs = await _getPrefs;
    await prefs.setString('search_engine_url', url);
    await prefs.setBool(
      'search_engine_selected',
      true,
    ); // ZAPISUJEMY stan wyboru

    notifyListeners();
  }

  // ── Własne wyszukiwarki ──────────────────────────────────────────────────

  Future<void> _saveCustomSearchEngines() async {
    final prefs = await _getPrefs;
    await prefs.setString(
      'custom_search_engines',
      json.encode(customSearchEngines),
    );
  }

  /// Dodaje własną wyszukiwarkę.
  Future<void> addCustomSearchEngine({
    required String name,
    required String homeUrl,
    required String searchUrl,
    bool safesearch = false,
  }) async {
    customSearchEngines.add({
      'name': name.trim(),
      'url': homeUrl.trim(),
      'searchUrl': searchUrl.trim(),
      'safesearch': safesearch.toString(),
    });
    await _saveCustomSearchEngines();
    notifyListeners();
  }

  Future<void> removeCustomSearchEngine(int index) async {
    // Jeśli usuwana wyszukiwarka jest aktualnie wybrana — resetuj wybór
    if (customSearchEngines[index]['url'] == searchEngineUrl) {
      await setSearchEngine('https://www.google.com');
    }
    customSearchEngines.removeAt(index);
    await _saveCustomSearchEngines();
    notifyListeners();
  }

  /// Ukrywa wbudowaną wyszukiwarkę z listy.
  Future<void> hideBuiltinEngine(String url) async {
    if (!hiddenBuiltinEngines.contains(url)) {
      hiddenBuiltinEngines.add(url);
    }
    final prefs = await _getPrefs;
    await prefs.setStringList('hidden_builtin_engines', hiddenBuiltinEngines);
    notifyListeners();
  }

  Future<void> saveBlackList() async {
    final prefs = await _getPrefs;
    await prefs.setStringList('blocked_pages', blackList);
    await prefs.setString('blacklist_groups', json.encode(blackListGroups));
  }

  Future<void> addToBlackListGroup(String group, String entry) async {
    final clean = entry.toLowerCase().trim();
    if (clean.isEmpty) return;
    blackListGroups.putIfAbsent(group, () => []);
    if (!blackListGroups[group]!.contains(clean)) {
      blackListGroups[group]!.add(clean);
    }
    _syncBlackListFromGroups();
    await saveBlackList();
    notifyListeners();

    // Pobierz tłumaczenia w tle (nie blokuje UI)
    Future.microtask(() async {
      await fetchAndSaveTranslations(clean);
      debugPrint('🌐 Tłumaczenia dla "$clean": ${_wordTranslations[clean]}');
    });
  }

  Future<void> removeFromBlackListGroup(String group, String entry) async {
    blackListGroups[group]?.remove(entry);
    _syncBlackListFromGroups();
    await saveBlackList();
    notifyListeners();
  }

  Future<void> addGroup(String name) async {
    if (name.trim().isEmpty || blackListGroups.containsKey(name)) return;
    blackListGroups[name] = [];
    await saveBlackList();
    notifyListeners();
  }

  Future<void> removeGroup(String name) async {
    blackListGroups.remove(name);
    _syncBlackListFromGroups();
    await saveBlackList();
    notifyListeners();
  }

  void _syncBlackListFromGroups() {
    final all = <String>{};
    for (final entries in blackListGroups.values) {
      all.addAll(entries);
    }
    blackList = all.toList();
  }

  void addToBlackList(String domain) {
    blackList.add(domain.toLowerCase().trim());
    saveBlackList();
    notifyListeners();
  }

  void removeFromBlackList(int index) {
    blackList.removeAt(index);
    saveBlackList();
    notifyListeners();
  }

  Future<void> clearBlackList() async {
    blackList.clear();
    await saveBlackList();
    notifyListeners();
  }

  // ── Blokowanie URL ───────────────────────────
  bool _isProxyOrVpnUrl(String urlString) {
    final lowerUrl = urlString.toLowerCase();
    final uri = Uri.tryParse(lowerUrl);

    if (uri != null && remoteBlockedProxy.contains(uri.host)) return true;
    if (remoteBlockedProxy.any((domain) => lowerUrl.contains(domain))) {
      return true;
    }

    const keywords = [
      "proxy",
      "proxies",
      "unblock",
      "bypass",
      "anonymizer",
      "anonymouse",
      "hidemy",
      "hideip",
      "croxyproxy",
      "kproxy",
      "ultrasurf",
      "psiphon",
      "vpn",
      "nordvpn",
      "expressvpn",
      "surfshark",
      "cyberghost",
      "privatevpn",
      "ipvanish",
      "purevpn",
      "tunnelbear",
      "windscribe",
      "protonvpn",
      "mullvad",
      "hidemyass",
      "strongvpn",
      "astrill",
    ];
    if (keywords.any((word) => lowerUrl.contains(word))) return true;

    return false;
  }

  // ─────────────────────────────────────────────
  //  FUZZY MATCHING
  // ─────────────────────────────────────────────

  /// Normalizuje tekst: leet speak, diakrytyki, separatory
  String _normalize(String s) {
    s = s.toLowerCase();
    // Diakrytyki
    const from = 'ąćęłńóśźżàáâãäåæçèéêëìíîïðñòóôõöøùúûüýÿ';
    const to = 'acelnoszzaaaaaaaceeeeiiiidnoooooouuuuyy';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    // Leet speak
    s = s
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('6', 'g')
        .replaceAll('7', 't')
        .replaceAll('8', 'b')
        .replaceAll('@', 'a')
        .replaceAll('\$', 's')
        .replaceAll('+', 't');
    // Separatory → spacja (będziemy splitować)
    s = s.replaceAll(RegExp(r'[.\-_/]'), ' ');
    // Usuń wszystko poza a-z i spacją
    s = s.replaceAll(RegExp(r'[^a-z ]'), '');
    return s;
  }

  /// Odległość Levenshteina
  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final la = a.length, lb = b.length;
    // Optymalizacja: jeśli różnica długości > 3, nie ma sensu liczyć
    if ((la - lb).abs() > 3) return 99;
    final prev = List<int>.generate(lb + 1, (i) => i);
    final curr = List<int>.filled(lb + 1, 0);
    for (var i = 1; i <= la; i++) {
      curr[0] = i;
      for (var j = 1; j <= lb; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      prev.setAll(0, curr);
    }
    return prev[lb];
  }

  /// Próg odległości edycyjnej w zależności od długości słowa kluczowego
  int _threshold(int wordLen) {
    if (wordLen <= 3) return 0; // krótkie słowa — tylko dokładne
    if (wordLen <= 5) return 1;
    if (wordLen <= 8) return 2;
    return 3;
  }

  /// Rozbija URL na tokeny do analizy (host + segmenty ścieżki + query values)
  List<String> _urlTokens(String normalizedUrl) {
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null) return [normalizedUrl];
    final tokens = <String>[];
    // Host bez TLD (np. "pornhub" z "pornhub.com")
    final hostParts = uri.host.split('.');
    tokens.addAll(hostParts.where((p) => p.length > 2));
    // Segmenty ścieżki
    tokens.addAll(uri.pathSegments);
    // Wartości parametrów query (np. q=szukana+fraza)
    tokens.addAll(uri.queryParameters.values);
    return tokens
        .map(_normalize)
        .expand((t) => t.split(' '))
        .where((t) => t.length >= 3)
        .toList();
  }

  bool _fuzzyMatchesUrl(
    String keyword,
    String normalizedUrl, {
    int? overrideThreshold,
  }) {
    final normKeyword = _normalize(keyword);
    if (normKeyword.length < 3) return false;
    final threshold = overrideThreshold ?? _threshold(normKeyword.length);
    final tokens = _urlTokens(normalizedUrl);
    for (final token in tokens) {
      if (token == normKeyword) return true;
      if (threshold > 0 &&
          (token.length - normKeyword.length).abs() <= threshold) {
        if (_levenshtein(token, normKeyword) <= threshold) return true;
      }
      if (threshold > 0 &&
          normKeyword.length >= 5 &&
          token.contains(normKeyword))
        return true;
    }
    return false;
  }

  // Subdomeny zawsze przepuszczane (np. logowanie Google/YouTube)
  static const _allowedSubdomains = [
    'accounts.google.com',
    'accounts.youtube.com',
    'myaccount.google.com',
    'signin.google.com',
    'login.microsoftonline.com',
    'accounts.firefox.com',
    'appleid.apple.com',
  ];

  bool _isAllowedSubdomain(String host) {
    return _allowedSubdomains.any(
      (allowed) => host == allowed || host.endsWith('.$allowed'),
    );
  }

  BlockReason getBlockReason(String urlString) {
    if (urlString.isEmpty) return BlockReason.none;

    final lowerUrl = urlString.toLowerCase().trim();

    // 1. Normalizacja URL (wymagana, aby Uri.host zadziałało)
    String normalizedUrl = lowerUrl;
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      normalizedUrl = 'https://$lowerUrl';
    }

    final uri = Uri.tryParse(normalizedUrl);
    // Jeśli uri jest nullem, używamy surowego tekstu, ale host jest kluczowy
    final host = uri?.host ?? lowerUrl;

    // 0. Whitelist — subdomeny logowania zawsze przepuszczane
    if (_isAllowedSubdomain(host)) return BlockReason.none;

    // 2. Blokada Proxy / VPN
    if (_isProxyOrVpnUrl(normalizedUrl)) return BlockReason.proxy;

    // 3. Filtr treści dla dorosłych
    if (adultFilterEnabled) {
      // Sprawdzenie pełnego hosta w pobranych listach (np. "pornhub.com")
      if (remoteBlockedDomains.contains(host)) {
        return BlockReason.content;
      }

      // Sprawdzenie, czy host zawiera zakazane słowo (np. "hardnsfw.com" zawiera "nsfw")
      // Używamy 'host', a nie 'lowerUrl', żeby uniknąć blokowania np. wyników wyszukiwania
      // w Google, które tylko wyświetlają te słowa w tytule.
      if (_matchesPornKeywordsExpanded(normalizedUrl)) {
        return BlockReason.content;
      }
    }

    // 4. Twoja prywatna czarna lista (+ tłumaczenia)
    if (_matchesBlacklistExpanded(normalizedUrl)) {
      return BlockReason.blacklist;
    }

    // 5. Reguły czasowe
    if (isBlockedByTimeRule(normalizedUrl)) {
      return BlockReason.timeLimit;
    }

    return BlockReason.none;
  }

  /// Jak getBlockReason, ale dodatkowo zwraca dopasowany ciąg (słowo kluczowe / domenę).
  (BlockReason, String?) getBlockReasonWithMatch(String urlString) {
    if (urlString.isEmpty) return (BlockReason.none, null);

    final lowerUrl = urlString.toLowerCase().trim();
    String normalizedUrl = lowerUrl;
    if (!lowerUrl.startsWith('http://') && !lowerUrl.startsWith('https://')) {
      normalizedUrl = 'https://$lowerUrl';
    }

    final uri = Uri.tryParse(normalizedUrl);
    final host = uri?.host ?? lowerUrl;

    // 0. Whitelist — subdomeny logowania zawsze przepuszczane
    if (_isAllowedSubdomain(host)) return (BlockReason.none, null);

    // 1. Proxy / VPN
    if (uri != null && remoteBlockedProxy.contains(uri.host)) {
      return (BlockReason.proxy, uri.host);
    }
    for (final domain in remoteBlockedProxy) {
      if (lowerUrl.contains(domain)) return (BlockReason.proxy, domain);
    }
    const proxyKeywords = [
      "proxy",
      "proxies",
      "unblock",
      "bypass",
      "anonymizer",
      "anonymouse",
      "hidemy",
      "hideip",
      "croxyproxy",
      "kproxy",
      "ultrasurf",
      "psiphon",
      "vpn",
      "nordvpn",
      "expressvpn",
      "surfshark",
      "cyberghost",
      "privatevpn",
      "ipvanish",
      "purevpn",
      "tunnelbear",
      "windscribe",
      "protonvpn",
      "mullvad",
      "hidemyass",
      "strongvpn",
      "astrill",
    ];
    for (final word in proxyKeywords) {
      if (lowerUrl.contains(word)) return (BlockReason.proxy, word);
    }

    // 2. Filtr treści dla dorosłych
    if (adultFilterEnabled) {
      if (remoteBlockedDomains.contains(host)) {
        return (BlockReason.content, host);
      }
      if (_matchesPornKeywordsExpanded(normalizedUrl)) {
        // Znajdź które słowo pasuje (do wyświetlenia w UI)
        // Zamiast obecnego bloku "matched", użyj tej samej logiki co _matchesPornKeywordsExpanded
        String matched = 'treści dla dorosłych';

        // Szukaj w pornKeywords + ich tłumaczeniach (tak samo jak _matchesPornKeywordsExpanded)
        outer:
        for (final baseWord in pornKeywords) {
          if (_fuzzyMatchesUrl(baseWord, normalizedUrl)) {
            matched = baseWord;
            break;
          }
          final trans = _wordTranslations[baseWord];
          if (trans != null) {
            for (final t in trans) {
              if (_fuzzyMatchesUrl(t, normalizedUrl)) {
                matched = '$baseWord ($t)';
                break outer;
              }
            }
          }
        }
        return (BlockReason.content, matched);
      }
    }

    // 3. Czarna lista (+ tłumaczenia)
    final matchedBlacklist = _matchedBlacklistWord(normalizedUrl);
    if (matchedBlacklist != null) {
      return (BlockReason.blacklist, matchedBlacklist);
    }

    if (isBlockedByTimeRule(normalizedUrl)) {
      return (BlockReason.timeLimit, _findTimeRuleDomain(host) ?? host);
    }

    return (BlockReason.none, null);
  }

  bool handleNavigation(
    String urlString,
    InAppWebViewController controller,
    void Function(WebUri, InAppWebViewController?, BlockReason, String?)
    onPasswordRequired,
    void Function(String) onBlocked,
  ) {
    print("🔍 handleNavigation: $urlString");

    // Najpierw sprawdź słowa kluczowe — nawet w zapytaniach Google
    final (reason, matchedWord) = getBlockReasonWithMatch(urlString);
    print("🔍 reason: $reason, matched: $matchedWord");

    if (reason == BlockReason.proxy) {
      final msg = matchedWord != null
          ? "Ta strona jest zablokowana — proxy i VPN są niedozwolone. [\"$matchedWord\"]"
          : "Ta strona jest zablokowana — proxy i VPN są niedozwolone.";
      onBlocked(msg);
      return true;
    }

    if (reason == BlockReason.content || reason == BlockReason.blacklist) {
      if (savedPassword != null) {
        if (canSkipAuth(urlString)) {
          return false; // już autoryzowana, przepuść
        }
        onPasswordRequired(WebUri(urlString), controller, reason, matchedWord);
      } else {
        final msg = matchedWord != null
            ? "Ta strona jest zablokowana. [\"$matchedWord\"]"
            : "Ta strona jest zablokowana.";
        onBlocked(msg);
      }
      return true;
    }

    // SafeSearch — tylko gdy URL jest czysty (brak słów kluczowych)
    if (reason == BlockReason.timeLimit) {
      onPasswordRequired(WebUri(urlString), controller, reason, matchedWord);
      return true;
    }

    if (adultFilterEnabled) {
      final safeUrl = _applySafeSearch(urlString);
      if (safeUrl != null) {
        controller.loadUrl(urlRequest: URLRequest(url: WebUri(safeUrl)));
        return true;
      }
    }

    return false;
  }

  /// Zwraca true jeśli blokada jest aktywna i żądanie zostało anulowane.

  // ── Weryfikacja hasłem ───────────────────────
  bool canSkipAuth(String urlString) {
    if (_lastAuthTime == null) return false;
    if (DateTime.now().difference(_lastAuthTime!).inSeconds > 30) return false;

    // Porównuj domeny bazowe zamiast pełnych URLi
    final authUri = Uri.tryParse(_lastAuthUrl ?? '');
    final currentUri = Uri.tryParse(urlString);
    if (authUri == null || currentUri == null) return false;

    // youtube.com == m.youtube.com == www.youtube.com
    final authDomain = _baseDomain(authUri.host);
    final currentDomain = _baseDomain(currentUri.host);

    return authDomain == currentDomain;
  }

  String _baseDomain(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    return '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
  }

  void recordAuth(String urlString) {
    _lastAuthTime = DateTime.now();
    _lastAuthUrl = urlString;
  }

  /// Zwraca zmodyfikowany URL z wymuszonym SafeSearch, lub null jeśli nic nie trzeba zmieniać.
  String? _applySafeSearch(String urlString) {
    final lower = urlString.toLowerCase();

    // Pary: [fragment hosta, parametr do sprawdzenia, parametr do dodania]
    const rules = [
      // Google
      ('google.', '/search', 'safe=active', 'safe=active'),
      // Bing
      ('bing.com', '/search', 'adlt=strict', 'adlt=strict'),
      // DuckDuckGo
      ('duckduckgo.com', '?q=', 'kp=1', 'kp=1'),
      // Yahoo
      ('search.yahoo.com', '/search', 'vm=r', 'vm=r'),
      // Brave Search
      ('search.brave.com', '/search', 'safesearch=strict', 'safesearch=strict'),
      // Ecosia
      ('ecosia.org', '/search', 'safesearch=strict', 'safesearch=strict'),
      // Startpage
      ('startpage.com', '/search', 'safe=1', 'safe=1'),
    ];

    for (final (host, path, checkParam, addParam) in rules) {
      if (lower.contains(host) && lower.contains(path)) {
        if (!lower.contains(checkParam)) {
          final sep = urlString.contains('?') ? '&' : '?';
          return '$urlString$sep$addParam';
        }
        return null; // już ma SafeSearch, nic nie rób
      }
    }

    return null; // nie rozpoznana wyszukiwarka
  }

  bool verifyPassword(String entered) {
    return entered == savedPassword;
  }

  Future<void> savePassword(String newPassword) async {
    final prefs = await _getPrefs;
    await prefs.setString('user_password', newPassword);
    savedPassword = newPassword;
    notifyListeners();
  }

  List<ContentBlocker> getContentBlockers() {
    if (!adBlockEnabled) return [];

    // ── Domeny reklamowe (EasyList top domains) ──
    const adDomains = [
      // Google Ads
      "doubleclick.net", "googleadservices.com", "googlesyndication.com",
      "adservice.google.com",
      "adservice.google.pl",
      "pagead2.googlesyndication.com",
      "tpc.googlesyndication.com",
      // AppNexus / Xandr
      "adnxs.com", "adnxs-simple.com",
      // Amazon Ads
      "amazon-adsystem.com", "aax.amazon-adsystem.com",
      // Facebook Ads
      "an.facebook.com", "connect.facebook.net",
      // Criteo
      "criteo.com", "criteo.net", "storefront.criteo.com",
      // Taboola
      "taboola.com", "trc.taboola.com", "cdn.taboola.com",
      // Outbrain
      "outbrain.com", "outbrainimg.com",
      // Rubicon / Magnite
      "rubiconproject.com", "fastlane.rubiconproject.com",
      // OpenX
      "openx.net", "openx.com",
      // PubMatic
      "pubmatic.com", "ads.pubmatic.com",
      // Index Exchange
      "indexexchange.com", "casalemedia.com",
      // Media.net
      "media.net", "adservetx.media.net",
      // Sovrn
      "sovrn.com", "lijit.com",
      // Smart AdServer
      "smartadserver.com", "equativ.com",
      // The Trade Desk
      "adsrvr.org",
      // TripleLift
      "3lift.com", "tlx.3lift.com",
      // Sharethrough
      "sharethrough.com",
      // Moat
      "moatads.com", "moat.com",
      // Sizmek
      "sizmek.com", "serving-sys.com",
      // Conversant
      "conversantmedia.com", "dotomi.com",
      // Oath/Verizon
      "advertising.com", "adtech.de",
      // Yieldmo
      "yieldmo.com",
      // Undertone
      "undertone.com",
      // Adroll
      "adroll.com", "d.adroll.com",
      // Teads
      "teads.tv", "teads.com",
      // Dianomi
      "dianomi.com",
      // Bidswitch
      "bidswitch.net",
      // Spotxchange
      "spotxchange.com", "spotx.tv",
      // Yandex Ads
      "an.yandex.ru", "yandex-adv.ru",
    ];

    // ── Domeny trackerów (EasyPrivacy top domains) ──
    const trackingDomains = [
      // Google Analytics / Tag Manager
      "google-analytics.com", "googletagmanager.com", "googletagservices.com",
      "analytics.google.com", "ssl.google-analytics.com",
      // Facebook Pixel
      "facebook.com/tr", "fbcdn.net",
      // Hotjar
      "hotjar.com", "static.hotjar.com", "script.hotjar.com",
      // Mixpanel
      "mixpanel.com", "api.mixpanel.com",
      // Segment
      "segment.com", "segment.io", "api.segment.io",
      // Amplitude
      "amplitude.com", "api.amplitude.com",
      // Heap
      "heapanalytics.com", "heap.io",
      // FullStory
      "fullstory.com", "rs.fullstory.com",
      // Mouseflow
      "mouseflow.com",
      // Lucky Orange
      "luckyorange.com", "luckyorange.net",
      // Clarity (Microsoft)
      "clarity.ms", "c.clarity.ms",
      // New Relic
      "newrelic.com", "nr-data.net",
      // Datadog
      "datadoghq.com", "browser-intake-datadoghq.com",
      // Sentry
      "sentry.io", "browser.sentry-cdn.com",
      // Scorecard Research
      "scorecardresearch.com", "scdn.co",
      // Nielsen
      "nielsen.com", "imrworldwide.com",
      // Comscore
      "comscore.com", "comscore.net",
      // Quantcast
      "quantserve.com", "quantcast.com",
      // Chartbeat
      "chartbeat.com", "chartbeat.net",
      // Pingdom
      "pingdom.net",
      // Intercom
      "intercom.io", "intercomcdn.com",
      // Optimizely
      "optimizely.com",
      // VWO
      "vwo.com", "wingify.com",
      // Crazy Egg
      "crazyegg.com",
      // Yandex Metrika
      "mc.yandex.ru", "metrika.yandex.ru",
    ];

    final List<ContentBlocker> blockers = [];

    // Blokuj domeny reklamowe
    for (final domain in adDomains) {
      blockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: RegExp.escape(domain),
            resourceType: [
              ContentBlockerTriggerResourceType.SCRIPT,
              ContentBlockerTriggerResourceType.IMAGE,
              ContentBlockerTriggerResourceType.STYLE_SHEET,
            ],
          ),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }

    // Blokuj trackery
    for (final domain in trackingDomains) {
      blockers.add(
        ContentBlocker(
          trigger: ContentBlockerTrigger(
            urlFilter: RegExp.escape(domain),
            resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
          ),
          action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
        ),
      );
    }

    // Ukryj elementy reklamowe przez CSS
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(urlFilter: ".*"),
        action: ContentBlockerAction(
          type: ContentBlockerActionType.CSS_DISPLAY_NONE,
          selector:
              ".ad, .ads, .ad-unit, .ad-container, .ad-wrapper, "
              ".advertisement, .adsbygoogle, .banner-ad, .display-ad, "
              "#ad, #ads, #advertisement, #google_ads_iframe, "
              "[id^='google_ads'], [class^='GoogleAd'], "
              ".sponsored, .promoted, #carbonads, "
              ".advert, #adverts, .widget-ad, "
              "[data-ad], [data-ads], [data-advertisement], "
              ".ad-slot, .ad-placeholder, .ad-banner, "
              "ins.adsbygoogle",
        ),
      ),
    );

    // Zastąp obecne trackingDomains bardziej szczegółowymi regułami:

    // Google Analytics

    // Hotjar
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: r".*(hotjar\.com|hjid|hjsv).*",
          resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );

    // Yandex Metrica
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter:
              r".*(mc\.yandex\.|metrika\.yandex\.|yandex\.ru\/metrika|ym\.js).*",
          resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );

    // Sentry
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: r".*(sentry\.io|sentry-cdn\.com|browser\.sentry).*",
          resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );

    // Bugsnag
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter: r".*(bugsnag\.com|bugsnag\.js).*",
          resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );

    // Flash banners / GIF / Static image ads
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter:
              r".*(banner|flash|leaderboard|skyscraper|rectangle|interstitial|preroll).*\.(gif|jpg|png|swf|jpeg).*",
          resourceType: [ContentBlockerTriggerResourceType.IMAGE],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );

    // Tracking pixels (1x1 GIF)
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter:
              r".*[/_-](tracking-pixel|pixel\.gif|beacon\.gif|telemetry|ping\.gif)[/_?].*",
          resourceType: [ContentBlockerTriggerResourceType.IMAGE],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );
    return blockers;
  }

  // ── Filtr treści dla dorosłych ───────────────
  Future<void> setAdultFilter(bool value) async {
    final prefs = await _getPrefs;
    await prefs.setBool('adult_filter_enabled', value);
    adultFilterEnabled = value;
    notifyListeners();
  }

  // ── Karty ────────────────────────────────────
  void addNewTab() {
    tabs.add(TabModel(url: homePageUrl, loaded: true));
    currentTabIndex = tabs.length - 1;
    saveTabs();
    notifyListeners();
  }

  void addTabWithUrl(String url) {
    tabs.add(TabModel(url: url, loaded: true));
    currentTabIndex = tabs.length - 1;
    saveTabs();
    notifyListeners();
  }

  void closeTab(int index) {
    if (tabs.length <= 1) return;
    tabs.removeAt(index);
    if (currentTabIndex >= tabs.length) currentTabIndex = tabs.length - 1;
    saveTabs();
    notifyListeners();
  }

  void closeAllTabs() {
    tabs = [TabModel(url: homePageUrl, loaded: true)];
    currentTabIndex = 0;
    saveTabs();
    notifyListeners();
  }

  void switchTab(int index) {
    currentTabIndex = index;
    tabs[index].loaded = true; // ← dopiero teraz ta karta się załaduje
    saveTabs();
    notifyListeners();
  }

  void _applyTabMetadata(int index, {String? url, String? title}) {
    var changed = false;
    if (url != null &&
        url.isNotEmpty &&
        !url.startsWith('about:') &&
        tabs[index].url != url) {
      tabs[index].url = url;
      changed = true;
    }
    final cleanTitle = title?.trim();
    if (_isUsableTabTitle(cleanTitle) && cleanTitle != tabs[index].title) {
      tabs[index].title = cleanTitle!;
      changed = true;
    } else if (!_isUsableTabTitle(tabs[index].title)) {
      final fallbackTitle = _titleFromUrl(tabs[index].url);
      if (fallbackTitle != tabs[index].title) {
        tabs[index].title = fallbackTitle;
        changed = true;
      }
    }
    if (changed) {
      saveTabs();
      notifyListeners();
    }
  }

  // Aktualizuj metadane przez referencję do obiektu TabModel (nie przez kontroler)
  void setTabAudio(TabModel tab, bool isPlaying) {
    final index = tabs.indexWhere((t) => t == tab);
    if (index == -1) return;
    if (tabs[index].isPlayingAudio != isPlaying) {
      tabs[index].isPlayingAudio = isPlaying;
      notifyListeners();
    }
  }

  void updateTab(TabModel tab, {String? url, String? title}) {
    final index = tabs.indexWhere((t) => t == tab);
    if (index == -1) return;
    _applyTabMetadata(index, url: url, title: title);
  }

  void updateTabMetadata(
    InAppWebViewController controller, {
    String? url,
    String? title,
  }) {
    final index = tabs.indexWhere((t) => t.controller == controller);
    if (index == -1) {
      // Fallback: szukaj po URL
      if (url != null && url.isNotEmpty) {
        final urlIndex = tabs.indexWhere((t) => t.url == url);
        if (urlIndex != -1) _applyTabMetadata(urlIndex, url: url, title: title);
      }
      return;
    }

    _applyTabMetadata(index, url: url, title: title);
  }

  bool _isUsableTabTitle(String? title) {
    final value = title?.trim();
    if (value == null || value.isEmpty) return false;
    final lower = value.toLowerCase();
    return lower != 'about:blank' &&
        lower != 'about:blank#blocked' &&
        !lower.startsWith('about:');
  }

  String _titleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return 'Nowa karta';
    return uri.host.startsWith('www.') ? uri.host.substring(4) : uri.host;
  }

  Future<void> clearHistoryInRange(
    DateTime fromDate,
    DateTime toDate, {
    TimeOfDay? fromTime,
    TimeOfDay? toTime,
  }) async {
    history.removeWhere((e) {
      final date = DateTime.tryParse(e['date'] ?? '');
      if (date == null) return false;
      if (date.isBefore(fromDate) || date.isAfter(toDate)) return false;

      // Jeśli brak filtra godzinowego — usuń cały zakres dat
      if (fromTime == null || toTime == null) return true;

      final parts = (e['time'] ?? '').split(':');
      if (parts.length < 2) return true;
      final entryMin =
          (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
      final fromMin = fromTime.hour * 60 + fromTime.minute;
      final toMin = toTime.hour * 60 + toTime.minute;
      return entryMin >= fromMin && entryMin <= toMin;
    });

    final prefs = await _getPrefs;
    await prefs.setString('browser_history', json.encode(history));
    notifyListeners();
  }

  Future<void> clearHistoryFromDaysBack(int days) async {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    history.removeWhere((e) {
      final date = DateTime.tryParse(e['date'] ?? '');
      return date != null && date.isAfter(cutoff);
    });
    final prefs = await _getPrefs;
    await prefs.setString('browser_history', json.encode(history));
    notifyListeners();
  }

  DateTime? get oldestHistoryDate {
    if (history.isEmpty) return null;
    DateTime? oldest;
    for (final e in history) {
      final date = DateTime.tryParse(e['date'] ?? '');
      if (date != null && (oldest == null || date.isBefore(oldest))) {
        oldest = date;
      }
    }
    return oldest;
  }

  // ── Historia ─────────────────────────────────
  Future<void> addToHistory(String? title, String url) async {
    if (url.isEmpty ||
        url.contains("about:blank") ||
        url.contains("safe=active") ||
        url == "https://www.google.com/" ||
        url.startsWith("https://www.google.com/#") ||
        incognitoMode) {
      return;
    }

    String displayTitle = title ?? url;

    // Próba wyciągnięcia frazy z URL
    final uri = Uri.tryParse(url);
    if (uri != null &&
        uri.host.contains("google.") &&
        uri.queryParameters.containsKey("q")) {
      displayTitle = "🔍 ${uri.queryParameters['q']}";
    }
    // Próba wyciągnięcia frazy z tytułu strony (np. "fraza - Google Search")
    else if (title != null &&
        (title.contains(" - Google Search") ||
            title.contains(" - Szukaj w Google") ||
            title.contains(" - Google"))) {
      final phrase = title
          .replaceAll(" - Google Search", "")
          .replaceAll(" - Szukaj w Google", "")
          .replaceAll(" - Google", "")
          .trim();
      if (phrase.isNotEmpty) displayTitle = "🔍 $phrase";
    }

    // Jeśli ostatni wpis ma ten sam tytuł — nie dodawaj duplikatu
    if (history.isNotEmpty && history.first['title'] == displayTitle) return;

    history.insert(0, {
      'title': displayTitle,
      'url': url,
      'time': DateTime.now().toString().substring(11, 16),
      'date': DateTime.now().toString().substring(0, 10),
    });
    if (history.length > 100) history.removeLast();
    notifyListeners();

    final prefs = await _getPrefs;
    await prefs.setString('browser_history', json.encode(history));
  }

  Future<void> saveTabs() async {
    final prefs = await _getPrefs;
    // Używaj tab.url który jest na bieżąco aktualizowany przez updateTabMetadata
    // Nie odpytuj kontrolera asynchronicznie — może zwrócić stary URL
    final tabsData = tabs.map((t) {
      final url = t.url.isNotEmpty && !t.url.startsWith('about:') ? t.url : '';
      final title = _isUsableTabTitle(t.title) ? t.title : _titleFromUrl(url);
      return {'url': url, 'title': title};
    }).toList();
    final encoded = json.encode(tabsData);
    await prefs.setString('saved_tabs', encoded);
    await prefs.setInt('saved_tab_index', currentTabIndex);
    debugPrint('💾 saveTabs: $encoded');
  }

  Future<void> loadTabs() async {
    final prefs = await _getPrefs;
    final tabsData = prefs.getString('saved_tabs');
    debugPrint('📂 loadTabs raw: $tabsData');
    final savedIndex = prefs.getInt('saved_tab_index') ?? 0;
    if (tabsData != null) {
      final decoded = json.decode(tabsData) as List<dynamic>;
      if (decoded.isNotEmpty) {
        tabs = decoded
            .map(
              (e) => TabModel(
                url: e['url'] as String,
                title: _isUsableTabTitle(e['title'] as String?)
                    ? e['title'] as String
                    : _titleFromUrl(e['url'] as String),
                loaded: false,
              ),
            )
            .toList();
        currentTabIndex = savedIndex.clamp(0, tabs.length - 1);
        tabs[currentTabIndex].loaded = true;
        debugPrint(
          '📂 loadTabs: ${tabs.length} kart, aktywna $currentTabIndex',
        );
        for (final t in tabs) debugPrint('  tab.url=${t.url}');
        notifyListeners();
      }
    }
  }

  bool downloadEnabled = false;
  List<String> blockedExtensions = [
    "apk",
    "exe",
    "bat",
    "cmd",
    "sh",
    "msi",
    "dmg",
  ];

  Future<void> setDownloadEnabled(bool value) async {
    //tylko do debugu
    final prefs = await _getPrefs;
    await prefs.setBool('download_enabled', value);
    downloadEnabled = value;
    notifyListeners();
  }

  Future<void> saveWordInputLanguages() async {
    final prefs = await _getPrefs;
    await prefs.setStringList('word_input_languages', wordInputLanguages);
    notifyListeners();
  }

  void addWordInputLanguage(String langCode) {
    if (!wordInputLanguages.contains(langCode)) {
      wordInputLanguages.add(langCode);
      saveWordInputLanguages();
    }
  }

  void removeWordInputLanguage(String langCode) {
    if (wordInputLanguages.length <= 1) return;
    wordInputLanguages.remove(langCode);
    saveWordInputLanguages();
  }

  Future<void> saveBlockedExtensions() async {
    final prefs = await _getPrefs;
    await prefs.setStringList('blocked_extensions', blockedExtensions);
  }

  void addBlockedExtension(String ext) {
    final clean = ext.toLowerCase().trim().replaceAll('.', '');
    if (clean.isNotEmpty && !blockedExtensions.contains(clean)) {
      blockedExtensions.add(clean);
      saveBlockedExtensions();
      notifyListeners();
    }
  }

  void removeBlockedExtension(int index) {
    blockedExtensions.removeAt(index);
    saveBlockedExtensions();
    notifyListeners();
  }

  bool isExtensionBlocked(String url) {
    final ext = url.split('.').last.split('?').first.toLowerCase();
    return blockedExtensions.contains(ext);
  }

  // ── Budowanie URL z paska adresu ─────────────
  WebUri buildTargetUrl(String input) {
    final trimmed = input.trim();
    // Jeśli użytkownik wpisuje ścieżkę lokalną lub protokół file://
    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      return WebUri(
        trimmed.startsWith('file://') ? trimmed : 'file://$trimmed',
      );
    }
    final isDomain =
        (trimmed.contains('.') && !trimmed.contains(' ')) ||
        trimmed.startsWith('http');

    if (isDomain) {
      final formatted = trimmed.startsWith('http')
          ? trimmed
          : 'https://$trimmed';
      return WebUri(formatted);
    } else {
      return WebUri(_buildSearchUrl(trimmed));
    }
  }

  /// Buduje URL wyszukiwania dla aktualnie wybranej wyszukiwarki
  String _buildSearchUrl(String query) {
    final safe = adultFilterEnabled;
    final encoded = Uri.encodeComponent(query);
    final engine = searchEngineUrl.isNotEmpty
        ? searchEngineUrl.toLowerCase()
        : 'https://www.google.com';

    // Sprawdź czy to własna wyszukiwarka użytkownika
    final custom = customSearchEngines.firstWhere(
      (e) => (e['url'] ?? '').toLowerCase() == engine,
      orElse: () => {},
    );
    if (custom.isNotEmpty && custom['searchUrl'] != null) {
      final customSafe = safe || custom['safesearch'] == 'true';
      var url = custom['searchUrl']!.replaceAll('%s', encoded);
      if (customSafe && !url.contains('safe=')) {
        final sep = url.contains('?') ? '&' : '?';
        url = '${url}${sep}safe=active';
      }
      return url;
    }

    if (engine.contains('duckduckgo.com')) {
      return 'https://www.duckduckgo.com/?q=$encoded${safe ? "&kp=1" : ""}';
    } else if (engine.contains('bing.com')) {
      return 'https://www.bing.com/search?q=$encoded${safe ? "&adlt=strict" : ""}';
    } else if (engine.contains('search.brave.com')) {
      return 'https://search.brave.com/search?q=$encoded${safe ? "&safesearch=strict" : ""}';
    } else if (engine.contains('startpage.com')) {
      return 'https://www.startpage.com/search?q=$encoded${safe ? "&safe=1" : ""}';
    } else if (engine.contains('ecosia.org')) {
      return 'https://www.ecosia.org/search?q=$encoded${safe ? "&safesearch=strict" : ""}';
    } else if (engine.contains('yahoo.com')) {
      return 'https://search.yahoo.com/search?p=$encoded${safe ? "&vm=r" : ""}';
    } else {
      return 'https://www.google.com/search?q=$encoded${safe ? "&safe=active" : "&safe=off"}';
    }
  }
}
