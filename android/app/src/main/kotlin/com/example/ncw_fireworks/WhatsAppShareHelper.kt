package com.example.ncw_fireworks

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

/**
 * Opens WhatsApp (or WhatsApp Business) directly on a single party's chat,
 * with the on-device Quotation/Estimate/Receipt PDF already attached —
 * used by the WhatsApp icon on the Quotation/Estimation/Receipt list
 * screens (see `ShareService.shareToWhatsApp` on the Dart side).
 *
 * How this actually targets one specific chat: WhatsApp's public share
 * contract (`ACTION_SEND` to package `com.whatsapp`) only ever opens
 * WhatsApp's own contact picker — there's no *official*, documented API
 * for a third-party app to preselect a chat. What's used here is the
 * `jid` extra ("<countrycode><number>@s.whatsapp.net"), which WhatsApp
 * has read for years to preselect a chat when present (this is the same
 * mechanism most "share directly to a WhatsApp contact" features in
 * other apps rely on). It isn't documented or contractually guaranteed,
 * so this always degrades gracefully:
 *   - no phone number on file for the party -> plain ACTION_SEND to
 *     WhatsApp (opens WhatsApp's own contact picker with the file ready)
 *   - a WhatsApp update stops honouring `jid` -> same graceful outcome,
 *     WhatsApp opens its contact picker instead of the exact chat
 *   - WhatsApp not installed at all -> throws, so the Dart side can fall
 *     back to the normal OS share sheet (`ShareService.share`)
 */
object WhatsAppShareHelper {

    private const val PACKAGE_PERSONAL = "com.whatsapp"
    private const val PACKAGE_BUSINESS = "com.whatsapp.w4b"

    /**
     * @param filePath absolute path to the already-written PDF (see
     *   `ShareService`'s temp-dir file prep — this must live under the
     *   cache dir declared in `res/xml/ncw_file_paths.xml`).
     * @param phone party's mobile number, digits only, with country code
     *   (e.g. "919876543210"). Pass null/blank if unknown.
     * @param message pre-filled caption text.
     * @throws ActivityNotFoundException if neither WhatsApp nor WhatsApp
     *   Business is installed — callers should catch this and fall back
     *   to the generic share sheet.
     */
    fun shareFileToChat(
        context: Context,
        filePath: String,
        phone: String?,
        message: String,
    ) {
        val targetPackage = resolveInstalledPackage(context)
            ?: throw ActivityNotFoundException("WhatsApp is not installed")

        val file = File(filePath)
        val authority = "${context.packageName}.ncwfireworks.fileprovider"
        val uri = FileProvider.getUriForFile(context, authority, file)

        val intent = Intent(Intent.ACTION_SEND).apply {
            `package` = targetPackage
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TEXT, message)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (!phone.isNullOrBlank()) {
                // Best-effort direct-chat targeting — see class doc.
                putExtra("jid", "$phone@s.whatsapp.net")
            }
        }
        context.startActivity(intent)
    }

    private fun resolveInstalledPackage(context: Context): String? {
        val pm = context.packageManager
        for (pkg in listOf(PACKAGE_PERSONAL, PACKAGE_BUSINESS)) {
            try {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, 0)
                return pkg
            } catch (_: Exception) {
                // Not installed — try the next candidate.
            }
        }
        return null
    }
}