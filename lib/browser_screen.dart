import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'browser_service.dart';
import 'search_engine_picker.dart';
import 'browser_screen_dialogs.dart';
import 'webview_tab.dart';
import 'qr_scanner_screen.dart';

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowserScreen({super.key, this.initialUrl});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with BrowserScreenDialogsMixin {
  final TextEditingController urlController = TextEditingController();
  final FocusNode urlFocusNode = FocusNode();
  TabModel? _lastUrlTab;
  int _urlBarTapCount = 0;

  @override
  void initState() {
    super.initState();
    urlFocusNode.addListener(() {
      if (mounted) {
        if (!urlFocusNode.hasFocus) {
          _urlBarTapCount = 0;
          urlController.text = context.read<BrowserService>().currentTab.url;
        }
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<BrowserService>();
      _lastUrlTab = svc.currentTab;
      svc.addListener(_handlePendingShortcut);
      _handlePendingShortcut();
      // Czekaj na zakończenie init() zanim sprawdzisz czy wyszukiwarka jest wybrana
      svc.ready.then((_) {
        if (!mounted) return;
        if (!svc.searchEngineSelected && svc.searchEngineUrl.isEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const SearchEnginePicker(onboarding: true),
              fullscreenDialog: true,
            ),
          );
        }
      });
    });
  }

  void _handlePendingShortcut() {
    final svc = context.read<BrowserService>();
    final url = svc.pendingShortcutUrl;
    if (url == null) return;

    svc.pendingShortcutUrl = null;

    final existingIndex = svc.tabs.indexWhere((tab) => tab.url == url);
    if (existingIndex != -1) {
      svc.switchTab(existingIndex);
    } else {
      svc.addNewTab();
      if (svc.tabs.isNotEmpty) {
        svc.tabs.last.url = url;
        svc.notifyUI();
      }
    }
  }

  @override
  void dispose() {
    context.read<BrowserService>().removeListener(_handlePendingShortcut);
    urlFocusNode.dispose();
    urlController.dispose();
    super.dispose();
  }

  Color get _surfaceColor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 84, 19, 120)
      : const Color(0xFF303134);

  Color get _bgColor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 74, 31, 127)
      : const Color(0xFF202124);

  Future<void> _openQrScanner(BrowserService svc) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result == null || result.isEmpty) return;

    final isUrl = result.startsWith('http://') || result.startsWith('https://');

    if (isUrl) {
      // Otwórz URL w bieżącej karcie
      final webUri = WebUri(result);
      svc.currentTab.controller?.loadUrl(urlRequest: URLRequest(url: webUri));
      urlController.text = result;
    } else {
      // Pokaż dialog z opcjami dla zwykłego tekstu
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            'Zeskanowany kod QR',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(result, style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: result));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Skopiowano do schowka'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('KOPIUJ', style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                final searchUrl = svc.buildTargetUrl(result);
                svc.currentTab.controller?.loadUrl(
                  urlRequest: URLRequest(url: searchUrl),
                );
                urlController.text = result;
              },
              child: const Text('SZUKAJ', style: TextStyle(color: Colors.blue)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'ZAMKNIJ',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }
  }

  Color get _bordercolor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 182, 81, 199).withOpacity(0.5)
      : const Color.fromARGB(255, 255, 255, 255);

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BrowserService>();
    final currentTab = svc.currentTab;
    final currentUrl = currentTab.url;
    if (!identical(currentTab, _lastUrlTab)) {
      _lastUrlTab = currentTab;
      urlController.text = currentUrl;
      if (urlFocusNode.hasFocus) {
        urlFocusNode.unfocus();
      }
    } else if (urlController.text != currentUrl && !urlFocusNode.hasFocus) {
      urlController.text = currentUrl;
    }
    final modeTabs = svc.tabs.where(
      (t) => t.isIncognito == svc.incognitoMode,
    ).toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final controller = svc.currentTab.controller;
          if (controller != null && await controller.canGoBack()) {
            await controller.goBack();
          }
        },
        child: Scaffold(
          backgroundColor: svc.incognitoMode
              ? const Color.fromARGB(255, 116, 31, 162)
              : Colors.black,
          endDrawer: buildSettingsDrawer(svc),
          body: Column(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    // PASEK KART (tylko karty bieżącego trybu)
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: modeTabs.length,
                              itemBuilder: (context, i) {
                                final tab = modeTabs[i];
                                final index = svc.tabs.indexOf(tab);
                                return GestureDetector(
                                  onTap: () {
                                    debugPrint(
                                      '🔍 tabBar tap: index=$index tab=$tab',
                                    );
                                    svc.switchTab(index);
                                  },
                                  child: Container(
                                    margin:
                                        const EdgeInsets.only(right: 4),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: index == svc.currentTabIndex
                                          ? _surfaceColor
                                          : _bgColor.withOpacity(0.6),
                                      borderRadius:
                                          const BorderRadius.vertical(
                                        top: Radius.circular(10),
                                      ),
                                      border: index == svc.currentTabIndex
                                          ? Border.all(
                                              color: _bordercolor,
                                              width: 1,
                                            )
                                          : null,
                                    ),
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (svc.tabs[index]
                                              .isPlayingAudio)
                                            const Padding(
                                              padding:
                                                  EdgeInsets.only(right: 4),
                                              child: Icon(
                                                Icons.volume_up,
                                                size: 11,
                                                color:
                                                    Colors.lightBlueAccent,
                                              ),
                                            ),
                                          Flexible(
                                            child: Text(
                                              svc.tabs[index].title,
                                              style: TextStyle(
                                                color: index ==
                                                        svc.currentTabIndex
                                                    ? Colors.white
                                                    : Colors.grey,
                                                fontSize: 11,
                                              ),
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.add,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () {
                              svc.addNewTab();
                              urlController.text = svc.currentTab.url;
                            },
                          ),
                        ],
                      ),
                    ),

                    // TOOLBAR
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 40,
                              decoration: BoxDecoration(
                                color: _surfaceColor,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: TextField(
                                controller: urlController,
                                focusNode: urlFocusNode,
                                textAlignVertical: TextAlignVertical.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  suffixIcon: urlFocusNode.hasFocus
                                      ? null
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.copy,
                                            color: Colors.grey,
                                            size: 16,
                                          ),
                                          tooltip: 'Kopiuj link',
                                          onPressed: () {
                                            final url = urlController.text;
                                            if (url.isNotEmpty) {
                                              Clipboard.setData(
                                                ClipboardData(text: url),
                                              );
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons.check_circle,
                                                        color: Colors.white,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'Skopiowano: $url',
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  backgroundColor:
                                                      Colors.green.shade700,
                                                  behavior:
                                                      SnackBarBehavior.floating,
                                                  duration: const Duration(
                                                    seconds: 2,
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                ),
                                onTap: () {
                                  if (urlController.text.isEmpty) return;
                                  _urlBarTapCount++;
                                  if (_urlBarTapCount >= 3) {
                                    urlFocusNode.unfocus();
                                  } else if (_urlBarTapCount == 2) {
                                    urlController.selection = TextSelection.collapsed(
                                      offset: urlController.text.length,
                                    );
                                  } else {
                                    urlController.selection = TextSelection(
                                      baseOffset: 0,
                                      extentOffset: urlController.text.length,
                                    );
                                  }
                                },
                                onSubmitted: (v) async {
                                  _urlBarTapCount = 0;
                                  final ctrl = svc.currentTab.controller;
                                  debugPrint(
                                    '🔍 onSubmitted: v="$v" ctrl=$ctrl tabIdx=${svc.tabs.indexOf(svc.currentTab)}',
                                  );
                                  if (ctrl == null) {
                                    debugPrint('🔍 onSubmitted: ctrl IS NULL - return');
                                    return;
                                  }
                                  final targetUrl = svc.buildTargetUrl(v);
                                  final targetUrlString = targetUrl.toString();
                                  debugPrint('🔍 onSubmitted: targetUrl=$targetUrlString');

                                  final blocked = await svc.handleNavigation(
                                    targetUrlString,
                                    ctrl,
                                    (url, ctrl, reason, match) =>
                                        showPasswordDialog(
                                          svc,
                                          url,
                                          ctrl,
                                          reason: reason,
                                          match: match,
                                        ),
                                    (message) => ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                          SnackBar(
                                            content: Text(message),
                                            backgroundColor: Colors.redAccent,
                                            behavior:
                                                SnackBarBehavior.floating,
                                          ),
                                        ),
                                  );
                                  debugPrint('🔍 onSubmitted: blocked=$blocked');

                                  if (!blocked) {
                                    ctrl.loadUrl(
                                      urlRequest: URLRequest(url: targetUrl),
                                    );
                                    debugPrint('🔍 onSubmitted: loadUrl called');
                                  }
                                },
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => showTabsManager(svc, urlController),
                            child: Container(
                              margin: const EdgeInsets.only(left: 8),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Colors.grey,
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  "${svc.tabs.length}",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.refresh,
                              color: Colors.white,
                            ),
                            tooltip: 'Odśwież stronę',
                            onPressed: () =>
                                svc.currentTab.controller?.reload(),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.white,
                            ),
                            tooltip: 'Skaner QR',
                            onPressed: () => _openQrScanner(svc),
                          ),
                          Builder(
                            builder: (ctx) => IconButton(
                              icon: const Icon(
                                Icons.more_vert,
                                color: Colors.grey,
                              ),
                              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // WEBVIEW — dwa współdzielone + IndexedStack
              Expanded(
                child: IndexedStack(
                  index: svc.incognitoMode ? 1 : 0,
                  children: [
                    WebViewTab(
                      key: const ValueKey('normal_webview'),
                      tab: svc.normalTab,
                      svc: svc,
                      urlController: urlController,
                      incognito: false,
                      onPasswordRequired: (
                        svc,
                        url,
                        ctrl, {
                        reason = BlockReason.content,
                        BlockMatch? match,
                      }) {
                        showPasswordDialog(
                          svc,
                          url,
                          ctrl,
                          reason: reason,
                          match: match,
                        );
                      },
                    ),
                    WebViewTab(
                      key: const ValueKey('incognito_webview'),
                      tab: svc.incognitoTab ??
                          TabModel(url: 'about:blank', loaded: true),
                      svc: svc,
                      urlController: urlController,
                      incognito: true,
                      onPasswordRequired: (
                        svc,
                        url,
                        ctrl, {
                        reason = BlockReason.content,
                        BlockMatch? match,
                      }) {
                        showPasswordDialog(
                          svc,
                          url,
                          ctrl,
                          reason: reason,
                          match: match,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
