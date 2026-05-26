import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'browser_service.dart';
import 'pattern_lock.dart';

class TimeRulesScreen extends StatelessWidget {
  const TimeRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<BrowserService>();
    final rules = svc.timeRules;
    final sortedRules = rules.entries.toList()
      ..sort((a, b) {
        final domainCompare = a.value.domain.toLowerCase().compareTo(
          b.value.domain.toLowerCase(),
        );
        if (domainCompare != 0) return domainCompare;
        return a.value.mode.name.compareTo(b.value.mode.name);
      });

    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        title: const Text(
          'Limity czasowe',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () => _openRuleEditor(context, svc),
          ),
        ],
      ),
      body: rules.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_off, color: Colors.grey, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'Brak reguł czasowych',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Dodaj regułę aby ograniczyć dostęp\ndo wybranej strony',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _openRuleEditor(context, svc),
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj regułę'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: sortedRules.length,
              itemBuilder: (ctx, i) {
                final ruleKey = sortedRules[i].key;
                final rule = sortedRules[i].value;
                final usedSeconds = svc.getTodayUsageSeconds(rule.domain);
                return _RuleCard(
                  domain: rule.domain,
                  rule: rule,
                  usedSeconds: usedSeconds,
                  onEdit: () => _openRuleEditor(
                    context,
                    svc,
                    existing: rule,
                    existingKey: ruleKey,
                  ),
                  onDelete: () =>
                      _confirmDeleteWithPassword(context, svc, ruleKey),
                );
              },
            ),
    );
  }

  // ── Usuwanie z hasłem ────────────────────────────────────────────────────

  void _confirmDeleteWithPassword(
    BuildContext context,
    BrowserService svc,
    String domain,
  ) async {
    final granted = await _confirmPassword(context, svc);
    if (granted != true) return;
    svc.removeTimeRule(domain);
  }

  Future<bool> _confirmPassword(
    BuildContext context,
    BrowserService svc,
  ) async {
    if (!svc.hasPassword) return true;

    if (svc.isBiometricType) {
      return svc.verifyWithBiometrics();
    }

    if (svc.isPatternType) {
      bool ok = false;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF202124),
          title: const Text(
            "Wymagany wzór",
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Narysuj wzór, aby odblokować',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              PatternLock(
                onPatternEntered: (pattern) {
                  if (svc.verifyPattern(pattern)) {
                    ok = true;
                    Navigator.pop(ctx);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Błędny wzór!")),
                    );
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ANULUJ"),
            ),
          ],
        ),
      );
      return ok;
    }

    String entered = "";
    final granted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("ANULUJ"),
          ),
          TextButton(
            onPressed: () {
              if (svc.verifyPassword(entered)) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text("Błędne hasło!")),
                );
              }
            },
            child: const Text("POTWIERDŹ"),
          ),
        ],
      ),
    );
    return granted == true;
  }

  void _openRuleEditor(
    BuildContext context,
    BrowserService svc, {
    TimeRule? existing,
    String? existingKey,
  }) async {
    final granted = await _confirmPassword(context, svc);
    if (granted != true || !context.mounted) return;
    _showAddRuleDialog(
      context,
      svc,
      existing: existing,
      existingKey: existingKey,
    );
  }

  void _showAddRuleDialog(
    BuildContext context,
    BrowserService svc, {
    TimeRule? existing,
    String? existingKey,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF2C2C2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _AddRuleSheet(svc: svc, existing: existing, existingKey: existingKey),
    );
  }
}

