import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Cross-platform helper that saves PDF bytes to disk via `file_saver` —
/// either fetched from a live report endpoint ([download]) or already in
/// hand from a PDF built entirely on-device, with no network call at all
/// ([saveBytes] — see `QuotationPdfBuilder`).
///
/// - Web: triggers a normal browser download.
/// - Android: opens the native "Save As" picker (Storage Access Framework)
///   so the file lands in the visible Downloads folder — same reasoning
///   as [ExcelExporter], saveFile() alone would write to the app's
///   private, invisible storage on Android.
/// - iOS / desktop: saves via file_saver's normal saveFile() location.
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

    await saveBytes(bytes: Uint8List.fromList(bytes), fileName: fileName);
  }

  /// Public wrapper around [_sanitizeFileName] — reused by `ShareService`
  /// so a shared PDF's temp-file/attachment name gets the same
  /// filesystem-safe treatment as a downloaded one (bill numbers like
  /// "EST021/26-27" contain characters most platforms reject in a name).
  static String sanitizeFileName(String name) => _sanitizeFileName(name);

  /// Saves already-generated PDF bytes to disk — shared by [download]
  /// (network-fetched bytes) and by any report built entirely on-device
  /// (e.g. `QuotationPdfBuilder`, which never touches the network at all).
  static Future<void> saveBytes({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final safeName = _sanitizeFileName(fileName);

    if (!kIsWeb && Platform.isAndroid) {
      await FileSaver.instance.saveAs(
        name: safeName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
    } else {
      await FileSaver.instance.saveFile(
        name: safeName,
        bytes: bytes,
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