import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'browser_service.dart';

class PasswordDialog extends StatefulWidget {
  final BrowserService svc;
  const PasswordDialog({super.key, required this.svc});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
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
      ? const Color.fromARGB(255, 116, 31, 162)
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
