import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'pdf_downloader.dart';

/// Shares an already-built PDF (Quotation / Estimate / Receipt report)
/// with a party by handing it straight to the device's native share
/// sheet — the same "Share via..." grid the OS shows for any app
/// (WhatsApp, Telegram, Gmail, Drive, Messages, etc.), with the PDF
/// already attached.
///
/// Everything up to the moment the user actually taps "send" works with
/// no network at all — the PDF itself is built entirely on-device (see
/// `QuotationPdfBuilder` / `EstimatePdfBuilder` / `ReceiptPdfBuilder`),
/// and the native share sheet is a local OS operation that doesn't need
/// connectivity to *open*. If the device is actually offline when the
/// message is sent from inside WhatsApp, WhatsApp queues it and delivers
/// once connectivity returns, the same as it would for any message typed
/// by hand.
///
/// ---- Why there's no WhatsApp-specific priming step ------------------
/// An earlier version of this also opened a `wa.me` deep link for the
/// party's number just before showing the share sheet, so that chat
/// would be the most recently used one (and so ranked at the top of
/// Android's "Direct Share" row). That's been removed: on devices with
/// more than one WhatsApp app installed (a cloned/dual "WhatsApp
/// Business" or parallel-space copy, common on Android phones with
/// "clone app"/"dual apps" features), Android can't silently decide
/// which one to open and shows its own "open with" chooser first —
/// meaning the user saw two popups instead of one. A single, direct trip
/// to the share sheet is the only version of this that's reliably
/// one-popup on every device.
///
/// ---- Where the time actually goes, and what's tuned here ------------
/// Two things happen before the OS can show anything at all: (1) the PDF
/// is generated in Dart, and (2) it's written to a real file on disk (the
/// share sheet needs an actual file path, not just bytes in memory).
/// Both are optimized here: [_tempDir] resolves the temp directory once
/// and reuses it instead of hitting a platform channel on every share,
/// and [_PreparingOverlay] only appears at all if building genuinely
/// takes a moment (see [_overlayDelay]) — a typical bill shares with no
/// extra UI in the way whatsoever. What's *not* tunable from here is the
/// moment after that: once `Share.shareXFiles` is called, Android itself
/// takes over — it has to enumerate every installed app that can accept
/// a PDF and rank "Direct Share" targets (shortcuts from apps like
/// WhatsApp) before it can draw the sheet. On a phone with a lot of apps
/// installed that step alone can take real time, and it's identical for
/// every app's share button on that device, not something specific to
/// this one.
class ShareService {
  const ShareService._();

  static bool _busy = false;

  /// Only shown if [buildBytes] hasn't finished within this long — avoids
  /// a pointless flash of "Preparing…" for the common, fast case while
  /// still covering genuinely slow builds (a bill with many line items)
  /// so those don't look like nothing happened.
  static const _overlayDelay = Duration(milliseconds: 250);

  static Directory? _cachedTempDir;

