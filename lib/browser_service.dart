import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:path_provider/path_provider.dart';
import 'package:http/io_client.dart';
import 'package:path/path.dart' as pathh;

// ─────────────────────────────────────────────
//  MODEL
// ─────────────────────────────────────────────

class TabModel {
  InAppWebViewController? controller;
  String url;
  String title;
  bool loaded;
  TabModel({required this.url, this.title = "Nowa karta", this.loaded = false});
}

// ─────────────────────────────────────────────
//  SERWIS (cała logika biznesowa / backendowa)
// ─────────────────────────────────────────────
enum BlockReason { none, proxy, content, blacklist }

class BrowserService extends ChangeNotifier {
  String? pendingShortcutUrl;

  // --- Stan ---
  List<TabModel> tabs = [TabModel(url: "https://www.google.com")];
  int currentTabIndex = 0;

  List<String> blackList = [];
  Set<String> remoteBlockedDomains = {};
  Set<String> remoteBlockedProxy = {};
  List<Map<String, String>> history = [];
  String? savedPassword;
  bool isVerifying = false;
  bool adBlockEnabled = true;
  bool adultFilterEnabled = true;

  DateTime? _lastAuthTime;
  String? _lastAuthUrl;

  final List<String> pornKeywords = [
    "porn",
    "xxx",
    "hentai",
    "redtube",
    "pornhub",
    "rule34",
    "xvideos",
    "brazzers",
    "sex-video",
  ];

  // ── Gettery wygodne ──────────────────────────
  TabModel get currentTab => tabs[currentTabIndex];
  void notifyShortcut() {
    notifyListeners();
  }

