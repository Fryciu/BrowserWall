import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'browser_service.dart';

// ── Wbudowane wyszukiwarki ───────────────────────────────────────────────────

final _builtinEngines = [
  (
    name: 'Google',
    url: 'https://www.google.com',
    icon: "assets/icon.png",
    color: Color(0xFF4285F4),
    desc: 'Najpopularniejsza wyszukiwarka',
  ),
  (
    name: 'DuckDuckGo',
    url: 'https://www.duckduckgo.com',
    icon: "assets/icon.png",
    color: Color(0xFFDE5833),
    desc: 'Prywatność przede wszystkim',
  ),
  (
    name: 'Bing',
    url: 'https://www.bing.com',
    icon: "assets/icon.png",
    color: Color(0xFF008373),
    desc: 'Wyszukiwarka Microsoft',
  ),
  (
    name: 'Brave Search',
    url: 'https://search.brave.com',
    icon: "assets/icon.png",
    color: Color(0xFFFF6000),
    desc: 'Niezależna, bez śledzenia',
  ),
  (
    name: 'Startpage',
    url: 'https://www.startpage.com',
    icon: "assets/icon.png",
    color: Color(0xFF4CAF50),
    desc: 'Prywatne wyniki Google',
  ),
  (
    name: 'Ecosia',
    url: 'https://www.ecosia.org',
    icon: "assets/icon.png",
    color: Color(0xFF4CAF50),
    desc: 'Sadzisz drzewa wyszukując',
  ),
  (
    name: 'Yahoo',
    url: 'https://search.yahoo.com',
    icon: "assets/icon.png",
    color: Color(0xFF6001D2),
    desc: 'Klasyczna wyszukiwarka',
  ),
];

// ── Widget ───────────────────────────────────────────────────────────────────

class SearchEnginePicker extends StatefulWidget {
  final bool onboarding;
  const SearchEnginePicker({super.key, this.onboarding = true});

  @override
  State<SearchEnginePicker> createState() => _SearchEnginePickerState();
}

class _SearchEnginePickerState extends State<SearchEnginePicker> {
  String? _selected;
  late List<String> _hiddenBuiltins;

  @override
  void initState() {
    super.initState();
    final svc = context.read<BrowserService>();
    if (svc.searchEngineUrl.isNotEmpty) {
      _selected = svc.searchEngineUrl;
    }
    _hiddenBuiltins = List<String>.from(svc.hiddenBuiltinEngines);
  }

  int _totalVisible(BrowserService svc) {
    final visibleBuiltins = _builtinEngines
        .where((e) => !_hiddenBuiltins.contains(e.url))
        .length;
    return visibleBuiltins + svc.customSearchEngines.length;
  }

  // ── Weryfikacja hasła ────────────────────────────────────────────────────

