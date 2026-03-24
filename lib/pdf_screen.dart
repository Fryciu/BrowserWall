import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:media_scanner/media_scanner.dart';

class PdfScreen extends StatefulWidget {
  final String path;
  final String title;
  const PdfScreen({super.key, required this.path, required this.title});

  @override
  State<PdfScreen> createState() => _PdfScreenState();
}

class _PdfScreenState extends State<PdfScreen> {
  int currentPage = 0;
  int totalPages = 0;
  bool isSaving = false;

  String? localPath;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _preparePdf();
  }

  Future<void> _preparePdf() async {
    if (widget.path.startsWith('content://')) {
      try {
        // Używamy platform channel do odczytania content uri
        // Najprościej: użyj biblioteki 'open_file' lub napisz prosty MethodChannel
        // Ale jeśli nie chcesz zmieniać wielu plików, spróbuj pobrać to jako bajty:

        // Dla Androida: używamy natywnego API InAppWebView do konwersji (jeśli to możliwe)
        // W większości przypadków wystarczy skopiować plik przez prosty plugin:
        // np. 'flutter_file_dialog' lub 'shared_storage'
      } catch (e) {
        print("Error converting content uri: $e");
      }
    } else {
      setState(() {
        localPath = widget.path;
        isLoading = false;
      });
    }
  }

  // FUNKCJA: Zapis PDF do folderu Pobrane
  Future<void> _saveFileToPermanentStorage() async {
    setState(() => isSaving = true);

    try {
      // 1. Sprawdź czy plik źródłowy istnieje
      final File sourceFile = File(widget.path);
      if (!await sourceFile.exists()) {
        throw Exception("Plik źródłowy nie istnieje");
      }

      // 2. Przygotuj bezpieczną nazwę pliku
      String safeTitle = _sanitizeFileName(widget.title);
      if (!safeTitle.toLowerCase().endsWith('.pdf')) {
        safeTitle += '.pdf';
      }

      // 3. Ustal katalog docelowy (NOWA WERSJA)
      Directory? targetDirectory = await _getDownloadsDirectory();

      if (targetDirectory == null) {
        throw Exception("Nie można uzyskać dostępu do folderu Pobrane");
      }

      // 4. Utwórz folder jeśli nie istnieje
      if (!await targetDirectory.exists()) {
        await targetDirectory.create(recursive: true);
      }

      // 5. Utwórz docelową ścieżkę z unikalną nazwą
      final String destinationPath = await _getUniqueFilePath(
        targetDirectory.path,
        safeTitle,
      );

      // 6. Kopiuj plik
      await sourceFile.copy(destinationPath);

      // 7. Zeskanuj plik aby pojawił się natychmiast
      if (Platform.isAndroid) {
        try {
          await MediaScanner.loadMedia(path: destinationPath);
          print("✅ Plik zeskanowany: $destinationPath");
        } catch (e) {
          print("MediaScanner error (non-critical): $e");
        }
      }

      // 8. Pokaż sukces
      if (mounted) {
        _showSuccessSnackBar(destinationPath);
      }
    } catch (e) {
      print("❌ BŁĄD ZAPISU: $e");
      await _fallbackSave();
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // Pobiera prawidłowy katalog Downloads
  Future<Directory?> _getDownloadsDirectory() async {
    if (!Platform.isAndroid) {
      return await getApplicationDocumentsDirectory();
    }

    // Sprawdź uprawnienia
    if (!await _checkStoragePermissions()) {
      return null;
    }

    // Lista potencjalnych ścieżek Downloads
    final List<String> possiblePaths = [
      '/storage/emulated/0/Download',
      '/sdcard/Download',
      '/storage/emulated/0/Downloads',
      '/sdcard/Downloads',
    ];

    // Sprawdź każdą ścieżkę
    for (String path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        return dir;
      }
    }

    // Jeśli nie znaleziono, użyj getExternalStorageDirectory
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        String basePath = externalDir.path;
        if (basePath.contains('/Android')) {
          basePath = basePath.split('/Android')[0];
          final downloadDir = Directory('$basePath/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir;
        }
      }
    } catch (e) {
      print("Error getting external storage: $e");
    }

    return null;
  }

  // Sprawdza i prosi o uprawnienia
  Future<bool> _checkStoragePermissions() async {
    if (await Permission.storage.isGranted) {
      return true;
    }

    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    // Proś o uprawnienia
    if (await Permission.storage.request().isGranted) {
      return true;
    }

    if (await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }

    return false;
  }

  // Czyści nazwę pliku z niedozwolonych znaków
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

  // Tworzy unikalną ścieżkę pliku (dodaje liczbę jeśli plik istnieje)
  Future<String> _getUniqueFilePath(String directory, String fileName) async {
    final file = File(p.join(directory, fileName));

    if (!await file.exists()) {
      return file.path;
    }

    // Plik istnieje - dodaj numer
    final nameWithoutExt = p.withoutExtension(fileName);
    final extension = p.extension(fileName);

    int counter = 1;
    while (true) {
      final newName = '${nameWithoutExt} ($counter)$extension';
      final newPath = p.join(directory, newName);
      if (!await File(newPath).exists()) {
        return newPath;
      }
      counter++;
    }
  }

  // Awaryjny zapis do katalogu aplikacji
  Future<void> _fallbackSave() async {
    try {
      final fallbackDir = await getApplicationDocumentsDirectory();
      final fileName = _sanitizeFileName(widget.title);
      final fallbackPath = p.join(
        fallbackDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_$fileName',
      );

      await File(widget.path).copy(fallbackPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Zapisano w folderze aplikacji",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (fallbackError) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Nie udało się zapisać pliku"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Pokazuje sukces z opcją otwarcia
  void _showSuccessSnackBar(String path) {
    final fileName = p.basename(path);
    final dirName = path.contains('Download') ? 'Pobrane' : 'Aplikacja';

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
                    '📁 $dirName/${_truncateFileName(fileName)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: "UDOSTĘPNIJ",
          textColor: Colors.white,
          onPressed: _shareFile,
        ),
      ),
    );
  }

  // Skraca nazwę pliku jeśli za długa
  String _truncateFileName(String fileName, {int maxLength = 30}) {
    if (fileName.length <= maxLength) return fileName;
    return '${fileName.substring(0, maxLength - 3)}...';
  }

  // Udostępnianie pliku
  void _shareFile() {
    Share.shareXFiles([XFile(widget.path)], text: 'Plik: ${widget.title}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF202124),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Przycisk Zapisu
          isSaving
              ? const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: "Pobierz na telefon",
                  onPressed: _saveFileToPermanentStorage,
                ),

          // Przycisk Udostępniania
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: "Udostępnij",
            onPressed: _shareFile,
          ),

          // Licznik stron
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 8),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "$currentPage / $totalPages",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: PDFView(
        filePath: widget.path,
        enableSwipe: true,
        swipeHorizontal: false,
        autoSpacing: true,
        pageFling: true,
        backgroundColor: Colors.black,
        onRender: (pages) {
          if (pages != null && mounted) {
            setState(() => totalPages = pages);
          }
        },
        onPageChanged: (page, total) {
          if (page != null && mounted) {
            setState(() => currentPage = page + 1);
          }
        },
        onError: (error) {
          print("PDF Error: $error");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Błąd ładowania PDF: $error"),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }
}
