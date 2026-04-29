import 'dart:io';
import 'package:flutter/material.dart';
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
          ),
          onProgressChanged: (controller, progress) {
            if (mounted) setState(() => _progress = progress / 100);
          },
          onWebViewCreated: (c) {
            tab.controller = c;
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
          onReceivedError: (controller, request, error) async {
            final urlString = request.url.toString();
            debugPrint('❌ onReceivedError: $urlString — ${error.description}');
            // Gdy WebView nie może obsłużyć custom schematu (np. github://)
            // po OAuth redirect — otwieramy bezpośrednio przez system
            if (!urlString.startsWith('http://') &&
                !urlString.startsWith('https://')) {
              debugPrint('🔗 Custom schemat w onReceivedError: $urlString');
              try {
                final uri = Uri.parse(urlString);
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {
                debugPrint('❌ Błąd launchUrl w onReceivedError: $e');
              }
            }
          },
          onLoadStop: (c, u) async {
            if (u == null) return;
            final urlString = u.toString();

            if (urlString.isNotEmpty &&
                !urlString.startsWith("about:") &&
                urlString != "about:blank") {
              tab.url = urlString;
              final idx = svc.tabs.indexWhere((t) => t.controller == c);
              if (idx != -1) {
                svc.tabs[idx].url = urlString;
                if (idx == svc.currentTabIndex) {
                  widget.urlController.text = urlString;
                }
              }
              await svc.saveTabs();
              svc.notifyUI();
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
            final url = createWindowAction.request.url;
            final urlString = url?.toString() ?? svc.homePageUrl;
            debugPrint('🪟 onCreateWindow: $urlString');
            svc.addTabWithUrl(urlString);
            return true;
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
              try {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } catch (e) {
                debugPrint('❌ Nie można otworzyć: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Nie można otworzyć tego linku. Wymagana aplikacja może nie być zainstalowana.',
                      ),
                    ),
                  );
                }
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
