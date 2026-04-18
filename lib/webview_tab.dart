import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'browser_service.dart';
import 'pdf_screen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

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

  Future<String> _getCookiesForUrl(String urlString) async {
    try {
      final cookies = await CookieManager.instance().getCookies(
        url: WebUri(urlString),
      );
      print("🍪 Cookies count: ${cookies.length}");
      for (final c in cookies) {
        print("🍪 ${c.name}=${c.value}");
      }
      return cookies.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _lastAdBlockVersion = widget.svc.adBlockVersion;
    widget.svc.addListener(_onSvcChanged);
    CookieManager.instance().deleteAllCookies();
  }

  @override
  void dispose() {
    widget.svc.removeListener(_onSvcChanged);
    super.dispose();
  }

  void reloadWithNewSettings() {
    if (mounted) setState(() => _webViewKey++);
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
            clearCache: false,
            allowsInlineMediaPlayback: true,
            sharedCookiesEnabled: true,
            disableDefaultErrorPage: false,
            supportMultipleWindows: true,
            allowFileAccess: true,
            useWideViewPort: true,
            loadsImagesAutomatically: true,
            blockNetworkLoads: false,
            javaScriptEnabled: true,
            allowContentAccess: true,
            javaScriptCanOpenWindowsAutomatically: true,
            userAgent:
                "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            cacheMode: CacheMode.LOAD_DEFAULT,
            useOnDownloadStart: true,
            hardwareAcceleration: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
            useHybridComposition: true,
            transparentBackground: false,
          ),
          onPermissionRequest: (controller, request) async {
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          onCreateWindow: (controller, createWindowAction) async {
            final url = createWindowAction.request.url;
            if (url != null) {
              controller.loadUrl(urlRequest: URLRequest(url: url));
            }
            return true;
          },
          onCloseWindow: (controller) async {
            if (widget.svc.tabs.length > 1) {
              final index = widget.svc.tabs.indexOf(tab);
              widget.svc.closeTab(index);
            }
          },
          onProgressChanged: (controller, progress) {
            if (mounted) setState(() => _progress = progress / 100);
          },
          onWebViewCreated: (c) {
            tab.controller = c;

            // Załaduj URL ręcznie (nie przez initialUrlRequest), żeby
            // handleNavigation zdążyło sprawdzić blokadę przed załadowaniem.
            // shouldOverrideUrlLoading NIE odpala się dla initialUrlRequest.

            Future.microtask(() {
              print("🚀 onWebViewCreated urlToLoad: ${tab.url}"); // ← dodaj
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
              print("🚀 blocked: $blocked"); // ← dodaj

              if (!blocked) {
                c.loadUrl(urlRequest: URLRequest(url: WebUri(urlToLoad)));
              }
            });
          },
          onTitleChanged: (c, t) {
            if (mounted) {
              setState(() => tab.title = t ?? "Nowa karta");
              svc.saveTabs();
            }
          },
          onLoadStop: (c, u) async {
            debugPrint('🔴 onLoadStop fired: ${u?.toString()}');
            if (u == null) return;
            final urlString = u.toString();

            // Aktualizuj URL karty — kluczowe dla persistencji
            if (urlString.isNotEmpty &&
                !urlString.startsWith("about:") &&
                urlString != "about:blank") {
              debugPrint('✅ onLoadStop updating tab.url: $urlString');
              // Aktualizuj przez svc.tabs (bezpieczne po loadTabs które zastępuje listę)
              tab.url = urlString;
              final idx = svc.tabs.indexWhere((t) => t.controller == c);
              if (idx != -1) {
                svc.tabs[idx].url = urlString;
                if (idx == svc.currentTabIndex) {
                  widget.urlController.text = urlString;
                }
              }
              await svc.saveTabs();
              svc.notifyListeners();
            } else {
              debugPrint('⚠️ onLoadStop skipped url: $urlString');
            }

            CookieManager cookieManager = CookieManager.instance();
            await cookieManager.setCookie(
              url: u,
              name: "test",
              value: "value",
              isHttpOnly: false,
            );
            await Future.delayed(const Duration(milliseconds: 500));
            await svc.addToHistory(await c.getTitle(), urlString);
          },
          onLoadStart: (controller, url) async {
            if (url == null) return;
            final urlString = url.toString();

            // Uwaga: blokowanie przez handleNavigation (pornKeywords, blacklist, proxy)
            // jest obsługiwane w shouldOverrideUrlLoading, który odpala się PRZED
            // załadowaniem strony. onLoadStart odpala się już PO wysłaniu requesta,
            // dlatego blokowanie tu jest za późne i zostało przeniesione wyżej.

            if (urlString.startsWith("file://") &&
                urlString.toLowerCase().endsWith(".pdf")) {
              await controller.stopLoading();
              final filePath = url.toFilePath();
              final fileName = url.pathSegments.isNotEmpty
                  ? url.pathSegments.last
                  : "Dokument PDF";

              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PdfScreen(path: filePath, title: fileName),
                  ),
                );
              }
            }
          },
          // Wewnątrz InAppWebView w webview_tab.dart
          // Przykład użycia wewnątrz onDownloadStartRequest:
          onDownloadStartRequest: (controller, downloadRequest) async {
            final urlString = downloadRequest.url.toString();
            print("📥 onDownloadStartRequest URL: $urlString");

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 15),
                    Text("Pobieranie dokumentu PDF..."),
                  ],
                ),
                duration: Duration(seconds: 60),
                behavior: SnackBarBehavior.floating,
              ),
            );

            // Rejestrujemy handler PRZED nawigacją
            final completer = Completer<String?>();
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
                  final Map<String, dynamic> parsed = json.decode(
                    args[0] as String,
                  );
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
                    if (!fileName.toLowerCase().endsWith('.pdf'))
                      fileName += '.pdf';
                    final dir = await getTemporaryDirectory();
                    final file = File('${dir.path}/$fileName');
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

            // Nawiguj do strony serwera (nie PDF) — żeby ustawić właściwy origin
            final pdfUri = Uri.parse(urlString);
            final serverOrigin = '${pdfUri.scheme}://${pdfUri.host}';

            // Ładujemy origin serwera żeby WebView był na właściwej domenie
            await controller.loadUrl(
              urlRequest: URLRequest(url: WebUri(serverOrigin)),
            );

            // Czekamy na załadowanie strony
            await Future.delayed(const Duration(seconds: 3));

            // Teraz fetch wykona się z właściwego originu
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

            final path = await completer.future.timeout(
              const Duration(seconds: 45),
              onTimeout: () {
                controller.removeJavaScriptHandler(
                  handlerName: 'pdfDownloadResult',
                );
                print("❌ timeout");
                return null;
              },
            );

            if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

            if (path != null && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdfScreen(
                    path: path,
                    title:
                        downloadRequest.suggestedFilename ??
                        urlString.split('/').last.split('?').first,
                  ),
                ),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Nie udało się pobrać PDF."),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          shouldOverrideUrlLoading: (c, act) async {
            print("🔀 shouldOverride: ${act.request.url}");
            final url = act.request.url;
            if (url == null) return NavigationActionPolicy.ALLOW;

            final urlString = url.toString();

            // Lokalny PDF
            if (urlString.startsWith('file://') &&
                urlString.toLowerCase().endsWith('.pdf')) {
              final localPath = url.toFilePath();
              if (await File(localPath).exists()) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfScreen(
                      path: localPath,
                      title: localPath.split('/').last,
                    ),
                  ),
                );
                return NavigationActionPolicy.CANCEL;
              }
            }

            // Intent URL
            if (urlString.startsWith('intent://')) {
              if (urlString.contains('play.google.com')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Sklep Play jest niedostępny na tym urządzeniu.",
                    ),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return NavigationActionPolicy.CANCEL;
              }
              try {
                final uri = Uri.parse(urlString);
                final fallbackUrl = uri.queryParameters['browser_fallback_url'];
                if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
                  c.loadUrl(
                    urlRequest: URLRequest(
                      url: WebUri(Uri.decodeFull(fallbackUrl)),
                    ),
                  );
                }
              } catch (e) {
                print("intent:// error: $e");
              }
              return NavigationActionPolicy.CANCEL;
            }

            // Zablokowane rozszerzenia
            if (svc.isExtensionBlocked(urlString)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Pobieranie tego typu pliku jest zablokowane."),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return NavigationActionPolicy.CANCEL;
            }

            // Wykrywanie PDF po URL lub content-type
            bool isPdfUrl =
                urlString.toLowerCase().endsWith('.pdf') ||
                urlString.toLowerCase().contains('.pdf?');

            // Pomiń sondowanie HTTP dla przekierowań auth (CAS, OAuth, SSO)
            // — żądanie HTTP do serwera auth unieważnia token i tworzy pętlę
            final _uri = Uri.tryParse(urlString);
            final _qp = _uri?.queryParameters ?? {};
            final _isAuthRedirect =
                _qp.containsKey('service') ||
                _qp.containsKey('ticket') ||
                _qp.containsKey('callback') ||
                _qp.containsKey('gateway') ||
                _qp.containsKey('code') ||
                _qp.containsKey('state') ||
                urlString.contains('/cas/') ||
                urlString.contains('/oauth') ||
                urlString.contains('/realms/') ||
                urlString.contains('/protocol/') ||
                urlString.contains('logowaniecas') ||
                urlString.contains('SetSID') ||
                urlString.contains('accounts.google.com') ||
                urlString.contains('accounts.youtube.com');

            if (!isPdfUrl && !_isAuthRedirect) {
              final uri = Uri.tryParse(urlString);
              final pathSegment = uri?.pathSegments.lastOrNull ?? '';
              const skipExtensions = {
                '.html',
                '.htm',
                '.aspx',
                '.js',
                '.css',
                '.png',
                '.jpg',
                '.jpeg',
                '.gif',
                '.svg',
                '.ico',
                '.woff',
                '.ttf',
              };
              final ext = pathSegment.contains('.')
                  ? '.${pathSegment.split('.').last.toLowerCase()}'
                  : '';
              final shouldProbe = !skipExtensions.contains(ext);
              if (shouldProbe) {
                try {
                  final cookieStr = await _getCookiesForUrl(urlString);
                  final headHeaders = <String, String>{};
                  if (cookieStr.isNotEmpty) headHeaders['Cookie'] = cookieStr;
                  final headResponse = await http
                      .head(Uri.parse(urlString), headers: headHeaders)
                      .timeout(const Duration(seconds: 5));
                  final ct = headResponse.headers['content-type'] ?? '';

                  if (ct.contains('application/pdf')) {
                    isPdfUrl = true;
                  } else {
                    final getHeaders = <String, String>{'Range': 'bytes=0-3'};
                    if (cookieStr.isNotEmpty) getHeaders['Cookie'] = cookieStr;
                    final getResponse = await http
                        .get(Uri.parse(urlString), headers: getHeaders)
                        .timeout(const Duration(seconds: 8));
                    final body = getResponse.bodyBytes;
                    if (body.length >= 4 &&
                        body[0] == 0x25 &&
                        body[1] == 0x50 &&
                        body[2] == 0x44 &&
                        body[3] == 0x46) {
                      isPdfUrl = true;
                    }
                  }
                } catch (_) {}
              }
            }

            // Otwieranie PDF
            //if (isPdfUrl) {
            //  if (urlString.contains('accounts.google.com')) {
            //    await launchUrl(
            //      Uri.parse(urlString),
            //      customTabsOptions: CustomTabsOptions(
            //        colorSchemes: CustomTabsColorSchemes.defaults(
            //          toolbarColor: const Color(0xFF202124),
            //        ),
            //        showTitle: true,
            //        urlBarHidingEnabled: true,
            //      ),
            //    );
            //    return NavigationActionPolicy.CANCEL;
            //  }
            //
            //  ScaffoldMessenger.of(context).showSnackBar(
            //    const SnackBar(
            //      content: Row(
            //        children: [
            //          SizedBox(
            //            width: 20,
            //            height: 20,
            //            child: CircularProgressIndicator(
            //              strokeWidth: 2,
            //              color: Colors.white,
            //            ),
            //          ),
            //          SizedBox(width: 15),
            //          Text("Pobieranie dokumentu PDF..."),
            //        ],
            //      ),
            //      duration: Duration(seconds: 10),
            //      behavior: SnackBarBehavior.floating,
            //    ),
            //  );
            //
            //  final path = await svc.downloadFileWithFullHeaders(
            //    controller: c,
            //    url: urlString,
            //  );
            //  if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
            //
            //  if (path != null && mounted) {
            //    await Navigator.push(
            //      context,
            //      MaterialPageRoute(
            //        builder: (_) => PdfScreen(
            //          path: path,
            //          title: urlString.split('/').last.split('?').first,
            //        ),
            //      ),
            //    );
            //  } else if (mounted) {
            //    ScaffoldMessenger.of(context).showSnackBar(
            //      const SnackBar(
            //        content: Text("Błąd pobierania pliku PDF."),
            //        backgroundColor: Colors.redAccent,
            //        behavior: SnackBarBehavior.floating,
            //      ),
            //    );
            //  }
            //  return NavigationActionPolicy.CANCEL;
            //}
            if (isPdfUrl) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    "Otwieranie dokumentu — kliknij Download na stronie.",
                  ),
                  duration: Duration(seconds: 4),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return NavigationActionPolicy.ALLOW;
            }
            // Pobieranie wyłączone
            if (!svc.downloadEnabled) {
              final path = Uri.tryParse(urlString)?.path ?? '';
              final hasFileExtension =
                  path.contains('.') &&
                  !path.endsWith('/') &&
                  path.split('.').last.length <= 5;
              if (hasFileExtension) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Pobieranie plików jest wyłączone."),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return NavigationActionPolicy.CANCEL;
              }
            }

            // Obsługa nawigacji (czarna lista, hasło, itp.)
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
                  behavior: SnackBarBehavior.floating,
                ),
              ),
            );
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
