import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'browser_service.dart';
import 'browser_screen.dart';

/* TODO 
    2. Podwójne podawanie hasła usunąć
    Jak się uda to:
    3. Naprawa adblocka tak, żeby blokował reklamy yt
*/
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? initialShortcutUrl;
  try {
    const channel = MethodChannel('app/shortcuts');
    initialShortcutUrl = await channel.invokeMethod<String>('getInitialUrl');
    print("main: initialShortcutUrl=$initialShortcutUrl");
  } catch (e) {
    print("main: błąd getInitialUrl: $e");
  }

  // Serwis tworzony przed runApp żeby handler miał do niego dostęp
  final svc = BrowserService();
  if (initialShortcutUrl != null && initialShortcutUrl.isNotEmpty) {
    svc.pendingShortcutUrl = initialShortcutUrl;
  }

  // Handler MUSI być ustawiony przed init() żeby nie przegapić eventu
  const channel = MethodChannel('app/shortcuts');
  channel.setMethodCallHandler((call) async {
    if (call.method == 'onShortcutUrl') {
      final url = call.arguments as String;
      print("onShortcutUrl received: $url");
      svc.pendingShortcutUrl = url;
      svc.notifyShortcut();
    }
  });

  svc.init();

  runApp(
    ChangeNotifierProvider.value(
      value: svc,
      child: const MaterialApp(
        home: BrowserScreen(),
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
}
