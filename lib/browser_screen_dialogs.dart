import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart' as url_launcher;
import 'browser_service.dart';
import 'search_engine_picker.dart';
import 'password_dialog.dart';

/// Mixin zawierający wszystkie metody dialogów/menu dla BrowserScreen.
/// Wymaga, aby klasa mieszająca była State<...> z dostępem do context.
mixin BrowserScreenDialogsMixin<T extends StatefulWidget> on State<T> {
  static const _channel = MethodChannel('app/shortcuts');

  // ── Hasło ────────────────────────────────────────────────────────────────

  void showPasswordDialog(
    BrowserService svc,
    WebUri url,
    InAppWebViewController? controller, {
    BlockReason reason = BlockReason.content,
    String? matchedWord,
  }) {
    if (svc.canSkipAuth(url.toString())) {
      controller?.loadUrl(urlRequest: URLRequest(url: url));
      return;
    }
    if (svc.isVerifying) return;
    svc.isVerifying = true;

    // Opis przyczyny blokady
    final (
      String reasonIcon,
      String reasonLabel,
      Color reasonColor,
    ) = switch (reason) {
      BlockReason.content => ("🔞", "Treści dla dorosłych", Colors.orange),
      BlockReason.blacklist => (
        "🚫",
        "Strona na czarnej liście",
        Colors.redAccent,
      ),
      BlockReason.proxy => ("🛡️", "VPN / Proxy", Colors.purple),
      _ => ("🔒", "Strona zablokowana", Colors.grey),
    };

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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Baner z przyczyną blokady
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: reasonColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: reasonColor.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  Text(reasonIcon, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Powód blokady",
                          style: TextStyle(
                            color: reasonColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reasonLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (matchedWord != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: reasonColor.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '"$matchedWord"',
                              style: TextStyle(
                                color: reasonColor,
                                fontSize: 12,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            TextField(
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
          ],
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
                    onPressed: () => Navigator.pop(context),
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

  String _engineName(String url) {
    if (url.isEmpty) return 'Nie wybrano';
    if (url.contains('google.com')) return 'Google';
    if (url.contains('duckduckgo.com')) return 'DuckDuckGo';
    if (url.contains('bing.com')) return 'Bing';
    if (url.contains('brave.com')) return 'Brave Search';
    if (url.contains('startpage.com')) return 'Startpage';
    if (url.contains('ecosia.org')) return 'Ecosia';
    if (url.contains('yahoo.com')) return 'Yahoo';
    return url;
  }

  /// Otwiera drawer ustawień (wysuwa się z prawej strony)
  void showSettingsMenu(BrowserService svc) {
    Scaffold.of(context).openEndDrawer();
  }

  /// Buduje zawartość drawera — wywoływane z browser_screen.dart
  Widget buildSettingsDrawer(BrowserService svc) {
    return Drawer(
      width: 300,
      backgroundColor: const Color(0xFF202124),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Nagłówek
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF3A3A3E))),
              ),
              child: Row(
                children: [
                  const Icon(Icons.settings, color: Colors.blue, size: 22),
                  const SizedBox(width: 10),
                  const Text(
                    'Ustawienia',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (svc.incognitoMode)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.purple),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_off,
                            size: 12,
                            color: Colors.purple,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Incognito',
                            style: TextStyle(
                              color: Colors.purple,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            // Lista opcji
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerTile(
                    icon: Icons.shield,
                    iconColor: svc.adBlockEnabled ? Colors.green : Colors.grey,
                    title: 'AdBlock',
                    subtitle: svc.adBlockEnabled ? 'Włączony' : 'Wyłączony',
                    onTap: () {
                      Navigator.pop(context);
                      showAdBlockMenu(svc);
                    },
                  ),
                  _drawerTile(
                    icon: Icons.history,
                    iconColor: Colors.blue,
                    title: 'Historia',
                    onTap: () {
                      Navigator.pop(context);
                      showHistory(svc);
                    },
                  ),
                  _drawerTile(
                    icon: Icons.block,
                    iconColor: Colors.redAccent,
                    title: 'Blokady',
                    onTap: () {
                      Navigator.pop(context);
                      _showBlockingMenu(svc);
                    },
                  ),
                  _drawerTile(
                    icon: Icons.add_to_home_screen,
                    iconColor: Colors.blue,
                    title: 'Dodaj skrót do ekranu głównego',
                    onTap: () {
                      Navigator.pop(context);
                      addShortcut(svc);
                    },
                  ),
                  const Divider(
                    color: Color(0xFF3A3A3E),
                    indent: 16,
                    endIndent: 16,
                  ),
                  _drawerTile(
                    icon: Icons.manage_search,
                    iconColor: Colors.blue,
                    title: 'Wyszukiwarka',
                    subtitle: _engineName(svc.searchEngineUrl),
                    onTap: () {
                      Navigator.pop(context);
                      showDialog(
                        context: context,
                        builder: (_) =>
                            const SearchEnginePicker(onboarding: false),
                      );
                    },
                  ),
                  _drawerTile(
                    icon: Icons.home_outlined,
                    iconColor: Colors.blue,
                    title: 'Strona startowa',
                    subtitle: svc.homePageUrl,
                    onTap: () {
                      Navigator.pop(context);
                      _showHomePageDialog(svc);
                    },
                  ),
                  const Divider(
                    color: Color(0xFF3A3A3E),
                    indent: 16,
                    endIndent: 16,
                  ),
                  _drawerTile(
                    icon: Icons.delete_outline,
                    iconColor: Colors.redAccent,
                    title: 'Wyczyść dane przeglądania',
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
                            'Usuniesz ciasteczka, cache i dane stron. Zostaniesz wylogowany ze wszystkich stron.',
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
                  _drawerTile(
                    icon: Icons.info_outline,
                    iconColor: Colors.grey,
                    title: 'O aplikacji',
                    onTap: () {
                      Navigator.pop(context);
                      _showAboutDialog(svc);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(color: Colors.grey, fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right,
        color: Color(0xFF555555),
        size: 18,
      ),
      onTap: onTap,
    );
  }

  void _showHomePageDialog(BrowserService svc) {
    const engines = [
      ('Google', 'https://www.google.com', Icons.search),
      ('DuckDuckGo', 'https://www.duckduckgo.com', Icons.privacy_tip_outlined),
      ('Bing', 'https://www.bing.com', Icons.search),
      ('Brave Search', 'https://search.brave.com', Icons.shield_outlined),
      ('Startpage', 'https://www.startpage.com', Icons.lock_outline),
      ('Ecosia', 'https://www.ecosia.org', Icons.park_outlined),
    ];

    final customC = TextEditingController(
      text: engines.any((e) => e.$2 == svc.homePageUrl) ? '' : svc.homePageUrl,
    );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            'Strona startowa',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Kafelki wyszukiwarek
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: engines.map((e) {
                    final isSelected = svc.homePageUrl == e.$2;
                    return GestureDetector(
                      onTap: () async {
                        await svc.setHomePage(e.$2);
                        customC.clear();
                        setD(() {});
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.withOpacity(0.2)
                              : const Color(0xFF2A2A2E),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue
                                : Colors.grey.withOpacity(0.3),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              e.$3,
                              size: 16,
                              color: isSelected ? Colors.blue : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              e.$1,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.white70,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.blue,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.grey),
                const SizedBox(height: 8),
                // Własny URL
                TextField(
                  controller: customC,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Własny adres (np. https://moja-strona.pl)',
                    hintStyle: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                    prefixIcon: const Icon(
                      Icons.link,
                      color: Colors.grey,
                      size: 18,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        Icons.check,
                        color: Colors.blue,
                        size: 18,
                      ),
                      tooltip: 'Ustaw',
                      onPressed: () async {
                        final v = customC.text.trim();
                        if (v.isEmpty) return;
                        final url = v.startsWith('http') ? v : 'https://$v';
                        await svc.setHomePage(url);
                        setD(() {});
                      },
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  onSubmitted: (v) async {
                    if (v.trim().isEmpty) return;
                    final url = v.trim().startsWith('http')
                        ? v.trim()
                        : 'https://${v.trim()}';
                    await svc.setHomePage(url);
                    setD(() {});
                  },
                ),
                const SizedBox(height: 8),
                // Aktualna wartość
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 13,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Aktualnie: ${svc.homePageUrl}',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
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
          ListTile(
            leading: const Icon(
              Icons.eighteen_up_rating_outlined,
              color: Colors.orange,
            ),
            title: const Text(
              "Słowa filtra (tłumaczenia)",
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              "Przeglądaj i usuwaj tłumaczenia słów kluczowych",
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
            onTap: () {
              Navigator.pop(context);
              showPornKeywordsViewer(svc);
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
    bool authenticated = svc.savedPassword == null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDS) {
          final groups = svc.blackListGroups;
          final groupNames = groups.keys.toList();

          return AlertDialog(
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
                    Icons.add_box_outlined,
                    color: Colors.blue,
                    size: 24,
                  ),
                  tooltip: "Nowa grupa",
                  onPressed: () async {
                    final nameC = TextEditingController();
                    final name = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF202124),
                        title: const Text(
                          "Nowa grupa",
                          style: TextStyle(color: Colors.white),
                        ),
                        content: TextField(
                          controller: nameC,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Nazwa grupy",
                            hintStyle: TextStyle(color: Colors.grey),
                          ),
                          onSubmitted: (v) => Navigator.pop(ctx, v),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text(
                              "ANULUJ",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, nameC.text),
                            child: const Text(
                              "DODAJ",
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (name != null && name.trim().isNotEmpty) {
                      await svc.addGroup(name.trim());
                      setDS(() {});
                    }
                  },
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.25)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Wpisz słowa kluczowe lub adresy stron, których nie chcesz odwiedzać. Przeglądarka zablokuje każdy URL zawierający te wyrazy.",
                            style: TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Grupy
                  Flexible(
                    child: groupNames.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              "Brak grup",
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: groupNames.length,
                            itemBuilder: (context, gi) {
                              final groupName = groupNames[gi];
                              final entries = groups[groupName] ?? [];
                              final addC = TextEditingController();
                              return Card(
                                color: const Color(0xFF2A2A2E),
                                margin: const EdgeInsets.only(bottom: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ExpansionTile(
                                  initiallyExpanded: true,
                                  collapsedIconColor: Colors.grey,
                                  iconColor: Colors.blue,
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          groupName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        "${entries.length}",
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      // Usuń grupę (tylko niestandardowe)
                                      if (groupName != 'Strony' &&
                                          groupName != 'Słowa kluczowe')
                                        GestureDetector(
                                          onTap: () async {
                                            if (!authenticated) {
                                              final granted =
                                                  await _askForPasswordOnly(
                                                    svc,
                                                  );
                                              if (granted != true) return;
                                              authenticated = true;
                                            }
                                            await svc.removeGroup(groupName);
                                            setDS(() {});
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            child: Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 18,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  children: [
                                    // Pole dodawania
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        0,
                                        12,
                                        8,
                                      ),
                                      child: TextField(
                                        controller: addC,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                        decoration: InputDecoration(
                                          hintText:
                                              groupName == 'Słowa kluczowe'
                                              ? "Dodaj słowo (np. hazard)"
                                              : "Dodaj adres (np. facebook.com)",
                                          hintStyle: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                          isDense: true,
                                          suffixIcon: IconButton(
                                            icon: const Icon(
                                              Icons.add,
                                              color: Colors.blue,
                                              size: 18,
                                            ),
                                            onPressed: () async {
                                              if (addC.text.isEmpty) return;
                                              await svc.addToBlackListGroup(
                                                groupName,
                                                addC.text,
                                              );
                                              addC.clear();
                                              setDS(() {});
                                            },
                                          ),
                                        ),
                                        onSubmitted: (v) async {
                                          if (v.isEmpty) return;
                                          await svc.addToBlackListGroup(
                                            groupName,
                                            v,
                                          );
                                          addC.clear();
                                          setDS(() {});
                                        },
                                      ),
                                    ),
                                    // Wpisy
                                    if (entries.isEmpty)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          0,
                                          16,
                                          12,
                                        ),
                                        child: Text(
                                          "Brak wpisów",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 12,
                                          ),
                                        ),
                                      )
                                    else
                                      ...entries.map((entry) {
                                        final translations =
                                            svc.wordTranslations[entry];
                                        final hasTranslations =
                                            translations != null &&
                                            translations.length > 1;
                                        final progress =
                                            svc.translationProgress[entry];
                                        final isLoading = progress != null;
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ListTile(
                                              dense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 0,
                                                  ),
                                              leading: Icon(
                                                groupName == 'Słowa kluczowe'
                                                    ? Icons.text_fields
                                                    : Icons.language,
                                                color: Colors.grey,
                                                size: 16,
                                              ),
                                              title: Text(
                                                entry,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              subtitle: isLoading
                                                  ? Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const SizedBox(
                                                          height: 3,
                                                        ),
                                                        Row(
                                                          children: [
                                                            Expanded(
                                                              child: ClipRRect(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      4,
                                                                    ),
                                                                child: LinearProgressIndicator(
                                                                  value:
                                                                      progress,
                                                                  minHeight: 4,
                                                                  backgroundColor:
                                                                      Colors
                                                                          .grey
                                                                          .shade800,
                                                                  color: Colors
                                                                      .blue,
                                                                ),
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 6,
                                                            ),
                                                            Text(
                                                              '${(progress * 100).toInt()}%',
                                                              style:
                                                                  const TextStyle(
                                                                    color: Colors
                                                                        .blue,
                                                                    fontSize:
                                                                        10,
                                                                  ),
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    )
                                                  : hasTranslations
                                                  ? Text(
                                                      '🌐 ${translations.length - 1} tłumaczeń',
                                                      style: const TextStyle(
                                                        color: Colors.blue,
                                                        fontSize: 10,
                                                      ),
                                                    )
                                                  : null,
                                              trailing: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Ikona tłumaczeń — zawsze widoczna, ale za hasłem
                                                  IconButton(
                                                    icon: Icon(
                                                      Icons.translate,
                                                      color: hasTranslations
                                                          ? Colors.blue
                                                          : Colors.grey
                                                                .withOpacity(
                                                                  0.4,
                                                                ),
                                                      size: 16,
                                                    ),
                                                    tooltip:
                                                        'Tłumaczenia (wymaga hasła)',
                                                    onPressed: () async {
                                                      if (svc.savedPassword !=
                                                          null) {
                                                        final granted =
                                                            await _askForPasswordOnly(
                                                              svc,
                                                            );
                                                        if (granted != true)
                                                          return;
                                                      }
                                                      if (!context.mounted)
                                                        return;
                                                      _showTranslationsDialog(
                                                        context: context,
                                                        svc: svc,
                                                        word: entry,
                                                        translations:
                                                            translations ?? [],
                                                        onChanged: () =>
                                                            setDS(() {}),
                                                      );
                                                    },
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                      Icons.close,
                                                      color: Colors.redAccent,
                                                      size: 18,
                                                    ),
                                                    onPressed: () async {
                                                      if (!authenticated) {
                                                        final granted =
                                                            await _askForPasswordOnly(
                                                              svc,
                                                            );
                                                        if (granted != true)
                                                          return;
                                                        authenticated = true;
                                                      }
                                                      await svc
                                                          .removeFromBlackListGroup(
                                                            groupName,
                                                            entry,
                                                          );
                                                      setDS(() {});
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                  ],
                                ),
                              );
                            },
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
          );
        },
      ),
    );
  }

  // ── Dialog tłumaczeń (za hasłem, z usuwaniem) ──────────────────────────────

  static String _thresholdLabel(int t) {
    switch (t) {
      case 0:
        return 'Dokładne (0) — tylko identyczne';
      case 1:
        return 'Luźne (1) — 1 literka różnicy';
      case 2:
        return 'Średnie (2) — 2 literki różnicy';
      case 3:
        return 'Bardzo luźne (3) — 3 literki różnicy';
      default:
        return 'Niestandardowe ($t)';
    }
  }

  void _showTranslationsDialog({
    required BuildContext context,
    required BrowserService svc,
    required String word,
    required List<String> translations,
    required VoidCallback onChanged,
  }) {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setTD) {
          final current = List<String>.from(
            svc.wordTranslations[word] ?? translations,
          );
          final wordThresh = svc.wordThresholds[word] ?? -1; // -1 = auto
          return AlertDialog(
            backgroundColor: const Color(0xFF202124),
            title: Row(
              children: [
                const Icon(Icons.translate, color: Colors.blue, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tłumaczenia: "$word"',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Próg dla słowa bazowego ──
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune,
                                color: Colors.blue,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Próg dopasowania słowa bazowego',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            wordThresh < 0
                                ? 'Auto (domyślny dla długości słowa)'
                                : _thresholdLabel(wordThresh),
                            style: TextStyle(
                              color: wordThresh < 0 ? Colors.grey : Colors.blue,
                              fontSize: 11,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Auto',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: (wordThresh < 0 ? -1 : wordThresh)
                                      .toDouble(),
                                  min: -1,
                                  max: 3,
                                  divisions: 4,
                                  activeColor: Colors.blue,
                                  inactiveColor: Colors.grey.shade800,
                                  onChanged: (v) async {
                                    await svc.setWordThreshold(word, v.round());
                                    setTD(() {});
                                    onChanged();
                                  },
                                ),
                              ),
                              const Text(
                                '3',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // ── Tłumaczenia z chipakami i suwakami ──
                    if (current.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Brak tłumaczeń.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ...current.map((t) {
                        final tThresh = svc.wordThresholds[t] ?? -1;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.redAccent,
                                      size: 16,
                                    ),
                                    onPressed: () async {
                                      final updated = List<String>.from(
                                        svc.wordTranslations[word] ?? [],
                                      )..remove(t);
                                      svc.wordTranslations[word] = updated;
                                      final prefs = await svc.getPrefsPublic();
                                      await prefs.setString(
                                        'word_translations',
                                        svc.wordTranslationsJson,
                                      );
                                      setTD(() {});
                                      onChanged();
                                    },
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Text(
                                    'Auto',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 9,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: (tThresh < 0 ? -1 : tThresh)
                                          .toDouble(),
                                      min: -1,
                                      max: 3,
                                      divisions: 4,
                                      activeColor: Colors.blueGrey,
                                      inactiveColor: Colors.grey.shade800,
                                      onChanged: (v) async {
                                        await svc.setWordThreshold(
                                          t,
                                          v.round(),
                                        );
                                        setTD(() {});
                                      },
                                    ),
                                  ),
                                  const Text(
                                    '3',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                tThresh < 0 ? 'Auto' : _thresholdLabel(tThresh),
                                style: TextStyle(
                                  color: tThresh < 0
                                      ? Colors.grey
                                      : Colors.blueGrey,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ZAMKNIJ',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dialog tłumaczeń dla pornKeywords — z progami i usuwaniem
  void _showPornKeywordTranslationsDialog({
    required BuildContext context,
    required BrowserService svc,
    required String word,
  }) {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setTD) {
          final current = List<String>.from(svc.wordTranslations[word] ?? []);
          final wordThresh = svc.wordThresholds[word] ?? -1;
          return AlertDialog(
            backgroundColor: const Color(0xFF202124),
            title: Row(
              children: [
                const Icon(Icons.translate, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '"$word"',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Próg dla słowa bazowego
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2E),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.tune,
                                color: Colors.orange,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'Próg dopasowania słowa bazowego',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            wordThresh < 0
                                ? 'Auto'
                                : _thresholdLabel(wordThresh),
                            style: TextStyle(
                              color: wordThresh < 0
                                  ? Colors.grey
                                  : Colors.orange,
                              fontSize: 11,
                            ),
                          ),
                          Row(
                            children: [
                              const Text(
                                'Auto',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: wordThresh.toDouble().clamp(-1, 3),
                                  min: -1,
                                  max: 3,
                                  divisions: 4,
                                  activeColor: Colors.orange,
                                  inactiveColor: Colors.grey.shade800,
                                  onChanged: (v) async {
                                    await svc.setWordThreshold(word, v.round());
                                    setTD(() {});
                                  },
                                ),
                              ),
                              const Text(
                                '3',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (current.isEmpty)
                      const Text(
                        'Brak tłumaczeń — słowo blokowane tylko w wersji oryginalnej.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    else
                      ...current.map((t) {
                        final tThresh = svc.wordThresholds[t] ?? -1;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A2E),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.2),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      t,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.redAccent,
                                      size: 16,
                                    ),
                                    onPressed: () async {
                                      final updated = List<String>.from(
                                        svc.wordTranslations[word] ?? [],
                                      )..remove(t);
                                      svc.wordTranslations[word] = updated;
                                      final prefs = await svc.getPrefsPublic();
                                      await prefs.setString(
                                        'word_translations',
                                        svc.wordTranslationsJson,
                                      );
                                      setTD(() {});
                                    },
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Text(
                                    'Auto',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 9,
                                    ),
                                  ),
                                  Expanded(
                                    child: Slider(
                                      value: tThresh.toDouble().clamp(-1, 3),
                                      min: -1,
                                      max: 3,
                                      divisions: 4,
                                      activeColor: Colors.orange.shade300,
                                      inactiveColor: Colors.grey.shade800,
                                      onChanged: (v) async {
                                        await svc.setWordThreshold(
                                          t,
                                          v.round(),
                                        );
                                        setTD(() {});
                                      },
                                    ),
                                  ),
                                  const Text(
                                    '3',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                tThresh < 0 ? 'Auto' : _thresholdLabel(tThresh),
                                style: TextStyle(
                                  color: tThresh < 0
                                      ? Colors.grey
                                      : Colors.orange,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'ZAMKNIJ',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Pokazuje dialog z listą pornKeywords i ich tłumaczeniami — wymaga hasła
  void showPornKeywordsViewer(BrowserService svc) async {
    if (svc.savedPassword != null) {
      final granted = await _askForPasswordOnly(svc);
      if (granted != true) return;
    }
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setPKD) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Row(
            children: [
              Icon(
                Icons.eighteen_up_rating_outlined,
                color: Colors.orange,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Słowa kluczowe filtra',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: svc.pornKeywords.length,
              itemBuilder: (context, index) {
                final word = svc.pornKeywords[index];
                final translations = svc.wordTranslations[word];
                final hasT = translations != null && translations.isNotEmpty;
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(
                    Icons.block,
                    color: Colors.orange,
                    size: 16,
                  ),
                  title: Text(
                    word,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  subtitle: hasT
                      ? Text(
                          '${translations.length} tłumaczeń',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    icon: Icon(
                      Icons.translate,
                      color: hasT
                          ? Colors.orange
                          : Colors.grey.withOpacity(0.4),
                      size: 16,
                    ),
                    tooltip: 'Pokaż / edytuj tłumaczenia',
                    onPressed: () {
                      _showPornKeywordTranslationsDialog(
                        context: context,
                        svc: svc,
                        word: word,
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ZAMKNIJ',
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
