import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'browser_service.dart';
import 'pdf_screen.dart';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:media_scanner/media_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class WebViewTab extends StatefulWidget {
  final TabModel tab;
  final BrowserService svc;
  final TextEditingController urlController;
  final void Function(
    BrowserService,
    WebUri,
    InAppWebViewController?, {
    BlockReason reason,
    BlockMatch? match,
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
  bool _timeLimitBlocked = false;

  void _onSvcChanged() {
    final svc = widget.svc;
    if (svc.adBlockVersion != _lastAdBlockVersion) {
      _lastAdBlockVersion = svc.adBlockVersion;
      if (mounted) setState(() => _webViewKey++);
    }
    if (_timeLimitBlocked &&
        widget.tab.url.isNotEmpty &&
        !widget.tab.url.startsWith('about:') &&
        !svc.isBlockedByTimeRule(widget.tab.url)) {
      _timeLimitBlocked = false;
      widget.tab.controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(widget.tab.url)),
      );
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

  Future<String?> _saveDownloadedFile(List<int> bytes, String fileName) async {
    try {
      final targetDirectory = await _getDownloadsDirectory();
      if (targetDirectory == null) return null;
      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      final sanitizedName = _sanitizeFileName(fileName);
      final safeName = sanitizedName.isEmpty
          ? 'file_${DateTime.now().millisecondsSinceEpoch}.bin'
          : sanitizedName;
      final destinationPath = await _getUniqueFilePath(
        targetDirectory.path,
        safeName,
      );
      final output = File(destinationPath);
      await output.writeAsBytes(bytes, flush: true);

      if (Platform.isAndroid) {
        try {
          await MediaScanner.loadMedia(path: destinationPath);
        } catch (e) {
          debugPrint('MediaScanner error: $e');
        }
      }

      return destinationPath;
    } catch (e) {
      debugPrint('download save error: $e');
      return null;
    }
  }

  String _extensionFromContentType(String contentType) {
    final type = contentType.split(';').first.trim().toLowerCase();
    return switch (type) {
      'application/zip' => '.zip',
      'application/x-zip-compressed' => '.zip',
      'application/vnd.rar' => '.rar',
      'application/x-7z-compressed' => '.7z',
      'application/msword' => '.doc',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document' =>
        '.docx',
      'application/vnd.ms-excel' => '.xls',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' =>
        '.xlsx',
      'application/vnd.ms-powerpoint' => '.ppt',
      'application/vnd.openxmlformats-officedocument.presentationml.presentation' =>
        '.pptx',
      'text/plain' => '.txt',
      'text/csv' => '.csv',
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'audio/mpeg' => '.mp3',
      'video/mp4' => '.mp4',
      _ => '.bin',
    };
  }

  Future<Directory?> _getDownloadsDirectory() async {
    if (!Platform.isAndroid) {
      return getApplicationDocumentsDirectory();
    }

    if (!await _checkStoragePermissions()) return null;

    for (final path in const [
      '/storage/emulated/0/Download',
      '/sdcard/Download',
      '/storage/emulated/0/Downloads',
      '/sdcard/Downloads',
    ]) {
      final dir = Directory(path);
      if (await dir.exists()) return dir;
    }

    final externalDir = await getExternalStorageDirectory();
    if (externalDir == null) return null;
    var basePath = externalDir.path;
    if (basePath.contains('/Android')) {
      basePath = basePath.split('/Android').first;
    }
    return Directory('$basePath/Download');
  }

  Future<bool> _checkStoragePermissions() async {
    if (!Platform.isAndroid) return true;
    if (await Permission.storage.isGranted) return true;
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.request().isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    return false;
  }

  Future<void> _handleFileDownload(String urlString) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Pobieranie pliku..."),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
    try {
      Uri uri;
      try {
        uri = Uri.parse(urlString);
      } catch (_) {
        try {
          uri = Uri.parse(Uri.encodeFull(Uri.decodeFull(urlString)));
        } catch (_) {
          uri = Uri.parse(urlString.replaceAll(' ', '%20'));
        }
      }

      final response = await http
          .get(uri)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw Exception('Timeout pobierania'),
          );
      if (!mounted) return;

      if (response.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Błąd pobierania: HTTP ${response.statusCode}"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final bytes = response.bodyBytes;
      final ct = (response.headers['content-type'] ?? '').toLowerCase();
      final cd = response.headers['content-disposition'] ?? '';

      // Sprawdź magic bytes czy to PDF
      final isPdf =
          bytes.length > 4 &&
          bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46;

      String fileName = _fileNameFromCd(cd);
      if (fileName.isEmpty) fileName = _fileNameFromUrl(urlString);
      if (!p.basename(fileName).contains('.')) {
        fileName += isPdf ? '.pdf' : _extensionFromContentType(ct);
      }
      fileName = _sanitizeFileName(fileName);
      if (fileName.isEmpty) {
        fileName = 'file_${DateTime.now().millisecondsSinceEpoch}.bin';
      }

      if (isPdf || fileName.toLowerCase().endsWith('.pdf')) {
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, fileName));
        await file.writeAsBytes(bytes);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PdfScreen(path: file.path, title: fileName),
            ),
          );
        }
      } else {
        final savedPath = await _saveDownloadedFile(bytes, fileName);
        if (!mounted) return;
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Zapisano pomyślnie!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          '📁 Pobrane/${p.basename(savedPath)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Nie udało się zapisać: $fileName"),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Błąd: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _fileNameFromCd(String cd) {
    if (cd.isEmpty) return '';
    final match = RegExp(
      r'''filename[^;=\n]*=((['"]).*?\2|[^;\n]*)''',
    ).firstMatch(cd);
    if (match == null) return '';
    return match.group(1)!.replaceAll('"', '').replaceAll("'", '').trim();
  }

  String _fileNameFromUrl(String url) {
    try {
      // Use Uri.dataFromString if it's a data URI, or standard parse
      final uri = Uri.tryParse(url);
      if (uri == null) return '';

      final last = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';
      // Use decodeComponent safely
      return last.isNotEmpty ? Uri.decodeComponent(last) : '';
    } catch (e) {
      // If decoding fails due to illegal percent, return the raw last segment
      // and let the sanitizer clean it
      return url.split('/').last.split('?').first;
    }
  }

  String _sanitizeFileName(String fileName) {
    return fileName
        .split('?')
        .first
        .split('/')
        .last
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<String> _getUniqueFilePath(String directory, String fileName) async {
    final file = File(p.join(directory, fileName));
    if (!await file.exists()) return file.path;

    final nameWithoutExt = p.withoutExtension(fileName);
    final extension = p.extension(fileName);
    var counter = 1;
    while (true) {
      final candidate = p.join(
        directory,
        '$nameWithoutExt ($counter)$extension',
      );
      if (!await File(candidate).exists()) return candidate;
      counter++;
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
            useShouldOverrideUrlLoading: true,
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

            // Tracking czasu — rejestruj co 5s na potrzeby limitów czasowych
            Future.doWhile(() async {
              await Future.delayed(const Duration(seconds: 5));
              if (!mounted) return false;
              if (svc.currentTab != tab) return mounted;

              final controllerUrl = await c.getUrl();
              if (!mounted) return false;
              final currentUrl = controllerUrl?.toString() ?? tab.url;
              if (currentUrl.isNotEmpty && !currentUrl.startsWith('about:')) {
                final uri = Uri.tryParse(currentUrl);
                final domain = uri?.host ?? '';
                if (domain.isNotEmpty && !_timeLimitBlocked) {
                  final reachedLimit =
                      svc.recordUsage(domain, 5) ||
                      svc.isBlockedByTimeRule(currentUrl);
                  if (reachedLimit && mounted) {
                    _timeLimitBlocked = true;
                    await c.stopLoading();
                    await c.loadUrl(
                      urlRequest: URLRequest(
                        url: WebUri('about:blank#blocked'),
                      ),
                    );
                    widget.onPasswordRequired(
                      svc,
                      WebUri(currentUrl),
                      c,
                      reason: BlockReason.timeLimit,
                      match: BlockMatch(domain, domain),
                    );
                  }
                }
              }
              return mounted;
            });

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

            // Handler dla błędów JS z console.error
            c.addJavaScriptHandler(
              handlerName: 'jsError',
              callback: (args) {
                if (args.isEmpty) return;
                debugPrint('🐛 JS Error: ${args[0]}');
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
            Future.microtask(() async {
              String urlToLoad = tab.url;
              if (svc.pendingShortcutUrl != null &&
                  svc.tabs.indexOf(tab) == svc.currentTabIndex) {
                urlToLoad = svc.pendingShortcutUrl!;
                svc.pendingShortcutUrl = null;
              }

              final blocked = await svc.handleNavigation(
                urlToLoad,
                c,
                (url, ctrl, reason, match) => widget.onPasswordRequired(
                  svc,
                  url,
                  ctrl,
                  reason: reason,
                  match: match,
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
                _timeLimitBlocked = false;
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
              final blocked = await svc.handleNavigation(
                urlString,
                c,
                (url, ctrl, reason, match) => widget.onPasswordRequired(
                  svc,
                  url,
                  ctrl,
                  reason: reason,
                  match: match,
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
              if (blocked) {
                await c.stopLoading();
                return;
              }
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

                // Łap błędy JS do debugowania logowania
                window.onerror = function(msg, src, line, col, err) {
                  console.error('🐛 BF JS Error:', msg, 'at', src, line, col);
                };
                (function() {
                  var origConsoleError = console.error;
                  console.error = function() {
                    try { window.flutter_inappwebview.callHandler('jsError', Array.prototype.slice.call(arguments).join(' ')); } catch(e) {}
                    return origConsoleError.apply(console, arguments);
                  };
                })();

                // Loguj wszystkie kliknięcia
                document.addEventListener('click', function(e) {
                  var el = e.target;
                  var tag = el.tagName || '?';
                  var text = (el.textContent || '').trim().substring(0, 40);
                  var id = el.id || '';
                  var cls = el.className || '';
                  console.log('🖱 BF Click:', tag, '"' + text + '"', '#' + id, '.' + cls);
                  // Sprawdź czy handler React jest podpięty na elemencie lub jego parentach
                  var cur = el;
                  while (cur && cur !== document.body) {
                    var reactKey = Object.keys(cur).find(function(k) { return k.indexOf('__reactProps') >= 0 || k.indexOf('__reactEventHandlers') >= 0; });
                    if (reactKey) {
                      var props = cur[reactKey];
                      console.log('🔄 BF React onClick on', cur.tagName, '.' + ((cur.className || '').substring(0,30)), ':', props && typeof props.onClick);
                      if (props && typeof props.onClick === 'function') {
                        var fnStr = props.onClick.toString().substring(0, 300);
                        console.log('🔄 BF onClick body:', fnStr);
                      }
                      break;
                    }
                    cur = cur.parentElement;
                  }
                }, true);

                // Nadpisz window.open — zamiast popupa (który nie działa na mobile),
                // przekieruj bieżącą kartę. To wymusi redirect OAuth zamiast popupa.
                var origWindowOpen = window.open;
                window.open = function(url, name, features) {
                  if (url && url !== 'about:blank' && url !== '') {
                    console.log('🪟 BF window.open with real URL:', url.substring(0, 100));
                    window.location.href = url;
                  } else {
                    console.log('🪟 BF window.open empty/blank - returning null for Supabase fallback');
                  }
                  // Zwróć null — Supabase ma fallback do window.location.href = url
                  return null;
                };

                // Loguj wszystkie fetch i XHR do debugowania logowania
                (function() {
                  var origFetch2 = window.fetch.bind(window);
                  window.fetch = function(input, init) {
                    var url = typeof input === 'string' ? input : (input && input.url) || '';
                    if (isCustom(url)) { sendCustom(url); return Promise.resolve(new Response('', {status: 200})); }
                    if (url.includes('auth.') || url.includes('supabase') || url.includes('google')) {
                      console.log('🌐 BF Fetch:', url);
                    }
                    return origFetch2(input, init).then(function(r) {
                      if (url.includes('auth.') || url.includes('supabase')) {
                        console.log('✅ BF Fetch OK:', url, r.status);
                      }
                      return r;
                    }).catch(function(e) {
                      console.error('❌ BF Fetch FAIL:', url, e.message);
                      throw e;
                    });
                  };
                })();

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
          onConsoleMessage: (controller, message) {
            debugPrint('📋 Console: [${message.messageLevel}] ${message.message}');
          },
          onDownloadStartRequest: (controller, downloadRequest) async {
            _handleFileDownload(downloadRequest.url.toString());
          },
          onCreateWindow: (controller, createWindowAction) async {
            final url = createWindowAction.request.url;
            var urlString = url?.toString() ?? '';
            debugPrint('🪟 onCreateWindow: "$urlString"');

            if (urlString.isEmpty || urlString == 'about:blank') {
              // Supabase/ OAuth otwiera pusty popup a potem ustawia location.
              // Nie blokuj – nawiguj bieżącą kartę. Strona po chwili
              // dostanie błąd (popup nie istnieje) i sama przekieruje
              // (fallback redirect).
              return false;
            }

            // Mobile WebView nie wspiera popupów z window.opener.
            // Nawiguj bieżącą kartę zamiast tworzyć nową.
            svc.currentTab.url = urlString;
            svc.currentTab.controller?.loadUrl(
              urlRequest: URLRequest(url: WebUri(urlString)),
            );
            svc.notifyUI();
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

            // Przechwytuj pliki po rozszerzeniu — serwer może nie wysyłać
            // Content-Disposition:attachment więc onDownloadStartRequest nie odpala
            const _downloadExts = {
              '.docx',
              '.doc',
              '.xlsx',
              '.xls',
              '.pptx',
              '.ppt',
              '.zip',
              '.rar',
              '.7z',
              '.tar',
              '.gz',
              '.apk',
              '.exe',
              '.dmg',
              '.mp3',
              '.mp4',
              '.avi',
              '.mkv',
              '.mov',
              '.jpg',
              '.jpeg',
              '.png',
              '.gif',
              '.webp',
              '.txt',
              '.csv',
              '.xml',
              '.json',
              '.pdf',
            };
            final decodedUrl = Uri.decodeFull(
              urlString.split('?').first.toLowerCase(),
            );
            final ext = '.${decodedUrl.split('.').last}';
            if (_downloadExts.contains(ext)) {
              // Uruchom pobieranie w tle — nie nawiguj
              _handleFileDownload(urlString);
              return NavigationActionPolicy.CANCEL;
            }

            // Obsługa nawigacji (hasła, czarna lista)
            final blocked = await svc.handleNavigation(
              urlString,
              c,
              (url, ctrl, reason, match) => widget.onPasswordRequired(
                svc,
                url,
                ctrl,
                reason: reason,
                match: match,
              ),
              (message) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.redAccent,
                ),
              ),
            );

            if (!blocked) {
              _timeLimitBlocked = false;
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
