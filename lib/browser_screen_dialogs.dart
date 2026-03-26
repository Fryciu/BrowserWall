import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'browser_service.dart';
import 'password_dialog.dart';

/// Mixin zawierający wszystkie metody dialogów/menu dla BrowserScreen.
/// Wymaga, aby klasa mieszająca była State<...> z dostępem do context.
mixin BrowserScreenDialogsMixin<T extends StatefulWidget> on State<T> {
  static const _channel = MethodChannel('app/shortcuts');

  // ── Hasło ────────────────────────────────────────────────────────────────

  void showPasswordDialog(
    BrowserService svc,
    WebUri url,
    InAppWebViewController? controller,
  ) {
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

  // ── Skrót do ekranu głównego ──────────────────────────────────────────────

  Future<void> addShortcut(BrowserService svc) async {
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

  // ── AdBlock ──────────────────────────────────────────────────────────────

  void showAdBlockMenu(BrowserService svc) {
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
                      showSettingsMenu(svc);
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

  // ── Menu ustawień ────────────────────────────────────────────────────────

  void showSettingsMenu(BrowserService svc) {
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
              showAdBlockMenu(svc);
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
              showHistory(svc);
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
              addShortcut(svc);
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
              _showAboutDialog(svc);
            },
          ),
          const SizedBox(height: 5),
        ],
      ),
    );
  }

  void _showAboutDialog(BrowserService svc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text('O aplikacji', style: TextStyle(color: Colors.white)),
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
                      mode: url_launcher.LaunchMode.externalApplication,
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
                      mode: url_launcher.LaunchMode.externalApplication,
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
            child: const Text('ZAMKNIJ', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // ── Blokady ──────────────────────────────────────────────────────────────

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
                    showSettingsMenu(svc);
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

  // ── Zarządzanie kartami ──────────────────────────────────────────────────

  void showTabsManager(
    BrowserService svc,
    TextEditingController urlController,
  ) {
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
              // PRZYCISK NOWEJ KARTY
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

  // ── Hasło (ustawienia) ────────────────────────────────────────────────────

  void _setupPassword(BrowserService svc) {
    showDialog(
      context: context,
      builder: (context) => PasswordDialog(svc: svc),
    );
  }

  // ── Czarna lista ─────────────────────────────────────────────────────────

  void _showListEditor(BrowserService svc) {
    final addC = TextEditingController();
    bool authenticated = svc.savedPassword == null;

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

  // ── Historia ─────────────────────────────────────────────────────────────

  void showHistory(BrowserService svc) {
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
                    const SizedBox(width: 12),
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

  String _formatDate(String dateStr) {
    final today = DateTime.now().toString().substring(0, 10);
    final yesterday = DateTime.now()
        .subtract(const Duration(days: 1))
        .toString()
        .substring(0, 10);
    if (dateStr == today) return "Dzisiaj";
    if (dateStr == yesterday) return "Wczoraj";
    return dateStr;
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
              final daysBack = int.tryParse(controller.text);
              if (daysBack == null || daysBack <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Podaj poprawną liczbę dni")),
                );
                return;
              }
              await svc.clearHistoryFromDaysBack(daysBack);
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
    TimeOfDay timeFrom = const TimeOfDay(hour: 0, minute: 0);
    TimeOfDay timeTo = const TimeOfDay(hour: 23, minute: 59);
    bool useTimeFilter = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          int countMatching() {
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
                        activeThumbColor: Colors.blue,
                      ),
                    ],
                  ),
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
                  Text(
                    "Zostanie usuniętych wpisów: ${countMatching()}",
                    style: TextStyle(
                      color: countMatching() > 0 ? Colors.orange : Colors.grey,
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
}
