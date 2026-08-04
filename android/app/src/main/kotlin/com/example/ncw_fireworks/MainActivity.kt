package com.example.ncw_fireworks

import android.content.ActivityNotFoundException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // Must match WHATSAPP_CHANNEL in lib/core/utils/share_service.dart.
    private val whatsAppChannel = "ncw_fireworks/whatsapp_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, whatsAppChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "shareFileToChat" -> {
                        val filePath = call.argument<String>("filePath")
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message") ?: ""
                        if (filePath.isNullOrBlank()) {
                            result.error("bad_args", "filePath is required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            WhatsAppShareHelper.shareFileToChat(
                                context = this,
                                filePath = filePath,
                                phone = phone,
                                message = message,
                            )
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            // Neither WhatsApp nor WhatsApp Business installed —
                            // Dart side falls back to the generic share sheet.
                            result.error("not_installed", "WhatsApp is not installed", null)
                        } catch (e: Exception) {
                            result.error("failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}