  /// Builds the PDF, then immediately opens the native share sheet with
  /// it attached. Ignores any call made while a previous one is still in
  /// progress, so rapid repeat taps on the Share icon can't stack up
  /// multiple share sheets.
  ///
  /// [partyName] personalizes the message text that comes pre-filled
  /// alongside the PDF; pass `null`/empty if it isn't known. [phone] is
  /// accepted for forward-compatibility (and because callers already
  /// have it on hand) but isn't used by this generic [share] path, now
  /// that there's no WhatsApp-specific priming step here — see the class
  /// doc. [shareToWhatsApp] below is the one that actually uses [phone].
  /// [onBuildError], if given, is called instead of a generic snackbar
  /// when [buildBytes] itself throws — callers with a richer error
  /// dialog (e.g. `QuotationController._showPdfErrorDialog`) can pass it
  /// through here to keep that same experience for share failures.
  static Future<void> share({
    required Future<Uint8List> Function() buildBytes,
    required String fileName,
    required String documentLabel,
    String? partyName,
    String? phone,
    void Function(Object error, StackTrace stackTrace)? onBuildError,
  }) async {
    if (_busy) {
      // Already working on a previous tap — say nothing further and
      // just ignore this one rather than queuing a second share.
      return;
    }
    _busy = true;

    var overlayShown = false;
    // Delayed-onset spinner: only actually shows up if buildBytes() is
    // still running once this fires. Cancelled the instant building
    // finishes, so a fast share never sees it at all.
    final overlayTimer = Timer(_overlayDelay, () {
      overlayShown = true;
      Get.dialog(
        const _PreparingOverlay(),
        barrierDismissible: false,
        transitionDuration: Duration.zero,
      );
    });

    void closeOverlayIfShown() {
      overlayTimer.cancel();
      if (overlayShown) {
        Get.back();
        overlayShown = false;
      }
    }

    try {
      final Uint8List bytes;
      try {
        bytes = await buildBytes();
      } catch (e, st) {
        debugPrint('ShareService: failed to build PDF: $e\n$st');
        closeOverlayIfShown();
        if (onBuildError != null) {
          onBuildError(e, st);
        } else {
          Get.snackbar(
            'Could not share',
            'Something went wrong preparing the PDF: $e',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return;
      }

      final message = _messageFor(documentLabel, fileName, partyName);
      final safeName = PdfDownloader.sanitizeFileName(fileName);

      try {
        final file = await _prepareFile(bytes, safeName);
        // Close right before handing off to the OS — from here on,
        // Android/iOS/the browser own the remaining time (see class doc).
        closeOverlayIfShown();
        final result =
            await Share.shareXFiles([file], text: message, subject: safeName);
        if (result.status == ShareResultStatus.unavailable) {
          throw Exception('Sharing is not available on this device.');
        }
      } catch (e, st) {
        debugPrint(
            'ShareService: file share failed, falling back to download: $e\n$st');
        closeOverlayIfShown();
        await _fallbackToDownload(bytes: bytes, fileName: safeName);
      }
    } finally {
      overlayTimer.cancel();
      if (overlayShown) {
        try {
          Get.back();
        } catch (_) {
          // Already dismissed some other way — nothing further to do.
        }
      }
      _busy = false;
    }
  }

  /// Talks to `WhatsAppShareHelper.kt` (Android only) — see that file's
  /// class doc for exactly what it does and doesn't guarantee.
  static const _whatsAppChannel = MethodChannel('ncw_fireworks/whatsapp_share');

  /// Same as [share], but goes straight to a single party's WhatsApp
  /// chat instead of the generic "share via..." OS sheet — used by the
  /// WhatsApp icon on the Quotation/Estimation/Receipt list rows.
  ///
  /// This works fully offline right up to the moment of actually
  /// tapping "send" inside WhatsApp, exactly like [share] — the PDF is
  /// built on-device, and opening WhatsApp on a specific chat doesn't
  /// require connectivity either (WhatsApp itself queues the message if
  /// the device is offline when send is tapped).
  ///
  /// Direct-to-chat targeting (skipping WhatsApp's own contact picker)
  /// is Android-only and best-effort — see `WhatsAppShareHelper.kt`.
  /// On iOS, or if the direct attempt fails for any reason (WhatsApp
  /// not installed, no phone number on file, a platform quirk), this
  /// falls back to the same generic share sheet as [share] so the user
  /// can still pick WhatsApp from there manually.
  static Future<void> shareToWhatsApp({
    required Future<Uint8List> Function() buildBytes,
    required String fileName,
    required String documentLabel,
    String? partyName,
    String? phone,
    void Function(Object error, StackTrace stackTrace)? onBuildError,
  }) async {
    if (_busy) {
      return;
    }
    _busy = true;

    var overlayShown = false;
    final overlayTimer = Timer(_overlayDelay, () {
      overlayShown = true;
      Get.dialog(
        const _PreparingOverlay(),
        barrierDismissible: false,
        transitionDuration: Duration.zero,
      );
    });
    void closeOverlayIfShown() {
      overlayTimer.cancel();
      if (overlayShown) {
        Get.back();
        overlayShown = false;
      }
    }

    try {
      final Uint8List bytes;
      try {
        bytes = await buildBytes();
      } catch (e, st) {
        debugPrint('ShareService: failed to build PDF: $e\n$st');
        closeOverlayIfShown();
        if (onBuildError != null) {
          onBuildError(e, st);
        } else {
          Get.snackbar(
            'Could not share',
            'Something went wrong preparing the PDF: $e',
            snackPosition: SnackPosition.BOTTOM,
          );
        }
        return;
      }

      final message = _messageFor(documentLabel, fileName, partyName);
      final safeName = PdfDownloader.sanitizeFileName(fileName);
      final normalizedPhone = _normalizePhone(phone);

      try {
        final file = await _prepareFile(bytes, safeName);
        closeOverlayIfShown();

        var wentDirectToWhatsApp = false;
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          try {
            await _whatsAppChannel.invokeMethod<bool>('shareFileToChat', {
              'filePath': file.path,
              'phone': normalizedPhone,
              'message': message,
            });
            wentDirectToWhatsApp = true;
          } on PlatformException catch (e) {
            // 'not_installed' or any native-side hiccup -> fall through
            // to the generic share sheet below.
            debugPrint('ShareService: direct WhatsApp share failed '
                '(${e.code}), falling back to share sheet: ${e.message}');
          }
        }

        if (!wentDirectToWhatsApp) {
          final result = await Share.shareXFiles([file],
              text: message, subject: safeName);
          if (result.status == ShareResultStatus.unavailable) {
            throw Exception('Sharing is not available on this device.');
          }
        }
      } catch (e, st) {
        debugPrint(
            'ShareService: WhatsApp share failed, falling back to download: $e\n$st');
        closeOverlayIfShown();
        await _fallbackToDownload(bytes: bytes, fileName: safeName);
      }
    } finally {
      overlayTimer.cancel();
      if (overlayShown) {
        try {
          Get.back();
        } catch (_) {}
      }
      _busy = false;
    }
  }

  /// Best-effort normalization to "country code + number, digits only"
  /// (e.g. "9876543210" -> "919876543210"), which is the form WhatsApp
  /// expects for both `wa.me` links and the `jid` extra. Assumes India
  /// (+91) for bare 10-digit numbers, since that's this app's userbase;
  /// numbers that already include a country code are left as-is.
  /// Returns null if there's nothing usable to normalize.
  static String? _normalizePhone(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (digits.length == 10) return '91$digits';
    if (digits.length == 11 && digits.startsWith('0')) {
      return '91${digits.substring(1)}';
    }
    return digits;
  }

  /// Resolved once per app session and reused — [getTemporaryDirectory]
  /// is a platform-channel round trip, and the OS temp directory doesn't
  /// change mid-session, so there's no reason to pay for that call again
  /// on every single share.
  static Future<Directory> _tempDir() async {
    return _cachedTempDir ??= await getTemporaryDirectory();
  }

  static Future<XFile> _prepareFile(Uint8List bytes, String safeName) async {
    if (kIsWeb) {
      return XFile.fromData(
        bytes,
        name: '$safeName.pdf',
        mimeType: 'application/pdf',
      );
    }
    final dir = await _tempDir();
    final path = '${dir.path}/$safeName.pdf';
    await XFile.fromData(bytes, mimeType: 'application/pdf').saveTo(path);
    return XFile(path, name: '$safeName.pdf', mimeType: 'application/pdf');
  }

  /// If the native/web share sheet isn't available at all (an older
  /// WebView, a desktop browser with no Web Share API support, etc.) the
  /// PDF is saved to disk instead, same as the existing Download button,
  /// so the user always ends up with the file either way and can attach
  /// it inside WhatsApp manually.
  static Future<void> _fallbackToDownload({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      await PdfDownloader.saveBytes(bytes: bytes, fileName: fileName);
      Get.snackbar(
        'Saved instead',
        'Sharing isn\'t available here, so the PDF was downloaded — attach it from your files.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } catch (e) {
      Get.snackbar(
        'Could not share',
        'Something went wrong preparing the file: $e',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  static String _messageFor(
      String documentLabel, String fileName, String? partyName) {
    final who = (partyName == null || partyName.trim().isEmpty)
        ? ''
        : 'Hi ${partyName.trim()}, ';
    final label = fileName.trim().isEmpty ? documentLabel : fileName.trim();
    return '${who}sharing your $documentLabel $label. Please find the PDF attached.';
  }
}

/// A minimal "working on it" indicator — only ever shown if building the
/// PDF genuinely takes longer than [ShareService._overlayDelay], so the
/// common fast case never sees any extra UI at all before the share
/// sheet opens.
class _PreparingOverlay extends StatelessWidget {
  const _PreparingOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children:  [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
              SizedBox(width: 14),
              Text('Preparing to share…'),
            ],
          ),
        ),
      ),
    );
  }
}