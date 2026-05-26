import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'browser_service.dart';
import 'pattern_lock.dart';

class PasswordDialog extends StatefulWidget {
  final BrowserService svc;
  const PasswordDialog({super.key, required this.svc});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _newPController = TextEditingController();
  final _repeatPController = TextEditingController();

  bool _obscureNew = true;
  bool _obscureRepeat = true;
  late PasswordType _selectedType;

  List<int>? _firstPattern;
  bool _waitingSecond = false;
  String _patternError = '';

  @override
  void initState() {
    super.initState();
    _selectedType = widget.svc.passwordType;
  }

  @override
  void dispose() {
    _newPController.dispose();
    _repeatPController.dispose();
    super.dispose();
  }

  Color get _bgColor => context.read<BrowserService>().incognitoMode
      ? const Color.fromARGB(255, 116, 31, 162)
      : const Color(0xFF202124);

  Widget _buildTypeSelector(PasswordType current) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          _typeChip('Tekstowe', PasswordType.text, current, Icons.text_fields),
          const SizedBox(width: 6),
          _typeChip('Wzór', PasswordType.pattern, current, Icons.grid_3x3),
        ],
      ),
    );
  }

  Widget _typeChip(String label, PasswordType type, PasswordType current, IconData icon) {
    final selected = type == current;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedType = type;
        _firstPattern = null;
        _waitingSecond = false;
        _patternError = '';
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.withValues(alpha: 0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: selected ? Colors.blue : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? Colors.blue : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final type = _selectedType;

    if (type == PasswordType.text) {
      final newP = _newPController.text;
      final repeatP = _repeatPController.text;
      if (newP.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hasło nie może być puste!")),
        );
        return;
      }
      if (newP != repeatP) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hasła nie są zgodne!")),
        );
        return;
      }
      await widget.svc.savePassword(newP);
    } else if (type == PasswordType.pattern) {
      if (_firstPattern == null || !_waitingSecond) {
        setState(() => _patternError = 'Najpierw narysuj wzór');
        return;
      }
      await widget.svc.savePattern(_firstPattern!);
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final hasP = widget.svc.hasPassword;
    final type = _selectedType;

    return AlertDialog(
      backgroundColor: _bgColor,
      title: Text(
        hasP ? "Zmień hasło" : "Ustaw hasło",
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypeSelector(type),
          if (type == PasswordType.text) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _newPController,
              obscureText: _obscureNew,
              style: const TextStyle(color: Colors.white),
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
            const SizedBox(height: 12),
            TextField(
              controller: _repeatPController,
              obscureText: _obscureRepeat,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Powtórz nowe hasło",
                hintStyle: const TextStyle(color: Colors.grey),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureRepeat ? Icons.visibility : Icons.visibility_off,
                    color: Colors.blue,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscureRepeat = !_obscureRepeat),
                ),
              ),
            ),
          ] else if (type == PasswordType.pattern) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Narysuj wzór (minimum 2 punkty)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
            if (_patternError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _patternError,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            if (_waitingSecond)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Powtórz wzór',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            PatternLock(
              onPatternEntered: (pattern) {
                if (!_waitingSecond) {
                  _firstPattern = pattern;
                  _waitingSecond = true;
                  _patternError = '';
                  setState(() {});
                } else {
                  if (_firstPattern != null &&
                      _listEqual(_firstPattern!, pattern)) {
                    widget.svc.savePattern(pattern).then((_) {
                      if (mounted) Navigator.pop(context);
                    });
                  } else {
                    _firstPattern = null;
                    _waitingSecond = false;
                    _patternError = 'Wzory nie są zgodne. Spróbuj ponownie.';
                    setState(() {});
                  }
                }
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text("ANULUJ"),
        ),
        if (type == PasswordType.text)
          TextButton(
            onPressed: _save,
            child: const Text("ZAPISZ"),
          ),
      ],
    );
  }

  bool _listEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