  // ── Inicjalizacja ────────────────────────────
  Future<void> init() async {
    final t0 = DateTime.now();
    await loadData();
    print("loadData: ${DateTime.now().difference(t0).inMilliseconds}ms");

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

  // W BrowserService
  int adBlockVersion = 0; // ← inkrementuj przy zmianie adblockera

  Future<void> setAdBlock(bool value) async {
    final prefs = await _getPrefs;
    await prefs.setBool('adblock_enabled', value);
    adBlockEnabled = value;
    adBlockVersion++; // ← to sygnalizuje że trzeba przebudować WebView
    notifyListeners();
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
    final prefs = await _getPrefs;
    final data = prefs.getString('shortcuts');
    if (data != null) {
      final decoded = json.decode(data) as List<dynamic>;
      shortcuts = decoded
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
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

  Future<String?> downloadFileFromWebView({
    required InAppWebViewController controller,
    required String url,
  }) async {
    try {
      // Pobieranie w kontekście WebView (z pełną sesją, cookies, auth)
      final result = await controller.callAsyncJavaScript(
        functionBody: '''
    const response = await fetch(url, { credentials: 'include' });
    if (!response.ok) return null;
    const blob = await response.blob();
    return await new Promise((resolve) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result.split(",")[1]);
      reader.readAsDataURL(blob);
    });
  ''',
        arguments: {'url': url},
      );

      print("callAsyncJS value: ${result?.value}");
      print("callAsyncJS error: ${result?.error}");

      if (result == null || result.error != null || result.value == null)
        return null;

      final base64String = result.value.toString();
      if (base64String == 'null') return null;

      final bytes = base64Decode(base64String);
      final dir = await getTemporaryDirectory();
      final fileName = _parseFileName(null, url);
      final filePath = pathh.join(dir.path, fileName);
      await File(filePath).writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      print("Błąd podczas pobierania: $e");
      return null;
    }
  }

  /// Pomocnicza funkcja do wyciągania nazwy pliku
  String _parseFileName(String? contentDisposition, String url) {
    if (contentDisposition != null &&
        contentDisposition.contains('filename=')) {
      // Próba wyciągnięcia: filename="wyciag.pdf"
      final regExp = RegExp(r'filename=["?]?(.*?)["?]?($| )');
      final match = regExp.firstMatch(contentDisposition);
      if (match != null && match.group(1) != null) {
        return match.group(1)!;
      }
    }
    // Jeśli serwer nie podał nazwy, weź końcówkę adresu URL lub nadaj czasową
    String lastSegment = Uri.parse(url).pathSegments.isNotEmpty
        ? Uri.parse(url).pathSegments.last
        : "file_${DateTime.now().millisecondsSinceEpoch}";

    return lastSegment.contains('.') ? lastSegment : "$lastSegment.pdf";
  }

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
    debugPrint(
      "prefs read basic: ${DateTime.now().difference(t1).inMilliseconds}ms",
    );
    downloadEnabled = p.getBool('download_enabled') ?? false;
    blockedExtensions =
        p.getStringList('blocked_extensions') ??
        ["apk", "exe", "bat", "cmd", "sh", "msi", "dmg"];

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
  Future<void> saveBlackList() async {
    final prefs = await _getPrefs;
    await prefs.setStringList('blocked_pages', blackList);
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
    if (remoteBlockedProxy.any((domain) => lowerUrl.contains(domain)))
      return true;

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

  BlockReason getBlockReason(String urlString) {
    final lowerUrl = urlString.toLowerCase();
    final uri = Uri.tryParse(lowerUrl);

    if (_isProxyOrVpnUrl(urlString)) return BlockReason.proxy;

    if (adultFilterEnabled) {
      if (uri != null && remoteBlockedDomains.contains(uri.host))
        return BlockReason.content;
      if (pornKeywords.any((word) => lowerUrl.contains(word)))
        return BlockReason.content;
    }

    if (blackList.any((s) => lowerUrl.contains(s.toLowerCase())))
      return BlockReason.blacklist;

    return BlockReason.none;
  }

  bool handleNavigation(
    String urlString,
    InAppWebViewController controller,
    void Function(WebUri, InAppWebViewController?) onPasswordRequired,
    void Function(String) onBlocked,
  ) {
    print("handleNavigation: $urlString");
    if (adultFilterEnabled &&
        urlString.contains("google.") &&
        urlString.contains("/search") &&
        !urlString.contains("safe=active")) {
      final sep = urlString.contains("?") ? "&" : "?";
      controller.loadUrl(
        urlRequest: URLRequest(url: WebUri("$urlString${sep}safe=active")),
      );
      return true;
    }

    final reason = getBlockReason(urlString);

    if (reason == BlockReason.proxy) {
      onBlocked("Ta strona jest zablokowana — proxy i VPN są niedozwolone.");
      return true;
    }

    if (reason == BlockReason.content || reason == BlockReason.blacklist) {
      if (savedPassword != null) {
        if (canSkipAuth(urlString)) {
          return false; // już autoryzowana, przepuść
        }
        onPasswordRequired(WebUri(urlString), controller);
      } else {
        onBlocked("Ta strona jest zablokowana.");
      }
      return true;
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

  bool verifyPassword(String entered) {
    debugPrint("🔑 Weryfikacja hasła: $savedPassword == $entered");
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
    blockers.add(
      ContentBlocker(
        trigger: ContentBlockerTrigger(
          urlFilter:
              r".*(google-analytics\.com|googletagmanager\.com|googletagservices\.com|gtag\/js|analytics\.js|ga\.js).*",
          resourceType: [ContentBlockerTriggerResourceType.SCRIPT],
        ),
        action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
      ),
    );

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
          urlFilter: r".*(pixel|beacon|track|ping|telemetry|collect).*",
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
    tabs.add(TabModel(url: "https://www.google.com", loaded: true));
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
    tabs = [TabModel(url: "https://www.google.com")];
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
        incognitoMode)
      return;

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
    final tabsData = tabs.map((t) => {'url': t.url, 'title': t.title}).toList();
    await prefs.setString('saved_tabs', json.encode(tabsData));
    await prefs.setInt('saved_tab_index', currentTabIndex);
  }

  Future<void> loadTabs() async {
    final prefs = await _getPrefs;
    final tabsData = prefs.getString('saved_tabs');
    final savedIndex = prefs.getInt('saved_tab_index') ?? 0;
    if (tabsData != null) {
      final decoded = json.decode(tabsData) as List<dynamic>;
      if (decoded.isNotEmpty) {
        tabs = decoded
            .map(
              (e) => TabModel(
                url: e['url'] as String,
                title: e['title'] as String,
                loaded:
                    false, // wszystkie nieaktywne zaczynają jako niezaładowane
              ),
            )
            .toList();
        currentTabIndex = savedIndex.clamp(0, tabs.length - 1);
        tabs[currentTabIndex].loaded = true; // tylko aktywna ładuje się od razu
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
    final prefs = await _getPrefs;
    await prefs.setBool('download_enabled', value);
    downloadEnabled = value;
    notifyListeners();
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
    final isDomain =
        (trimmed.contains('.') && !trimmed.contains(' ')) ||
        trimmed.startsWith('http');

    if (isDomain) {
      final formatted = trimmed.startsWith('http')
          ? trimmed
          : 'https://$trimmed';
      return WebUri(formatted);
    } else {
      final safeParam = adultFilterEnabled ? "&safe=active" : "&safe=off";
      return WebUri("https://www.google.com/search?q=$trimmed$safeParam");
    }
  }
}
