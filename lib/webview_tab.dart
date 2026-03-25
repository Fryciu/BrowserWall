import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:http/http.dart' as http;
import 'browser_service.dart';
import 'pdf_screen.dart';

class WebViewTab extends StatefulWidget {
  final TabModel tab;
  final BrowserService svc;
  final TextEditingController urlController;
  final void Function(BrowserService, WebUri, InAppWebViewController?)
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
          initialUrlRequest: URLRequest(url: WebUri(tab.url)),
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
            if (svc.pendingShortcutUrl != null &&
                svc.tabs.indexOf(tab) == svc.currentTabIndex) {
              final url = svc.pendingShortcutUrl!;
              svc.pendingShortcutUrl = null;
              Future.microtask(
                () => c.loadUrl(urlRequest: URLRequest(url: WebUri(url))),
              );
            }
          },
          onTitleChanged: (c, t) {
            if (mounted) {
              setState(() => tab.title = t ?? "Nowa karta");
              svc.saveTabs();
            }
          },
          onLoadStop: (c, u) async {
            await Future.delayed(const Duration(milliseconds: 500));
            if (u != null) {
              await svc.addToHistory(await c.getTitle(), u.toString());
            }
          },
          onLoadStart: (controller, url) async {
            if (url == null) return;
            final urlString = url.toString();

            final blocked = svc.handleNavigation(
              urlString,
              controller,
              (url, ctrl) => widget.onPasswordRequired(svc, url, ctrl),
              (message) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.redAccent,
                ),
              ),
            );
            if (blocked) {
              await controller.stopLoading();
              return;
            }

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
          onDownloadStartRequest: (controller, downloadRequest) async {
            final urlString = downloadRequest.url.toString();

            if (urlString.startsWith("content://") ||
                urlString.toLowerCase().endsWith(".pdf")) {
              String fileName =
                  "dokument_${DateTime.now().millisecondsSinceEpoch}.pdf";
              if (downloadRequest.suggestedFilename != null) {
                fileName = downloadRequest.suggestedFilename!;
              }

              try {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PdfScreen(path: urlString, title: fileName),
                  ),
                );
              } catch (e) {
                print("Błąd PDF: $e");
              }
            }
          },
          shouldOverrideUrlLoading: (c, act) async {
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
            if (!isPdfUrl) {
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
            if (isPdfUrl) {
              if (urlString.contains('accounts.google.com')) {
                await launchUrl(
                  Uri.parse(urlString),
                  customTabsOptions: CustomTabsOptions(
                    colorSchemes: CustomTabsColorSchemes.defaults(
                      toolbarColor: const Color(0xFF202124),
                    ),
                    showTitle: true,
                    urlBarHidingEnabled: true,
                  ),
                );
                return NavigationActionPolicy.CANCEL;
              }

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
                  duration: Duration(seconds: 10),
                  behavior: SnackBarBehavior.floating,
                ),
              );

              final path = await svc.downloadFileFromWebView(
                controller: c,
                url: urlString,
              );
              if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

              if (path != null && mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfScreen(
                      path: path,
                      title: urlString.split('/').last.split('?').first,
                    ),
                  ),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Błąd pobierania pliku PDF."),
                    backgroundColor: Colors.redAccent,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
              return NavigationActionPolicy.CANCEL;
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
              (url, ctrl) => widget.onPasswordRequired(svc, url, ctrl),
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