  Future<bool> _verifyPassword(BrowserService svc) async {
    if (svc.savedPassword == null || svc.savedPassword!.isEmpty) return true;
    String entered = '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          'Wymagane hasło',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onChanged: (v) => entered = v,
          decoration: const InputDecoration(
            hintText: 'Wpisz hasło',
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
            onPressed: () => Navigator.pop(ctx, svc.verifyPassword(entered)),
            child: const Text(
              'POTWIERDŹ',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (ok != true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Błędne hasło!')));
    }
    return ok == true;
  }

  // ── Dialog dodawania własnej wyszukiwarki ────────────────────────────────

  Future<void> _showAddCustomDialog(BrowserService svc) async {
    if (!await _verifyPassword(svc)) return;

    final nameCtrl = TextEditingController();
    final searchCtrl = TextEditingController();
    bool safesearch = false;
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDS) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            'Własna wyszukiwarka',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Nazwa
                  TextFormField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Nazwa',
                      labelStyle: TextStyle(color: Colors.grey),
                      hintText: 'np. Moja wyszukiwarka',
                      hintStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.blueAccent,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Podaj nazwę' : null,
                  ),
                  const SizedBox(height: 14),

                  // Jedyne pole URL — zawiera %s
                  TextFormField(
                    controller: searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'URL wyszukiwania',
                      labelStyle: TextStyle(color: Colors.grey),
                      hintText: 'https://example.com/search?q=%s',
                      hintStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.blue),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Colors.blueAccent,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Podaj URL';
                      if (!v.contains('%s')) {
                        return 'URL musi zawierać %s (zastępnik zapytania)';
                      }
                      final uri = Uri.tryParse(
                        v.replaceAll('%s', 'test').trim(),
                      );
                      if (uri == null || !uri.hasScheme) {
                        return 'Nieprawidłowy URL (wymagane https://)';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 12),

                  // Podpowiedź
                  Container(
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
                            'Użyj %s jako miejsca na wpisaną frazę.\n'
                            'Przykład: https://example.com/find?q=%s\n'
                            'Strona główna zostanie wykryta automatycznie.',
                            style: TextStyle(color: Colors.blue, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // SafeSearch toggle
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SwitchListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      title: const Text(
                        'Wymuś SafeSearch',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                      subtitle: Text(
                        safesearch
                            ? 'Parametr &safe=active zostanie dodany do URL'
                            : 'Brak wymuszenia filtrowania treści',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 11,
                        ),
                      ),
                      value: safesearch,
                      activeColor: Colors.blue,
                      onChanged: (v) => setDS(() => safesearch = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ANULUJ', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                // Dedukuj stronę główną z URL wyszukiwania
                final rawSearch = searchCtrl.text.trim();
                final uri = Uri.tryParse(rawSearch.replaceAll('%s', 'test'));
                final homeUrl = uri != null
                    ? '${uri.scheme}://${uri.host}'
                    : rawSearch.split('%s').first;

                await svc.addCustomSearchEngine(
                  name: nameCtrl.text,
                  homeUrl: homeUrl,
                  searchUrl: rawSearch,
                  safesearch: safesearch,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                setState(() => _selected = homeUrl);
              },
              child: const Text(
                'DODAJ',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Kafelek wyszukiwarki ─────────────────────────────────────────────────

  Widget _engineTile({
    required String name,
    required String url,
    required String desc,
    required Color color,
    Widget? leading,
    VoidCallback? onDelete,
    bool deleteDisabled = false,
  }) {
    final isSelected = _selected == url;
    return GestureDetector(
      onTap: () => setState(() => _selected = url),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.12) : const Color(0xFF2A2A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withOpacity(0.2),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            leading ??
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.search, color: color, size: 20),
                ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontSize: 15,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Text(
                    desc,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              Tooltip(
                message: deleteDisabled ? 'Ostatnia wyszukiwarka' : 'Usuń',
                child: IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: deleteDisabled
                        ? Colors.grey.withOpacity(0.3)
                        : Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: deleteDisabled ? null : onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              )
            else if (isSelected)
              Icon(Icons.check_circle, color: color, size: 22)
            else
              const Icon(
                Icons.radio_button_unchecked,
                color: Colors.grey,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }

  // ── Usuwanie wbudowanej ──────────────────────────────────────────────────

  Future<void> _deleteBuiltin(
    BrowserService svc,
    String name,
    String url,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          'Usuń wyszukiwarkę',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Ukryć „$name" z listy?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANULUJ', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'UKRYJ',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (_selected == url) {
        final fallback = _builtinEngines
            .firstWhere(
              (e) => e.url != url && !_hiddenBuiltins.contains(e.url),
              orElse: () => _builtinEngines.first,
            )
            .url;
        setState(() => _selected = fallback);
      }
      setState(() => _hiddenBuiltins.add(url));
      await svc.hideBuiltinEngine(url);
    }
  }

  // ── Usuwanie własnej ─────────────────────────────────────────────────────

  Future<void> _deleteCustom(
    BrowserService svc,
    int index,
    Map<String, String> e,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          'Usuń wyszukiwarkę',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Usunąć „${e['name']}"?',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ANULUJ', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'USUŃ',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      if (_selected == e['url']) {
        setState(() => _selected = 'https://www.google.com');
      }
      await svc.removeCustomSearchEngine(index);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BrowserService>();
    final total = _totalVisible(svc);
    final visibleBuiltins = _builtinEngines
        .where((e) => !_hiddenBuiltins.contains(e.url))
        .toList();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onboarding) ...[
          const SizedBox(height: 32),
          const Icon(Icons.travel_explore, size: 56, color: Colors.blue),
          const SizedBox(height: 16),
          const Text(
            'Wybierz wyszukiwarkę',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Której wyszukiwarki chcesz używać\ndo wyszukiwania w przeglądarce?',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 28),
        ],

        // ── Wbudowane ──
        ...visibleBuiltins.map(
          (e) => _engineTile(
            name: e.name,
            url: e.url,
            desc: e.desc,
            color: e.color,
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: e.color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Image.asset(e.icon),
            ),
            onDelete: () => _deleteBuiltin(svc, e.name, e.url),
            deleteDisabled: total <= 1,
          ),
        ),

        // ── Własne ──
        if (svc.customSearchEngines.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 18, bottom: 6, left: 2),
            child: Text(
              'WŁASNE',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 11,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...svc.customSearchEngines.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final hasSafe = e['safesearch'] == 'true';
            return _engineTile(
              name: e['name'] ?? 'Własna',
              url: e['url'] ?? '',
              desc: hasSafe
                  ? '${e['searchUrl'] ?? ''} • 🔒 SafeSearch'
                  : e['searchUrl'] ?? '',
              color: Colors.teal,
              onDelete: () => _deleteCustom(svc, i, e),
              deleteDisabled: total <= 1,
            );
          }),
        ],

        // ── Dodaj własną ──
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => _showAddCustomDialog(svc),
          icon: const Icon(Icons.add, size: 18, color: Colors.blue),
          label: const Text(
            'Dodaj własną wyszukiwarkę',
            style: TextStyle(color: Colors.blue),
          ),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.blue, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            minimumSize: const Size(double.infinity, 44),
          ),
        ),

        const SizedBox(height: 20),

        // ── Zatwierdź ──
        ElevatedButton(
          onPressed: _selected == null
              ? null
              : () async {
                  await svc.setSearchEngine(_selected!);
                  if (context.mounted) Navigator.pop(context);
                },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            disabledBackgroundColor: Colors.grey.shade800,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            widget.onboarding ? 'Rozpocznij przeglądanie' : 'Zapisz',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        if (widget.onboarding) const SizedBox(height: 16),
      ],
    );

    if (widget.onboarding) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF202124),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: content,
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: const Color(0xFF202124),
      title: const Text('Wyszukiwarka', style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(child: content),
    );
  }
}
