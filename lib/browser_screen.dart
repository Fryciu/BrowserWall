import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'browser_service.dart';
import 'package:flutter/services.dart';
import 'pdf_screen.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';
import 'package:http/http.dart' as http;
import 'package:media_scanner/media_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart' as url_launcher;

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  const BrowserScreen({super.key, this.initialUrl});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final TextEditingController urlController = TextEditingController();
  final FocusNode urlFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    urlFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<BrowserService>();
      svc.addListener(_handlePendingShortcut);
      _handlePendingShortcut();
    });
  }

  void _handlePendingShortcut() {
    final svc = context.read<BrowserService>();
    final url = svc.pendingShortcutUrl;
    if (url == null) return;

    final existingIndex = svc.tabs.indexWhere((tab) => tab.url == url);
    if (existingIndex != -1) {
      svc.pendingShortcutUrl = null;
      svc.switchTab(existingIndex);
    } else {
      svc.pendingShortcutUrl = null;
      svc.addNewTab();
      svc.pendingShortcutUrl = url;
    }
  }

  @override
  /// Called when this object is about to be removed from the tree.
  ///
  /// This is where you should release any resources your object is using.
  /// For example, if your object has a reference to a network connection,
  /// or if it is maintaining a large in-memory data structure, you should
  /// release that connection or data structure here.
  ///
  /// You should also call [super.dispose] to complete the dispose.
  /// In general, it is recommended that you implement [dispose] to
  /// break any circular references your object has with other objects, and
  /// to release any resources your object is using that are not being used by
  /// other objects.
  ///
  /// If you subclass this class, make sure to include a call to
  /// [super.dispose] when you override [dispose].
  ///
  /// This method should not be used to dispose any resources that are being
  /// used by other objects. Instead, the resources should be released when they
  /// are no longer needed, which is usually (but not always) in the
  /// [dispose] method.
  ///
  /// See also: [WidgetsBinding.dispose]], and [State.dispose].
  void dispose() {
    context.read<BrowserService>().removeListener(_handlePendingShortcut);
    urlFocusNode.dispose();
    urlController.dispose();
    super.dispose();
  }

  void _showPasswordDialog(
    BrowserService svc,
    WebUri url,
    InAppWebViewController? controller,
  ) {
    //controller?.loadUrl(urlRequest: URLRequest(url: url));
    //return;
    if (svc.canSkipAuth(url.toString())) {
      controller?.loadUrl(urlRequest: URLRequest(url: url));
      return;
    }
    if (svc.isVerifying) return;
    svc.isVerifying = true;

    String enteredPass = "";
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          "Strona Chroniona",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          style: const TextStyle(color: Colors.white),
          obscureText: true,
          autofocus: true,
          onChanged: (v) => enteredPass = v,
          decoration: const InputDecoration(
            hintText: "Wpisz hasło",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              svc.isVerifying = false;
              Navigator.pop(context);
            },
            child: const Text("ANULUJ", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              svc.isVerifying = false;
              if (svc.verifyPassword(enteredPass)) {
                svc.recordAuth(url.toString());
                Navigator.pop(context);
                controller?.loadUrl(urlRequest: URLRequest(url: url));
              } else {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Błędne hasło!")));
              }
            },
            child: const Text(
              "ODBLOKUJ",
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static const _channel = MethodChannel('app/shortcuts');

  /// Shows a dialog asking for a shortcut name, and saves the shortcut to shared preferences
  /// if the user confirms. If the user cancels the dialog, does nothing.
  /// If the user enters an empty name, does nothing.
  /// If an error occurs while saving the shortcut, shows a snackbar with an error message.
  Future<void> _addShortcut(BrowserService svc) async {
    final currentUrl = svc.currentTab.url;
    String name = svc.currentTab.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text('Dodaj skrót', style: TextStyle(color: Colors.white)),
        content: TextField(
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          controller: TextEditingController(text: name),
          onChanged: (v) => name = v,
          decoration: const InputDecoration(
            hintText: 'Nazwa skrótu',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.blue),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANULUJ', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DODAJ', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );

    if (confirmed != true || name.isEmpty) return;

    try {
      await _channel.invokeMethod('createShortcut', {
        'name': name,
        'url': currentUrl,
      });
      await svc.saveShortcut(name, currentUrl);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się dodać skrótu'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Shows a dialog asking for a password to access a website.
  ///
  /// Returns `true` if the user enters a correct password, and `false` otherwise.
  ///
  /// If the user cancels the dialog, `null` is returned.
  Future<bool?> _askForPasswordOnly(BrowserService svc) {
    String entered = "";
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          "Wymagane hasło",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onChanged: (v) => entered = v,
          decoration: const InputDecoration(hintText: "Wpisz hasło"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("ANULUJ"),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, svc.verifyPassword(entered)),
            child: const Text("POTWIERDŹ"),
          ),
        ],
      ),
    );
  }

  void _showAdBlockMenu(BrowserService svc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.blue),
                    onPressed: () {
                      Navigator.pop(context);
                      _showSettingsMenu(svc);
                    },
                  ),
                  const Icon(Icons.shield, color: Colors.green, size: 22),
                  const SizedBox(width: 8),
                  const Text(
                    "AdBlock",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.grey),
            SwitchListTile(
              title: const Text(
                "AdBlock",
                style: TextStyle(color: Colors.white),
              ),
              secondary: Icon(
                Icons.shield,
                color: svc.adBlockEnabled ? Colors.green : Colors.grey,
              ),
              value: svc.adBlockEnabled,
              onChanged: (val) async {
                await svc.setAdBlock(val);
                setModalState(() {});
                svc.currentTab.controller?.reload();
              },
            ),
            ListTile(
              leading: const Icon(Icons.checklist, color: Colors.blue),
              title: const Text(
                "Wyjątki (wyłączony AdBlock)",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                "${svc.adBlockWhitelist.length} stron",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                _showAdBlockWhitelist(svc);
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  void _showAdBlockWhitelist(BrowserService svc) {
    final addC = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            "Wyjątki AdBlock",
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addC,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Dodaj domenę (np. example.com)",
                    hintStyle: const TextStyle(color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, color: Colors.blue),
                      onPressed: () {
                        if (addC.text.isNotEmpty) {
                          svc.addToAdBlockWhitelist(addC.text);
                          addC.clear();
                          setDS(() {});
                        }
                      },
                    ),
                  ),
                ),
                const Divider(color: Colors.grey),
                Flexible(
                  child: svc.adBlockWhitelist.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            "Brak wyjątków — AdBlock działa na wszystkich stronach",
                            style: TextStyle(color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: svc.adBlockWhitelist.length,
                          itemBuilder: (context, index) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.language,
                              color: Colors.blue,
                              size: 18,
                            ),
                            title: Text(
                              svc.adBlockWhitelist[index],
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: () {
                                svc.removeFromAdBlockWhitelist(index);
                                setDS(() {});
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "ZAMKNIJ",
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSettingsMenu(BrowserService svc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: Icon(
              Icons.shield,
              color: svc.adBlockEnabled ? Colors.green : Colors.grey,
            ),
            title: const Text("AdBlock", style: TextStyle(color: Colors.white)),
            subtitle: Text(
              svc.adBlockEnabled
                  ? "Włączony • może nie działać na każdej stronie i powodować problemy"
                  : "Wyłączony",
              style: TextStyle(
                color: svc.adBlockEnabled ? Colors.orange : Colors.grey,
                fontSize: 11,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.pop(context);
              _showAdBlockMenu(svc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, color: Colors.blue),
            title: const Text(
              "Historia",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _showHistory(svc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.block, color: Colors.redAccent),
            title: const Text("Blokady", style: TextStyle(color: Colors.white)),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            onTap: () {
              Navigator.pop(context);
              _showBlockingMenu(svc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_to_home_screen, color: Colors.blue),
            title: const Text(
              'Dodaj skrót do ekranu głównego',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _addShortcut(svc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
            title: const Text(
              "Wyczyść dane przeglądania",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () async {
              Navigator.pop(context);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF202124),
                  title: const Text(
                    'Wyczyść dane',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: const Text(
                    'Usuniesz ciasteczka, cache i dane stron.\nZostaniesz wylogowany ze wszystkich stron.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'ANULUJ',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text(
                        'WYCZYŚĆ',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await CookieManager.instance().deleteAllCookies();
                await InAppWebViewController.clearAllCache();
                svc.currentTab.controller?.reload();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dane przeglądania wyczyszczone'),
                    ),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.grey),
            title: const Text(
              'O aplikacji',
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF202124),
                  title: const Text(
                    'O aplikacji',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset('assets/icon.png', width: 80, height: 80),
                        const SizedBox(height: 8),
                        const Text(
                          'BrowserFocus',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Wersja 1.0.0',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 4),
                        const Text(
                          'Kontakt',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse('mailto:pagafryba@gmail.com');
                            if (await url_launcher.canLaunchUrl(uri)) {
                              await url_launcher.launchUrl(
                                uri,
                                mode:
                                    url_launcher.LaunchMode.externalApplication,
                              );
                            } else {
                              Navigator.pop(ctx);
                              svc.currentTab.controller?.loadUrl(
                                urlRequest: URLRequest(
                                  url: WebUri(
                                    'https://mail.google.com/mail/?view=cm&to=pagafryba@gmail.com',
                                  ),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'pagafryba@gmail.com',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse('https://github.com/Fryciu');
                            if (await url_launcher.canLaunchUrl(uri)) {
                              await url_launcher.launchUrl(
                                uri,
                                mode:
                                    url_launcher.LaunchMode.externalApplication,
                              );
                            } else {
                              Navigator.pop(ctx);
                              svc.currentTab.controller?.loadUrl(
                                urlRequest: URLRequest(
                                  url: WebUri('https://github.com/Fryciu'),
                                ),
                              );
                            }
                          },
                          child: const Text(
                            'github.com/Fryciu',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 4),
                        const Text(
                          'Ikona aplikacji:',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            svc.currentTab.controller?.loadUrl(
                              urlRequest: URLRequest(
                                url: WebUri(
                                  'https://www.flaticon.com/free-icons/isometric',
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Isometric icons created by Freepik - Flaticon',
                            style: TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'ZAMKNIJ',
                        style: TextStyle(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  void _showBlockingMenu(BrowserService svc) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.blue),
                  onPressed: () {
                    Navigator.pop(context);
                    _showSettingsMenu(svc);
                  },
                ),
                const Icon(Icons.block, color: Colors.redAccent, size: 22),
                const SizedBox(width: 8),
                const Text(
                  "Blokady",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.grey),

          SwitchListTile(
            title: const Text(
              "Filtr treści (Porno/SafeSearch)",
              style: TextStyle(color: Colors.white),
            ),
            secondary: Icon(
              Icons.eighteen_up_rating_outlined,
              color: svc.adultFilterEnabled ? Colors.red : Colors.green,
            ),
            value: svc.adultFilterEnabled,
            onChanged: (val) async {
              if (!val && svc.savedPassword != null) {
                final granted = await _askForPasswordOnly(svc);
                if (granted != true) return;
              }
              await svc.setAdultFilter(val);
              if (mounted) Navigator.pop(context);
              svc.currentTab.controller?.reload();
            },
          ),
          ListTile(
            leading: const Icon(Icons.playlist_remove, color: Colors.redAccent),
            title: const Text(
              "Czarna lista",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _showListEditor(svc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Colors.orange),
            title: const Text(
              "Ustawienia hasła",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _setupPassword(svc);
            },
          ),
          ListTile(
            leading: const Icon(Icons.file_present, color: Colors.orange),
            title: const Text(
              "Zablokowane pliki",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(context);
              _showExtensionsEditor(svc);
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  void _showExtensionsEditor(BrowserService svc) {
    final addC = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            "Zablokowane rozszerzenia",
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addC,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Dodaj rozszerzenie (np. pdf)",
                    hintStyle: const TextStyle(color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, color: Colors.blue),
                      onPressed: () {
                        if (addC.text.isNotEmpty) {
                          svc.addBlockedExtension(addC.text);
                          addC.clear();
                          setDS(() {});
                        }
                      },
                    ),
                  ),
                ),
                const Divider(color: Colors.grey),
                Flexible(
                  child: svc.blockedExtensions.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            "Lista jest pusta",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: svc.blockedExtensions.length,
                          itemBuilder: (context, index) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.extension,
                              color: Colors.orange,
                              size: 18,
                            ),
                            title: Text(
                              ".${svc.blockedExtensions[index]}",
                              style: const TextStyle(color: Colors.white),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: () async {
                                if (svc.savedPassword != null) {
                                  final granted = await _askForPasswordOnly(
                                    svc,
                                  );
                                  if (granted != true) return;
                                }
                                svc.removeBlockedExtension(index);
                                setDS(() {});
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "ZAMKNIJ",
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Zarządzanie kartami ──────────────────────

  void _showTabsManager(BrowserService svc) {
    final Set<int> selected = {};
    bool selectionMode = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF202124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            children: [
              // NAGŁÓWEK
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    if (selectionMode) ...[
                      Text(
                        "Zaznaczono: ${selected.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            if (selected.length == svc.tabs.length) {
                              selected.clear();
                            } else {
                              selected.addAll(
                                List.generate(svc.tabs.length, (i) => i),
                              );
                            }
                          });
                        },
                        child: Text(
                          selected.length == svc.tabs.length
                              ? "Odznacz wszystkie"
                              : "Zaznacz wszystkie",
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        tooltip: "Zamknij zaznaczone",
                        onPressed: selected.isEmpty
                            ? null
                            : () {
                                // Zamykamy od końca żeby indeksy się nie przesuwały
                                final toClose = selected.toList()
                                  ..sort((a, b) => b.compareTo(a));
                                for (final i in toClose) {
                                  if (svc.tabs.length > 1) svc.closeTab(i);
                                }
                                urlController.text = svc.currentTab.url;
                                setModalState(() {
                                  selected.clear();
                                  selectionMode = false;
                                });
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => setModalState(() {
                          selected.clear();
                          selectionMode = false;
                        }),
                      ),
                    ] else ...[
                      Text(
                        "Otwarte karty (${svc.tabs.length})",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          svc.closeAllTabs();
                          urlController.text = svc.currentTab.url;
                          Navigator.pop(context);
                        },
                        child: const Text(
                          "Zamknij wszystkie",
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.grey),
              // LISTA KART
              Expanded(
                child: ListView.builder(
                  itemCount: svc.tabs.length,
                  itemBuilder: (context, index) {
                    final isSelected = selected.contains(index);
                    final isActive = index == svc.currentTabIndex;
                    return GestureDetector(
                      onLongPress: () {
                        setModalState(() {
                          selectionMode = true;
                          selected.add(index);
                        });
                      },
                      child: ListTile(
                        selected: isActive && !selectionMode,
                        selectedTileColor: Colors.blue.withOpacity(0.1),
                        tileColor: isSelected
                            ? Colors.blue.withOpacity(0.15)
                            : null,
                        leading: selectionMode
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (_) {
                                  setModalState(() {
                                    if (isSelected) {
                                      selected.remove(index);
                                      if (selected.isEmpty) {
                                        selectionMode = false;
                                      }
                                    } else {
                                      selected.add(index);
                                    }
                                  });
                                },
                                activeColor: Colors.blue,
                              )
                            : const Icon(Icons.tab, color: Colors.blue),
                        title: Text(
                          svc.tabs[index].title,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                        ),
                        subtitle: Text(
                          svc.tabs[index].url,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                        ),
                        trailing: selectionMode
                            ? null
                            : IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.grey,
                                ),
                                onPressed: () {
                                  if (svc.tabs.length > 1) {
                                    svc.closeTab(index);
                                    urlController.text = svc.currentTab.url;
                                    setModalState(() {});
                                  }
                                },
                              ),
                        onTap: selectionMode
                            ? () {
                                setModalState(() {
                                  if (isSelected) {
                                    selected.remove(index);
                                    if (selected.isEmpty) selectionMode = false;
                                  } else {
                                    selected.add(index);
                                  }
                                });
                              }
                            : () {
                                svc.switchTab(index);
                                urlController.text = svc.currentTab.url;
                                Navigator.pop(context);
                              },
                      ),
                    );
                  },
                ),
              ),
              // PRZYCISK NOWEJ KARTY — ukryty w trybie zaznaczania
              if (!selectionMode)
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      svc.addNewTab();
                      urlController.text = svc.currentTab.url;
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Nowa karta"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  // ── Hasło ────────────────────────────────────

  void _setupPassword(BrowserService svc) {
    showDialog(
      context: context,
      builder: (context) => _PasswordDialog(svc: svc),
    );
  }

  // ── Czarna lista ─────────────────────────────

  void _showListEditor(BrowserService svc) {
    final addC = TextEditingController();
    bool authenticated = svc.savedPassword == null; // ← poza showDialog

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: Row(
            children: [
              const Expanded(
                child: Text(
                  "Czarna lista",
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_sweep,
                  color: Colors.red,
                  size: 28,
                ),
                tooltip: "Wyczyść wszystko",
                onPressed: () async {
                  if (!authenticated) {
                    final granted = await _askForPasswordOnly(svc);
                    if (granted != true) return;
                    authenticated = true;
                  }
                  await svc.clearBlackList();
                  setDS(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Lista została całkowicie wyczyszczona"),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: addC,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Dodaj domenę (np. facebook.com)",
                    hintStyle: const TextStyle(color: Colors.grey),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add, color: Colors.blue),
                      onPressed: () {
                        if (addC.text.isNotEmpty) {
                          svc.addToBlackList(addC.text);
                          addC.clear();
                          setDS(() {});
                        }
                      },
                    ),
                  ),
                ),
                const Divider(color: Colors.grey),
                Flexible(
                  child: svc.blackList.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text(
                            "Lista jest pusta",
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: svc.blackList.length,
                          itemBuilder: (context, index) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              svc.blackList[index],
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: () async {
                                if (!authenticated) {
                                  final granted = await _askForPasswordOnly(
                                    svc,
                                  );
                                  if (granted != true) return;
                                  authenticated = true;
                                }
                                svc.removeFromBlackList(index);
                                setDS(() {});
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "ZAMKNIJ",
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // ── Historia ─────────────────────────────────

  void _showHistory(BrowserService svc) {
    Map<String, List<Map<String, String>>> grouped = {};
    for (final entry in svc.history) {
      final date = entry['date'] ?? 'Nieznana data';
      grouped.putIfAbsent(date, () => []).add(entry);
    }
    final days = grouped.keys.toList();
    final Set<Map<String, String>> selected = {};
    bool selectionMode = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF202124),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // NAGŁÓWEK
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                child: Row(
                  children: [
                    // TRYB INCOGNITO
                    GestureDetector(
                      onTap: () async {
                        await svc.toggleIncognito();
                        setModalState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: svc.incognitoMode
                              ? Colors.purple.withOpacity(0.3)
                              : const Color(0xFF303134),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: svc.incognitoMode
                                ? Colors.purple
                                : Colors.grey,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_off,
                              size: 14,
                              color: svc.incognitoMode
                                  ? Colors.purple
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              svc.incognitoMode ? "Incognito" : "Normalny",
                              style: TextStyle(
                                color: svc.incognitoMode
                                    ? Colors.purple
                                    : Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12), // ← tutaj
                    // Jeśli tryb zaznaczania — pokaż licznik i przyciski akcji
                    if (selectionMode) ...[
                      Text(
                        "Zaznaczono: ${selected.length}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setModalState(() {
                            // Zaznacz wszystkie
                            if (selected.length == svc.history.length) {
                              selected.clear();
                            } else {
                              selected.addAll(svc.history);
                            }
                          });
                        },
                        child: Text(
                          selected.length == svc.history.length
                              ? "Odznacz wszystkie"
                              : "Zaznacz wszystkie",
                          style: const TextStyle(
                            color: Colors.blue,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                await svc.removeHistoryEntries(
                                  selected.toList(),
                                );
                                _rebuildGrouped(svc, grouped, days);
                                setModalState(() {
                                  selected.clear();
                                  selectionMode = false;
                                });
                              },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => setModalState(() {
                          selected.clear();
                          selectionMode = false;
                        }),
                      ),
                    ] else ...[
                      const Text(
                        "Historia",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.timer, color: Colors.orange),
                        tooltip: "Szybkie usuwanie",
                        onPressed: () => _showQuickDeleteDialog(
                          context,
                          svc,
                          setModalState,
                          grouped,
                          days,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.date_range, color: Colors.blue),
                        tooltip: "Usuń zakres dat",
                        onPressed: () => _showRangeDeleteDialog(
                          context,
                          svc,
                          setModalState,
                          grouped,
                          days,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(color: Colors.grey),
              // LISTA
              Expanded(
                child: svc.history.isEmpty
                    ? const Center(
                        child: Text(
                          "Brak historii",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: days.length,
                        itemBuilder: (context, dayIndex) {
                          final day = days[dayIndex];
                          final entries = grouped[day]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // NAGŁÓWEK DNIA
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  8,
                                  4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      _formatDate(day),
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    if (!selectionMode)
                                      TextButton(
                                        onPressed: () async {
                                          await svc.clearHistoryForDay(day);
                                          setModalState(() {
                                            grouped.remove(day);
                                            days.removeAt(dayIndex);
                                          });
                                        },
                                        child: const Text(
                                          "Usuń dzień",
                                          style: TextStyle(
                                            color: Colors.redAccent,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // WPISY
                              ...entries.map((entry) {
                                final isSelected = selected.contains(entry);
                                return GestureDetector(
                                  onLongPress: () {
                                    setModalState(() {
                                      selectionMode = true;
                                      selected.add(entry);
                                    });
                                  },
                                  child: ListTile(
                                    dense: true,
                                    selected: isSelected,
                                    selectedTileColor: Colors.blue.withOpacity(
                                      0.15,
                                    ),
                                    leading: selectionMode
                                        ? Checkbox(
                                            value: isSelected,
                                            onChanged: (_) {
                                              setModalState(() {
                                                if (isSelected) {
                                                  selected.remove(entry);
                                                  if (selected.isEmpty) {
                                                    selectionMode = false;
                                                  }
                                                } else {
                                                  selected.add(entry);
                                                }
                                              });
                                            },
                                            activeColor: Colors.blue,
                                          )
                                        : const Icon(
                                            Icons.history,
                                            color: Colors.grey,
                                            size: 18,
                                          ),
                                    title: Text(
                                      entry['title']!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      "${entry['time']} • ${entry['url']}",
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: selectionMode
                                        ? () {
                                            setModalState(() {
                                              if (isSelected) {
                                                selected.remove(entry);
                                                if (selected.isEmpty) {
                                                  selectionMode = false;
                                                }
                                              } else {
                                                selected.add(entry);
                                              }
                                            });
                                          }
                                        : () {
                                            svc.currentTab.controller?.loadUrl(
                                              urlRequest: URLRequest(
                                                url: WebUri(entry['url']!),
                                              ),
                                            );
                                            Navigator.pop(context);
                                          },
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper do ładnego formatowania daty
  String _formatDate(String dateStr) {
    final today = DateTime.now().toString().substring(0, 10);
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toString()
        .substring(0, 10);

    if (dateStr == today) return "Dzisiaj";
    if (dateStr == yesterday) return "Wczoraj";
    return dateStr; // "2026-03-14" jeśli starsze
  }

  void _showQuickDeleteDialog(
    BuildContext sheetContext,
    BrowserService svc,
    StateSetter setModalState,
    Map<String, List<Map<String, String>>> grouped,
    List<String> days,
  ) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          "Szybkie usuwanie",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Usuń historię z ostatnich X dni:",
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: "np. 7",
                hintStyle: TextStyle(color: Colors.grey),
                suffixText: "dni",
                suffixStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("ANULUJ", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              final days_back = int.tryParse(controller.text);
              if (days_back == null || days_back <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Podaj poprawną liczbę dni")),
                );
                return;
              }
              await svc.clearHistoryFromDaysBack(days_back);
              _rebuildGrouped(svc, grouped, days);
              setModalState(() {});
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              "USUŃ",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _copyContentUriToTempFile(
    String contentUri,
    String fileName,
  ) async {
    try {
      // Używamy natywnego mechanizmu InAppWebView do pobierania danych z content://
      // lub standardowego podejścia przez bajty, jeśli mamy dostęp.
      // Najbezpieczniej dla plików PDF jest użyć pomocnika:

      final directory = await getTemporaryDirectory();
      final tempFile = File('${directory.path}/$fileName');

      // Używamy natywnego kanału, aby odczytać strumień z ContentResolver
      // W Flutterze najprościej użyć paczki 'open_file' lub 'flutter_lib_phonenumber'
      // ALE w Twoim przypadku możemy użyć zapytania do systemu przez platform channel
      // lub sprawdzić, czy InAppWebView udostępnia dane.

      // Alternatywa: Jeśli masz dostęp do bajtów przez http (nie zadziała dla content://)
      // Dlatego musimy obsłużyć to specyficznie dla Androida.

      // Prostsze rozwiązanie: użyjemy biblioteki, którą już masz lub wbudowanych narzędzi
      // Jeśli nie chcesz dodawać paczek, musimy przechwycić to przed onDownloadStart.

      return null;
    } catch (e) {
      print("Błąd kopiowania content:// $e");
      return null;
    }
  }

  void _showRangeDeleteDialog(
    BuildContext sheetContext,
    BrowserService svc,
    StateSetter setModalState,
    Map<String, List<Map<String, String>>> grouped,
    List<String> days,
  ) {
    final oldest = svc.oldestHistoryDate ?? DateTime.now();
    DateTime selectedFrom = oldest;
    DateTime selectedTo = DateTime.now();
    // Domyślnie cały zakres godzin
    TimeOfDay timeFrom = const TimeOfDay(hour: 0, minute: 0);
    TimeOfDay timeTo = const TimeOfDay(hour: 23, minute: 59);
    bool useTimeFilter = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Licznik podglądu
          int _countMatching() {
            return svc.history.where((e) {
              final date = DateTime.tryParse(e['date'] ?? '');
              if (date == null) return false;
              if (date.isBefore(selectedFrom) || date.isAfter(selectedTo)) {
                return false;
              }
              if (!useTimeFilter) return true;
              final parts = (e['time'] ?? '').split(':');
              if (parts.length < 2) return true;
              final entryMin =
                  (int.tryParse(parts[0]) ?? 0) * 60 +
                  (int.tryParse(parts[1]) ?? 0);
              final fromMin = timeFrom.hour * 60 + timeFrom.minute;
              final toMin = timeTo.hour * 60 + timeTo.minute;
              return entryMin >= fromMin && entryMin <= toMin;
            }).length;
          }

          return AlertDialog(
            backgroundColor: const Color(0xFF202124),
            title: const Text(
              "Usuń zakres",
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // INFO o najstarszej dacie
                  Text(
                    "Najstarsza historia: ${oldest.toString().substring(0, 10)}",
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "DATY",
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // OD DATA
                  Row(
                    children: [
                      const SizedBox(
                        width: 36,
                        child: Text(
                          "Od:",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedFrom,
                              firstDate: oldest,
                              lastDate: DateTime.now(),
                              builder: (c, child) =>
                                  Theme(data: ThemeData.dark(), child: child!),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedFrom = picked);
                            }
                          },
                          child: _dateBox(
                            selectedFrom.toString().substring(0, 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // DO DATA
                  Row(
                    children: [
                      const SizedBox(
                        width: 36,
                        child: Text(
                          "Do:",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedTo,
                              firstDate: oldest,
                              lastDate: DateTime.now(),
                              builder: (c, child) =>
                                  Theme(data: ThemeData.dark(), child: child!),
                            );
                            if (picked != null) {
                              setDialogState(() => selectedTo = picked);
                            }
                          },
                          child: _dateBox(
                            selectedTo.toString().substring(0, 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // PRZEŁĄCZNIK GODZIN
                  Row(
                    children: [
                      const Text(
                        "Filtruj też po godzinie",
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                      const Spacer(),
                      Switch(
                        value: useTimeFilter,
                        onChanged: (v) =>
                            setDialogState(() => useTimeFilter = v),
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                  // GODZINY — widoczne tylko gdy przełącznik ON
                  if (useTimeFilter) ...[
                    const Text(
                      "GODZINY",
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 11,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 36,
                          child: Text(
                            "Od:",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: timeFrom,
                                builder: (c, child) => Theme(
                                  data: ThemeData.dark(),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setDialogState(() => timeFrom = picked);
                              }
                            },
                            child: _dateBox(
                              "${timeFrom.hour.toString().padLeft(2, '0')}:${timeFrom.minute.toString().padLeft(2, '0')}",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(
                          width: 36,
                          child: Text(
                            "Do:",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: timeTo,
                                builder: (c, child) => Theme(
                                  data: ThemeData.dark(),
                                  child: child!,
                                ),
                              );
                              if (picked != null) {
                                setDialogState(() => timeTo = picked);
                              }
                            },
                            child: _dateBox(
                              "${timeTo.hour.toString().padLeft(2, '0')}:${timeTo.minute.toString().padLeft(2, '0')}",
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  // PODGLĄD
                  Text(
                    "Zostanie usuniętych wpisów: ${_countMatching()}",
                    style: TextStyle(
                      color: _countMatching() > 0 ? Colors.orange : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  if (selectedFrom.isAfter(selectedTo)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Data 'Od' nie może być późniejsza niż 'Do'",
                        ),
                      ),
                    );
                    return;
                  }
                  if (useTimeFilter) {
                    final fromMin = timeFrom.hour * 60 + timeFrom.minute;
                    final toMin = timeTo.hour * 60 + timeTo.minute;
                    if (fromMin >= toMin) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Godzina 'Od' musi być wcześniejsza niż 'Do'",
                          ),
                        ),
                      );
                      return;
                    }
                  }
                  await svc.clearHistoryInRange(
                    selectedFrom,
                    selectedTo,
                    fromTime: useTimeFilter ? timeFrom : null,
                    toTime: useTimeFilter ? timeTo : null,
                  );
                  _rebuildGrouped(svc, grouped, days);
                  setModalState(() {});
                  if (context.mounted) Navigator.pop(context);
                },

                child: const Text(
                  "USUŃ",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // Helper — wspólny wygląd pola daty/godziny
  Widget _dateBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF303134),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }

  Color get _surfaceColor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 84, 19, 120)
      : const Color(0xFF303134);

  void _rebuildGrouped(
    BrowserService svc,
    Map<String, List<Map<String, String>>> grouped,
    List<String> days,
  ) {
    grouped.clear();
    days.clear();
    for (final e in svc.history) {
      final d = e['date'] ?? 'Nieznana data';
      grouped.putIfAbsent(d, () => []).add(e);
    }
    days.addAll(grouped.keys);
  }

  Color get _bgColor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 74, 31, 127)
      : const Color(0xFF202124);
  // ── Budowa UI ────────────────────────────────

  Color get _bordercolor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 182, 81, 199).withOpacity(0.5)
      : const Color.fromARGB(255, 255, 255, 255);
  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BrowserService>();

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
              ? const Color.fromARGB(
                  255,
                  116,
                  31,
                  162,
                ) // ciemny fiolet incognito
              : Colors.black,
          body: Column(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    // PASEK KART
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: svc.tabs.length,
                              itemBuilder: (context, index) => GestureDetector(
                                onTap: () {
                                  svc.switchTab(index);
                                  urlController.text = svc.tabs[index].url;
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),

                                  decoration: BoxDecoration(
                                    color: index == svc.currentTabIndex
                                        ? _surfaceColor // aktywna — jaśniejszy fiolet/szary
                                        : _bgColor.withOpacity(
                                            0.6,
                                          ), // nieaktywna — ciemniejszy ale widoczny
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(10),
                                    ),
                                    border: index == svc.currentTabIndex
                                        ? Border.all(
                                            color: _bordercolor,
                                            width: 1,
                                          )
                                        : null, // obramowanie tylko aktywnej
                                  ),
                                  child: Center(
                                    child: Text(
                                      svc.tabs[index].title,
                                      style: TextStyle(
                                        color: index == svc.currentTabIndex
                                            ? Colors
                                                  .white // aktywna — biały tekst
                                            : Colors
                                                  .grey, // nieaktywna — szary tekst
                                        fontSize: 11,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ),
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
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  prefixIcon: Icon(
                                    Icons.search,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                ),
                                onTap: () {
                                  if (urlController.text.isNotEmpty) {
                                    urlController.selection = TextSelection(
                                      baseOffset: 0,
                                      extentOffset: urlController.text.length,
                                    );
                                  }
                                },
                                onSubmitted: (v) {
                                  final targetUrl = svc.buildTargetUrl(v);
                                  svc.currentTab.controller?.loadUrl(
                                    urlRequest: URLRequest(url: targetUrl),
                                  );
                                },
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _showTabsManager(svc),
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
                              Icons.more_vert,
                              color: Colors.grey,
                            ),
                            onPressed: () => _showSettingsMenu(svc),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // WEBVIEW
              Expanded(
                child: IndexedStack(
                  index: svc.currentTabIndex,
                  children: svc.tabs
                      .map(
                        (tab) => _WebViewTab(
                          key: ValueKey(
                            tab,
                          ), // ← WAŻNE: stały klucz per obiekt tab
                          tab: tab,
                          svc: svc,
                          urlController: urlController,
                          onPasswordRequired:
                              _showPasswordDialog, //TODO odkomentować
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  final BrowserService svc;
  const _PasswordDialog({required this.svc});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _newPController = TextEditingController();
  final _oldPController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;

  @override
  void dispose() {
    _newPController.dispose();
    _oldPController.dispose();
    super.dispose();
  }

  Color get _bgColor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 116, 31, 162) // ciemny fiolet incognito
      : const Color(0xFF202124);
  @override
  Widget build(BuildContext context) {
    final hasP =
        widget.svc.savedPassword != null &&
        widget.svc.savedPassword!.isNotEmpty;

    return AlertDialog(
      backgroundColor: _bgColor,
      title: Text(
        hasP ? "Zmień hasło" : "Ustaw hasło",
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasP)
            TextField(
              controller: _oldPController,
              obscureText: _obscureOld,
              style: const TextStyle(color: Colors.white),
              contextMenuBuilder: (context, editableTextState) {
                return AdaptiveTextSelectionToolbar.buttonItems(
                  anchors: editableTextState.contextMenuAnchors,
                  buttonItems: editableTextState.contextMenuButtonItems,
                );
              },
              decoration: InputDecoration(
                hintText: "Stare hasło",
                hintStyle: const TextStyle(color: Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOld ? Icons.visibility : Icons.visibility_off,
                    color: Colors.blue,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureOld = !_obscureOld),
                ),
              ),
            ),
          const SizedBox(height: 16),
          // POLE: NOWE HASŁO
          TextField(
            controller: _newPController,
            obscureText: _obscureNew,
            style: const TextStyle(color: Colors.white),
            contextMenuBuilder: (context, editableTextState) {
              return AdaptiveTextSelectionToolbar.buttonItems(
                anchors: editableTextState.contextMenuAnchors,
                buttonItems: editableTextState.contextMenuButtonItems,
              );
            },
            decoration: InputDecoration(
              hintText: "Nowe hasło",
              hintStyle: const TextStyle(color: Colors.grey),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility : Icons.visibility_off,
                  color: Colors.blue,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANULUJ"),
        ),
        TextButton(
          onPressed: () async {
            final oldP = _oldPController.text;
            final newP = _newPController.text;
            print(
              "hasP: $hasP, oldP: $oldP, savedpassword: ${widget.svc.savedPassword}",
            );
            if (hasP && oldP != widget.svc.savedPassword) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Błędne stare hasło!")),
              );
              return;
            }
            if (newP.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Hasło nie może być puste!")),
              );
              return;
            }

            await widget.svc.savePassword(newP);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text("ZAPISZ"),
        ),
      ],
    );
  }
}

// Nowa klasa — dodaj na dole browser_screen.dart
class _WebViewTab extends StatefulWidget {
  final TabModel tab;
  final BrowserService svc;
  final TextEditingController urlController;
  final void Function(BrowserService, WebUri, InAppWebViewController?)
  onPasswordRequired;

  const _WebViewTab({
    required Key key,
    required this.tab,
    required this.svc,
    required this.urlController,
    required this.onPasswordRequired,
  }) : super(key: key);

  @override
  State<_WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<_WebViewTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  double _progress = 0;
  // Dodaj zmienną stanu
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
          key: ValueKey(_webViewKey), // ← zamiast braku klucza
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
            disableDefaultErrorPage: false, // nie blokuj stron błędów
            supportMultipleWindows: true, // wsparcie dla okien popup
            allowFileAccess: true, // dostęp do plików
            useWideViewPort: true,
            loadsImagesAutomatically: true,
            blockNetworkLoads: false, // to j
            // Wymuś akceptowanie wszystkich cookies
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
            // Pobierz URL z akcji window.open
            final url = createWindowAction.request.url;
            if (url != null) {
              // Załaduj ten URL w obecnej karcie zamiast otwierać nowe okno
              controller.loadUrl(urlRequest: URLRequest(url: url));
            }
            return true;
          },
          onCloseWindow: (controller) async {
            if (widget.svc.tabs.length > 1) {
              final index = widget.svc.tabs.indexOf(tab);
              widget.svc.closeTab(index);
            }
            return; // lub usuń return
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
            await Future.delayed(Duration(milliseconds: 500));
            if (u != null) {
              await svc.addToHistory(await c.getTitle(), u.toString());
            } // ⏳ opóźnienie
          },

          onLoadStart: (controller, url) async {
            if (url == null) return;
            final urlString = url.toString();

            // Sprawdź czy to plik lokalny i czy to PDF
            if (urlString.startsWith("file://") &&
                urlString.toLowerCase().endsWith(".pdf")) {
              // Zatrzymaj ładowanie w WebView, bo ono nie obsłuży PDF lokalnie
              await controller.stopLoading();

              // Wyciągnij czystą ścieżkę do pliku
              final filePath = url.toFilePath();
              final fileName = url.pathSegments.isNotEmpty
                  ? url.pathSegments.last
                  : "Dokument PDF";

              if (mounted) {
                // Przejdź do Twojego ekranu PDF
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        PdfScreen(path: filePath, title: fileName),
                  ),
                );
              }
              return;
            }
          },

          onDownloadStartRequest: (controller, downloadRequest) async {
            final urlString = downloadRequest.url.toString();
            print("onDownloadStart: $urlString");

            if (urlString.startsWith("content://") ||
                urlString.toLowerCase().endsWith(".pdf")) {
              // 1. Wyciągnij nazwę pliku
              String fileName =
                  "dokument_${DateTime.now().millisecondsSinceEpoch}.pdf";
              if (downloadRequest.suggestedFilename != null) {
                fileName = downloadRequest.suggestedFilename!;
              }

              try {
                // Dla content:// musimy użyć zewnętrznego sposobu zapisu.
                // Najszybsza poprawka bez nowych bibliotek:

                final directory = await getTemporaryDirectory();
                final savePath = "${directory.path}/$fileName";

                // Jeśli to jest content://, musimy poprosić system o dane.
                // UWAGA: InAppWebView automatycznie nie pobiera content:// przez http.get

                // Proponowane rozwiązanie: użyj NavigationAction zamiast DownloadStart dla takich linków
                // lub użyj paczki 'flutter_cache_manager' / 'dio'.

                // Jeśli chcesz tylko otworzyć ten PDF w swoim PdfScreen:
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfScreen(
                      path: urlString, // Przekaż URI
                      title: fileName,
                    ),
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

            // Sprawdzamy czy to plik lokalny kończący się na .pdf
            if (urlString.startsWith('file://') &&
                urlString.toLowerCase().endsWith('.pdf')) {
              final localPath = url
                  .toFilePath(); // Konwertuje file://... na zwykłą ścieżkę /...

              if (await File(localPath).exists()) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfScreen(
                      path: localPath,
                      title: localPath
                          .split('/')
                          .last, // Nazwa pliku jako tytuł
                    ),
                  ),
                );
                return NavigationActionPolicy
                    .CANCEL; // Blokujemy ładowanie w samym WebView
              }
            }
            if (urlString.startsWith('file://') &&
                urlString.toLowerCase().endsWith('.pdf')) {
              final localPath = url
                  .toFilePath(); // Konwertuje file://... na zwykłą ścieżkę /...

              if (await File(localPath).exists()) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PdfScreen(
                      path: localPath,
                      title: localPath
                          .split('/')
                          .last, // Nazwa pliku jako tytuł
                    ),
                  ),
                );
                return NavigationActionPolicy
                    .CANCEL; // Blokujemy ładowanie w samym WebView
              }
            }

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

            bool isPdfUrl =
                urlString.toLowerCase().endsWith('.pdf') ||
                urlString.toLowerCase().contains('.pdf?');
            if (!isPdfUrl) {
              final uri = Uri.tryParse(urlString);
              final pathSegment = uri?.pathSegments.lastOrNull ?? '';
              final skipExtensions = {
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
                    // ZAWSZE sprawdzaj magic bytes dla URL-i które mogą zwracać pliki
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
