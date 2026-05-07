import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'browser_service.dart';
import 'pdf_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewTab extends StatefulWidget {
  final TabModel tab;
  final BrowserService svc;
  final TextEditingController urlController;
  final void Function(
    BrowserService,
    WebUri,
    InAppWebViewController?, {
    BlockReason reason,
    String? matchedWord,
  })
  onPasswordRequired;

  const WebViewTab({
    required Key key,
    required this.tab,
    required this.svc,
    required this.urlController,
    required this.onPasswordRequired,
  }) : super(key: key);

  @override
  State<WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<WebViewTab>
    with AutomaticKeepAliveClientMixin {
  static const MethodChannel _customSchemeChannel = MethodChannel(
    'app/custom_scheme',
  );

  @override
  bool get wantKeepAlive => true;

  double _progress = 0;
  int _webViewKey = 0;
  int _lastAdBlockVersion = 0;

  void _onSvcChanged() {
    final svc = widget.svc;
    if (svc.adBlockVersion != _lastAdBlockVersion) {
      _lastAdBlockVersion = svc.adBlockVersion;
      if (mounted) setState(() => _webViewKey++);
    }
  }

  Future<bool> _openExternalUrl(String urlString) async {
    try {
      if (Platform.isAndroid) {
        final opened = await _customSchemeChannel.invokeMethod<bool>(
          'openExternalUrl',
          urlString,
        );
        if (opened == true) return true;
      }
    } catch (e) {
      debugPrint('Native openExternalUrl error: $e');
    }

    try {
      return await launchUrl(
        Uri.parse(urlString),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('launchUrl error: $e');
      return false;
    }
  }

  Future<bool> _openUrlInPackage(String urlString, String packageName) async {
    try {
      if (!Platform.isAndroid) return false;
      final opened = await _customSchemeChannel.invokeMethod<bool>(
        'openUrlInPackage',
        {'url': urlString, 'package': packageName},
      );
      return opened == true;
    } catch (e) {
      debugPrint('Native openUrlInPackage error: $e');
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _lastAdBlockVersion = widget.svc.adBlockVersion;
    widget.svc.addListener(_onSvcChanged);
  }

  @override
  void dispose() {
    widget.svc.removeListener(_onSvcChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final tab = widget.tab;
    final svc = widget.svc;

    if (!tab.loaded) {
      return Container(
        color: svc.incognitoMode
            ? const Color.fromARGB(255, 50, 15, 70)
            : Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.grey),
        ),
      );
    }

    return Stack(
      children: [
        InAppWebView(
          key: ValueKey(_webViewKey),
          initialUrlRequest: URLRequest(url: WebUri("about:blank")),
          initialSettings: InAppWebViewSettings(
            contentBlockers: svc.isAdBlockWhitelisted(tab.url)
                ? []
                : svc.getContentBlockers(),
            domStorageEnabled: true,
            databaseEnabled: true,
            thirdPartyCookiesEnabled: true,
            incognito: false,
            allowsInlineMediaPlayback: true,
            sharedCookiesEnabled: true,
            javaScriptEnabled: true,
            supportMultipleWindows: true,
            javaScriptCanOpenWindowsAutomatically: true,
            userAgent: svc.userAgent,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            useOnDownloadStart: true,
            hardwareAcceleration: true,
            useHybridComposition: false,
          ),
          onProgressChanged: (controller, progress) {
            if (mounted) setState(() => _progress = progress / 100);
            // Aktualizuj URL i metadane podczas ładowania (łapie redirecty)
            if (progress > 20) {
              controller.getUrl().then((u) {
                if (u == null) return;
                final urlString = u.toString();
                if (!urlString.startsWith('about:') &&
                    urlString != 'about:blank') {
                  svc.updateTab(tab, url: urlString);
                }
              });
            }
          },
          onTitleChanged: (controller, title) {
            svc.updateTab(tab, title: title);
          },
          onWebViewCreated: (c) {
            tab.controller = c;

            // Handler dla wykrywania odtwarzania audio
            c.addJavaScriptHandler(
              handlerName: 'onAudioState',
              callback: (args) {
                if (args.isEmpty) return;
                final isPlaying = args[0] == true;
                svc.setTabAudio(tab, isPlaying);
              },
            );

            // Handler dla aktualizacji tytułu z JS (SPA, YouTube itp.)
            c.addJavaScriptHandler(
              handlerName: 'onTitleUpdate',
              callback: (args) {
                if (args.isEmpty) return;
                final newTitle = args[0]?.toString();
                if (newTitle != null && newTitle.isNotEmpty) {
                  svc.updateTab(tab, title: newTitle);
                }
              },
            );

            // Handler dla custom scheme redirectów z JavaScript (np. OAuth)
            c.addJavaScriptHandler(
              handlerName: 'customScheme',
              callback: (args) async {
                if (args.isEmpty) return;
                final url = args[0] as String;
                debugPrint('🔗 JS customScheme: $url');
                await _openExternalUrl(url);
              },
            );

            // Nasłuchuj na custom scheme z natywnego WebViewClient
            _customSchemeChannel.setMethodCallHandler((call) async {
              if (call.method == 'onCustomScheme') {
                final url = call.arguments as String;
                debugPrint('🔗 Native custom scheme: $url');
                await _openExternalUrl(url);
              }
            });
            Future.microtask(() {
              String urlToLoad = tab.url;
              if (svc.pendingShortcutUrl != null &&
                  svc.tabs.indexOf(tab) == svc.currentTabIndex) {
                urlToLoad = svc.pendingShortcutUrl!;
                svc.pendingShortcutUrl = null;
              }

              final blocked = svc.handleNavigation(
                urlToLoad,
                c,
                (url, ctrl, reason, matchedWord) => widget.onPasswordRequired(
                  svc,
                  url,
                  ctrl,
                  reason: reason,
                  matchedWord: matchedWord,
                ),
                (message) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(message),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                },
              );

              if (!blocked) {
                c.loadUrl(urlRequest: URLRequest(url: WebUri(urlToLoad)));
              }
            });
          },
          onLoadStart: (c, url) async {
            debugPrint('onLoadStart: ${url?.toString()}');
            if (url == null) return;
            final urlString = url.toString();

            if (urlString.startsWith('http://') ||
                urlString.startsWith('https://')) {
              // Aktualizuj URL natychmiast gdy strona zaczyna się ładować
              svc.updateTab(tab, url: urlString);
            } else if (!urlString.startsWith('about:') &&
                !urlString.startsWith('file:') &&
                !urlString.startsWith('data:')) {
              debugPrint('🔗 onLoadStart custom schemat: $urlString');
              await _openExternalUrl(urlString);
              c.stopLoading();
            }
          },
          onLoadResourceWithCustomScheme: (c, request) async {
            final urlString = request.url.toString();
            debugPrint('🔗 onLoadResourceWithCustomScheme: $urlString');
            await _openExternalUrl(urlString);
            return CustomSchemeResponse(
              data: Uint8List(0),
              contentType: 'text/plain',
            );
          },
          onReceivedError: (controller, request, error) async {
            final urlString = request.url.toString();
            debugPrint('❌ onReceivedError: $urlString — ${error.description}');
            // Gdy WebView nie może obsłużyć custom schematu (np. github://)
            // po OAuth redirect — otwieramy bezpośrednio przez system
            if (!urlString.startsWith('http://') &&
                !urlString.startsWith('https://')) {
              debugPrint('🔗 Custom schemat w onReceivedError: $urlString');
              await _openExternalUrl(urlString);
            }
          },
          onLoadStop: (c, u) async {
            if (u == null) return;
            final urlString = u.toString();

            // Wstrzyknij agresywny interceptor JS dla custom scheme redirectów (np. OAuth)
            await c.evaluateJavascript(
              source: '''
              (function() {
                if (window.__customSchemeInjected) return;
                window.__customSchemeInjected = true;

                function isCustom(url) {
                  if (!url || typeof url !== "string") return false;
                  return !url.startsWith("http://") &&
                         !url.startsWith("https://") &&
                         !url.startsWith("about:") &&
                         !url.startsWith("javascript:") &&
                         !url.startsWith("/") &&
                         !url.startsWith("?") &&
                         !url.startsWith("#") &&
                         url.indexOf("://") > 0;
                }

                function sendCustom(url) {
                  try { window.flutter_inappwebview.callHandler("customScheme", url); } catch(e) {}
                }

                // Interceptory location
                var origAssign = window.location.assign.bind(window.location);
                var origReplace = window.location.replace.bind(window.location);
                try {
                  Object.defineProperty(window.location, "href", {
                    set: function(url) { isCustom(url) ? sendCustom(url) : origAssign(url); }
                  });
                } catch(e) {}
                window.location.assign = function(url) { isCustom(url) ? sendCustom(url) : origAssign(url); };
                window.location.replace = function(url) { isCustom(url) ? sendCustom(url) : origReplace(url); };

                // Interceptor fetch — GitHub może używać fetch do zainicjowania redirect
                if (window.fetch) {
                  var origFetch = window.fetch.bind(window);
                  window.fetch = function(input, init) {
                    var url = typeof input === "string" ? input : (input && input.url);
                    if (isCustom(url)) { sendCustom(url); return Promise.resolve(new Response("", {status: 200})); }
                    return origFetch(input, init);
                  };
                }

                // Interceptor XMLHttpRequest
                var origXHROpen = XMLHttpRequest.prototype.open;
                XMLHttpRequest.prototype.open = function(method, url) {
                  if (isCustom(url)) { sendCustom(url); return; }
                  return origXHROpen.apply(this, arguments);
                };

                // Polling — sprawdzaj location.href co 150ms przez 30s po załadowaniu
                var _lastHref = location.href;
                var _pollCount = 0;
                var _pollTimer = setInterval(function() {
                  _pollCount++;
                  if (_pollCount > 200) { clearInterval(_pollTimer); return; }
                  try {
                    var h = location.href;
                    if (h !== _lastHref) {
                      _lastHref = h;
                      if (isCustom(h)) { sendCustom(h); clearInterval(_pollTimer); }
                    }
                  } catch(e) {
                    // SecurityError przy cross-origin — ignoruj
                  }
                }, 150);

                // MutationObserver na meta refresh i iframes
                var obs = new MutationObserver(function(muts) {
                  muts.forEach(function(m) {
                    m.addedNodes.forEach(function(n) {
                      if (n.tagName === "META" && n.httpEquiv && n.httpEquiv.toLowerCase() === "refresh") {
                        var content = n.content || "";
                        var match = content.match(/url=(.+)/i);
                        if (match && isCustom(match[1].trim())) sendCustom(match[1].trim());
                      }
                      if (n.tagName === "A" && isCustom(n.href)) {
                        n.addEventListener("click", function(e) { e.preventDefault(); sendCustom(n.href); });
                      }
                    });
                  });
                });
                obs.observe(document.documentElement, { childList: true, subtree: true });

              })();
            ''',
            );

            if (urlString.isNotEmpty &&
                !urlString.startsWith("about:") &&
                urlString != "about:blank") {
              // Natychmiastowa aktualizacja
              final title = await c.getTitle();
              svc.updateTab(tab, url: urlString, title: title);
              // urlController jest aktualizowany przez _syncUrlBar w BrowserScreen

              // Wykrywanie odtwarzania audio
              await c.evaluateJavascript(
                source: """
                (function() {
                  if (window.__audioWatcherInjected) return;
                  window.__audioWatcherInjected = true;
                  function checkAudio() {
                    var playing = Array.from(document.querySelectorAll(\'audio,video\'))
                      .some(function(m) { return !m.paused && !m.ended && m.readyState > 2; });
                    try { window.flutter_inappwebview.callHandler(\'onAudioState\', playing); } catch(e) {}
                  }
                  setInterval(checkAudio, 1500);
                })();
              """,
              );

              // Obserwator zmian document.title przez JS (SPA, YouTube itp.)
              await c.evaluateJavascript(
                source: """
                (function() {
                  if (window.__titleObserverInjected) return;
                  window.__titleObserverInjected = true;
                  var lastTitle = document.title;
                  var obs = new MutationObserver(function() {
                    if (document.title !== lastTitle) {
                      lastTitle = document.title;
                      try { window.flutter_inappwebview.callHandler("onTitleUpdate", document.title); } catch(e) {}
                    }
                  });
                  var titleEl = document.querySelector("title");
                  if (titleEl) obs.observe(titleEl, { childList: true, characterData: true, subtree: true });
                  obs.observe(document.head || document.documentElement, { childList: true, subtree: false });
                })();
              """,
              );

              // Polling tytułu — 3 razy na wypadek gdyby JS jeszcze nie ustawił tytułu
              for (final delay in [800, 1600, 3000]) {
                Future.delayed(Duration(milliseconds: delay), () async {
                  if (!mounted) return;
                  final t = await c.getTitle();
                  if (t != null && t.isNotEmpty) {
                    svc.updateTab(tab, title: t);
                  }
                });
              }
            }
            await svc.addToHistory(await c.getTitle(), urlString);
          },
          onDownloadStartRequest: (controller, downloadRequest) async {
            final urlString = downloadRequest.url.toString();

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Pobieranie dokumentu..."),
                duration: Duration(seconds: 3),
                behavior: SnackBarBehavior.floating,
              ),
            );

            final completer = Completer<Map<String, dynamic>?>();
            controller.addJavaScriptHandler(
              handlerName: 'pdfDownloadResult',
              callback: (args) async {
                controller.removeJavaScriptHandler(
                  handlerName: 'pdfDownloadResult',
                );
                if (args.isEmpty) {
                  completer.complete(null);
                  return;
                }
                try {
                  completer.complete(json.decode(args[0] as String));
                } catch (e) {
                  completer.complete(null);
                }
              },
            );

            await controller.evaluateJavascript(
              source:
                  '''
                (async function() {
                  try {
                    const resp = await fetch(${json.encode(urlString)}, {
                      credentials: "include",
                      headers: { "Accept": "application/pdf,*/*" }
                    });
                    if (!resp.ok) {
                      window.flutter_inappwebview.callHandler("pdfDownloadResult", JSON.stringify({error: resp.status}));
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
                    const ct = resp.headers.get("content-type") || "";
                    window.flutter_inappwebview.callHandler("pdfDownloadResult", JSON.stringify({base64: b64, cd: cd, ct: ct}));
                  } catch(e) {
                    window.flutter_inappwebview.callHandler("pdfDownloadResult", JSON.stringify({error: e.toString()}));
                  }
                })();
              ''',
            );

            final result = await completer.future.timeout(
              const Duration(seconds: 45),
              onTimeout: () => null,
            );

            if (result != null && result.containsKey('base64')) {
              final bytes = base64Decode(result['base64']);
              final String cd = (result['cd'] as String? ?? '');
              final String ct = (result['ct'] as String? ?? '').toLowerCase();
              final String urlString = downloadRequest.url
                  .toString()
                  .toLowerCase();

              String fileName = "";

              // 1. Sprawdzenie sygnatury pliku (Magic Number) - NAJPEWNIEJSZE
              // Sprawdzamy czy pierwsze 4 bajty to %PDF (ASCII: 37, 80, 68, 70)
              bool isActuallyPdf = false;
              if (bytes.length > 4) {
                if (bytes[0] == 0x25 &&
                    bytes[1] == 0x50 &&
                    bytes[2] == 0x44 &&
                    bytes[3] == 0x46) {
                  isActuallyPdf = true;
                }
              }

              // 2. Próba wyciągnięcia nazwy z nagłówka
              if (cd.isNotEmpty) {
                final regExp = RegExp(
                  r'''filename[^;=\n]*=((['"]).*?\2|[^;\n]*)''',
                );
                final match = regExp.firstMatch(cd);
                if (match != null) {
                  fileName = match
                      .group(1)!
                      .replaceAll('"', '')
                      .replaceAll("'", '')
                      .trim();
                }
              }

              // 3. Logika ustalania rozszerzenia
              if (isActuallyPdf) {
                // Jeśli to PDF, upewnij się, że ma rozszerzenie .pdf
                if (fileName.isEmpty) {
                  // Jeśli brak nazwy, spróbuj wyciągnąć coś sensownego z adresu URL
                  final Uri uri = Uri.parse(urlString);
                  String lastSegment = uri.pathSegments.isNotEmpty
                      ? uri.pathSegments.last
                      : "";
                  if (lastSegment.isEmpty || lastSegment.contains('.')) {
                    fileName =
                        "dokument_${DateTime.now().millisecondsSinceEpoch}.pdf";
                  } else {
                    fileName = "$lastSegment.pdf";
                  }
                } else if (!fileName.toLowerCase().endsWith(".pdf")) {
                  // Zamień błędne rozszerzenie (np. .bin lub .do) na .pdf
                  fileName = fileName.contains('.')
                      ? "${fileName.substring(0, fileName.lastIndexOf('.'))}.pdf"
                      : "$fileName.pdf";
                }
              } else if (fileName.isEmpty) {
                // Jeśli to nie PDF i brak nazwy, użyj Content-Type lub fallbacku
                String ext = ".bin";
                if (ct.contains("image/jpeg"))
                  ext = ".jpg";
                else if (ct.contains("image/png"))
                  ext = ".png";
                else if (ct.contains("word"))
                  ext = ".doc";

                fileName = "file_${DateTime.now().millisecondsSinceEpoch}$ext";
              }

              final dir = await getTemporaryDirectory();
              final file = File('${dir.path}/$fileName');
              await file.writeAsBytes(bytes);

              if (mounted) {
                if (fileName.toLowerCase().endsWith('.pdf')) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PdfScreen(path: file.path, title: fileName),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Pobrano plik: $fileName")),
                  );
                }
              }
            }
          },
          onCreateWindow: (controller, createWindowAction) async {
            // Pobierz URL z żądania
            final url = createWindowAction.request.url;
            // Jeśli URL jest pusty lub jest to about:blank, użyj strony głównej lub
            // pozwól serwisowi obsłużyć pustą kartę
            final urlString =
                (url != null &&
                    url.toString().isNotEmpty &&
                    url.toString() != "about:blank")
                ? url.toString()
                : svc.homePageUrl;

            debugPrint('🪟 onCreateWindow: $urlString');

            // Dodanie karty do serwisu
            svc.addTabWithUrl(urlString);

            // Ręczne wywołanie powiadomienia, aby UI na pewno przeskoczyło do nowej karty
            svc.notifyUI();

            return true; // Informujemy WebView, że obsłużyliśmy otwarcie okna
          },
          shouldOverrideUrlLoading: (c, act) async {
            final url = act.request.url;
            if (url == null) return NavigationActionPolicy.ALLOW;
            final urlString = url.toString();

            // 1. Schematy wewnętrzne — przepuść bez sprawdzania
            if (urlString.startsWith('about:') ||
                urlString.startsWith('file:') ||
                urlString.startsWith('data:')) {
              return NavigationActionPolicy.ALLOW;
            }

            // 2. Schematy inne niż http/https (np. github://, fb://, intent://)
            bool isWebProtocol =
                urlString.startsWith('http://') ||
                urlString.startsWith('https://');

            if (!isWebProtocol) {
              debugPrint('🔗 Custom schemat: $urlString');
              final messenger = ScaffoldMessenger.of(context);
              final opened = await _openExternalUrl(urlString);
              if (!opened) {
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Nie mozna otworzyc tego linku. Wymagana aplikacja moze nie byc zainstalowana.',
                    ),
                  ),
                );
              }
              return NavigationActionPolicy.CANCEL;
            }

            if (svc.isExtensionBlocked(urlString)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Pobieranie tego typu pliku jest zablokowane."),
                ),
              );
              return NavigationActionPolicy.CANCEL;
            }

            // Obsługa nawigacji (hasła, czarna lista)
            final blocked = svc.handleNavigation(
              urlString,
              c,
              (url, ctrl, reason, matchedWord) => widget.onPasswordRequired(
                svc,
                url,
                ctrl,
                reason: reason,
                matchedWord: matchedWord,
              ),
              (message) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.redAccent,
                ),
              ),
            );

            if (!blocked) {
              // Aktualizuj URL od razu przy nawigacji — nie czekaj na onLoadStop
              svc.updateTab(tab, url: urlString);
            }

            return blocked
                ? NavigationActionPolicy.CANCEL
                : NavigationActionPolicy.ALLOW;
          },
        ),
        if (_progress < 1.0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.transparent,
              color: Colors.blue,
              minHeight: 3,
            ),
          ),
      ],
    );
  }
}