class _RuleCard extends StatelessWidget {
  final String domain;
  final TimeRule rule;
  final int usedSeconds;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RuleCard({
    required this.domain,
    required this.rule,
    required this.usedSeconds,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isBlocked = context.read<BrowserService>().isBlockedByTimeRule(
      'https://$domain',
    );
    final limitSeconds = rule.dailyLimitMinutes * 60;
    final remainingSeconds = (limitSeconds - usedSeconds).clamp(
      0,
      limitSeconds,
    );
    final usedLabel = _formatDurationSeconds(usedSeconds);
    final remainingLabel = _formatDurationSeconds(remainingSeconds);

    return Card(
      color: const Color(0xFF2C2C2E),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isBlocked
              ? Colors.red.shade900
              : Colors.blue.shade900,
          child: Icon(
            isBlocked ? Icons.block : Icons.timer,
            color: isBlocked ? Colors.red : Colors.blue,
            size: 20,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              domain,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            if (isBlocked)
              Text(
                'ZABLOKOWANA',
                style: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (rule.mode == TimeRuleMode.dailyLimit) ...[
              Text(
                'Limit dzienny: ${rule.dailyLimitMinutes} min',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 4),
              if (limitSeconds > 0)
                LinearProgressIndicator(
                  value: (usedSeconds / limitSeconds).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey.shade800,
                  color: remainingSeconds == 0 ? Colors.red : Colors.blue,
                ),
              Text(
                rule.dailyLimitMinutes == 0
                    ? 'Pozostało: 0 s'
                    : 'Pozostało: $remainingLabel • dziś: $usedLabel',
                style: TextStyle(
                  color: remainingSeconds == 0 ? Colors.red : Colors.grey,
                  fontSize: 11,
                ),
              ),
            ] else ...[
              Text(
                'Blokada: ${_fmt(rule.windowStart)} – ${_fmt(rule.windowEnd)}',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
            if (rule.allowedDays.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Dni: ${_daysLabel(rule.allowedDays)}',
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
              onPressed: onEdit,
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  String _formatDurationSeconds(int seconds) {
    if (seconds <= 0) return '0 s';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return secs > 0
          ? '$hours godz. $minutes min $secs s'
          : '$hours godz. $minutes min';
    }
    if (minutes > 0) {
      return secs > 0 ? '$minutes min $secs s' : '$minutes min';
    }
    return '$secs s';
  }

  String _daysLabel(List<int> days) {
    const names = ['', 'Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'Sb', 'Nd'];
    return days.map((d) => names[d]).join(', ');
  }
}

class _AddRuleSheet extends StatefulWidget {
  final BrowserService svc;
  final TimeRule? existing;
  final String? existingKey;
  const _AddRuleSheet({required this.svc, this.existing, this.existingKey});

  @override
  State<_AddRuleSheet> createState() => _AddRuleSheetState();
}

class _AddRuleSheetState extends State<_AddRuleSheet> {
  late TextEditingController _domainCtrl;
  late TimeRuleMode _mode;
  late int _dailyMinutes;
  late TimeOfDay _windowStart;
  late TimeOfDay _windowEnd;
  late List<int> _allowedDays;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _domainCtrl = TextEditingController(text: e?.domain ?? '');
    _mode = e?.mode ?? TimeRuleMode.dailyLimit;
    _dailyMinutes = e?.dailyLimitMinutes ?? 30;
    _windowStart = e?.windowStart ?? const TimeOfDay(hour: 8, minute: 0);
    _windowEnd = e?.windowEnd ?? const TimeOfDay(hour: 22, minute: 0);
    _allowedDays = List<int>.from(e?.allowedDays ?? []);
  }

  @override
  void dispose() {
    _domainCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const days = ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'Sb', 'Nd'];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.existing != null ? 'Edytuj regułę' : 'Nowa reguła czasowa',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Domena
            TextField(
              controller: _domainCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Domena (np. youtube.com, facebook.com)',
                labelStyle: const TextStyle(color: Colors.grey),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
                disabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                hintText: 'youtube.com, facebook.com',
                hintStyle: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 20),

            // Tryb
            const Text(
              'Typ reguły',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _ModeChip(
                  label: 'Limit dzienny',
                  icon: Icons.hourglass_bottom,
                  selected: _mode == TimeRuleMode.dailyLimit,
                  onTap: () => setState(() => _mode = TimeRuleMode.dailyLimit),
                ),
                const SizedBox(width: 10),
                _ModeChip(
                  label: 'Blokada godzinowa',
                  icon: Icons.access_time,
                  selected: _mode == TimeRuleMode.timeWindow,
                  onTap: () => setState(() => _mode = TimeRuleMode.timeWindow),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Ustawienia trybu
            if (_mode == TimeRuleMode.dailyLimit) ...[
              Text(
                _dailyMinutes == 0
                    ? 'Zawsze zablokowana'
                    : 'Limit: ${_formatDuration(_dailyMinutes)}',
                style: TextStyle(
                  color: _dailyMinutes == 0 ? Colors.red : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              // Szybkie przyciski
              Wrap(
                spacing: 8,
                children: [0, 15, 30, 60, 120, 180]
                    .map(
                      (min) => GestureDetector(
                        onTap: () => setState(() => _dailyMinutes = min),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _dailyMinutes == min
                                ? Colors.blue.shade900
                                : const Color(0xFF3A3A3E),
                            borderRadius: BorderRadius.circular(8),
                            border: _dailyMinutes == min
                                ? Border.all(color: Colors.blue)
                                : null,
                          ),
                          child: Text(
                            min == 0 ? 'Zawsze' : '$min min',
                            style: TextStyle(
                              color: _dailyMinutes == min
                                  ? Colors.blue
                                  : Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 10),
              // Pole do wpisania własnej wartości
              Row(
                children: [
                  const Text(
                    'Własna liczba minut: ',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: '0-1440',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                        isDense: true,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.blue),
                        ),
                      ),
                      onChanged: (v) {
                        final parsed = int.tryParse(v);
                        if (parsed != null && parsed >= 0 && parsed <= 1440) {
                          setState(() => _dailyMinutes = parsed);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '0 = zawsze zablokowana, 1440 = cały dzień',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _TimePicker(
                      label: 'Od',
                      time: _windowStart,
                      onChanged: (t) => setState(() => _windowStart = t),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _TimePicker(
                      label: 'Do',
                      time: _windowEnd,
                      onChanged: (t) => setState(() => _windowEnd = t),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Strona zablokowana w wybranym zakresie godzin',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],

            const SizedBox(height: 20),

            // Dni tygodnia
            Row(
              children: [
                const Text(
                  'Dni tygodnia (puste = każdy dzień)',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_allowedDays.length == 7) {
                        _allowedDays.clear();
                      } else {
                        _allowedDays = [1, 2, 3, 4, 5, 6, 7];
                      }
                    });
                  },
                  child: Text(
                    _allowedDays.length == 7
                        ? 'Odznacz wszystkie'
                        : 'Zaznacz wszystkie',
                    style: const TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(7, (i) {
                final day = i + 1;
                final selected = _allowedDays.contains(day);
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        if (selected)
                          _allowedDays.remove(day);
                        else
                          _allowedDays.add(day);
                        _allowedDays.sort();
                      });
                    },
                    child: Container(
                      margin: EdgeInsets.only(right: i < 6 ? 4 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.blue.shade900
                            : const Color(0xFF3A3A3E),
                        borderRadius: BorderRadius.circular(8),
                        border: selected
                            ? Border.all(color: Colors.blue)
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        days[i],
                        style: TextStyle(
                          color: selected ? Colors.blue : Colors.white,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _save,
                child: Text(
                  widget.existing != null ? 'Zapisz zmiany' : 'Dodaj regułę',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    if (minutes < 60) return '$minutes minut';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h godz.' : '$h godz. $m min';
  }

  void _save() async {
    final domains = _domainCtrl.text
        .split(',')
        .map(_cleanDomain)
        .where((domain) => domain.isNotEmpty)
        .toSet()
        .toList();
    if (domains.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Podaj domenę'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (widget.existingKey != null) {
      await widget.svc.removeTimeRule(widget.existingKey!);
    }
    for (final domain in domains) {
      await widget.svc.addTimeRule(
        TimeRule(
          domain: domain,
          mode: _mode,
          dailyLimitMinutes: _dailyMinutes,
          windowStart: _windowStart,
          windowEnd: _windowEnd,
          allowedDays: _allowedDays,
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  String _cleanDomain(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'^www\.'), '')
        .split('/')
        .first
        .trim();
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade900 : const Color(0xFF3A3A3E),
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: Colors.blue) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.blue : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.blue : Colors.grey,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePicker extends StatelessWidget {
  final String label;
  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onChanged;

  const _TimePicker({
    required this.label,
    required this.time,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time,
        );
        if (picked != null) onChanged(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF3A3A3E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, color: Colors.blue, size: 16),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
