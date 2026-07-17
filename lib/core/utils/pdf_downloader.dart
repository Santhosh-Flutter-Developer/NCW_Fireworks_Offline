import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Cross-platform helper that actually downloads a report PDF (as opposed
/// to just opening it in a viewer) and hands the bytes to `file_saver`.
///
/// - Web: triggers a normal browser download.
/// - Android: opens the native "Save As" picker (Storage Access Framework)
///   so the file lands in the visible Downloads folder — same reasoning
///   as [ExcelExporter], saveFile() alone would write to the app's
///   private, invisible storage on Android.
/// - iOS / desktop: saves via file_saver's normal saveFile() location.
///
/// This is deliberately separate from "Print", which just opens the same
/// report URL externally via `launchUrl` and lets the browser/OS PDF
/// viewer's own print button do the rest — Download needs to fetch and
/// persist the actual bytes.
class PdfDownloader {
  const PdfDownloader._();

  static Future<void> download({
    required Uri uri,
    required String fileName,
  }) async {
    final http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 30));
    } catch (_) {
      throw Exception('Could not reach the server to download the report.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned status ${response.statusCode}.');
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    // A bad/expired id on this kind of report endpoint typically comes
    // back as an HTML error page with a 200 status — guard against
    // silently "downloading" that instead of a real PDF.
    if (contentType.isNotEmpty &&
        !contentType.contains('pdf') &&
        !contentType.contains('octet-stream')) {
      throw Exception('The report is not available as a PDF right now.');
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw Exception('The report came back empty.');
    }

    final safeName = _sanitizeFileName(fileName);

    if (!kIsWeb && Platform.isAndroid) {
      await FileSaver.instance.saveAs(
        name: safeName,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
    } else {
      await FileSaver.instance.saveFile(
        name: safeName,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
    }
  }

  /// Bill numbers like "EST021/26-27" contain characters that aren't
  /// valid in file names on most platforms.
  static String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'report' : cleaned;
  }
}