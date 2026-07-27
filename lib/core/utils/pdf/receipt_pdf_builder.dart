import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:ncw_fireworks/data/models/billing_item_model.dart';
import 'package:ncw_fireworks/data/models/party/party_list_response_model.dart';
import 'package:ncw_fireworks/data/models/receipt_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'company_profile.dart';
import 'indian_currency_words.dart';

/// Builds the A5-landscape Receipt PDF entirely on-device, mirroring the
/// server's own `rpt_receipt_a5.php` (see the sample under
/// `Receipt No - SAN - RE024_26-27.pdf`) — same letterhead, "To" /
/// "Receipt No" / "Receipt Date" boxes, Remarks, Payment Mode, Total
/// Amount, Amount in words and signature blocks, in the same layout order
/// — so Print and Download both work with no network call, exactly like
/// `EstimatePdfBuilder` / `QuotationPdfBuilder`.
///
/// `receipt_listing` (the endpoint that backs the Receipt list/cache —
/// see `ReceiptRepository.listReceipts`) returns `narration` and
/// `payment_mode_data` per row in addition to the summary fields, so both
/// a still-pending and an already-synced receipt carry the Remarks/
/// Payment Mode detail `rpt_receipt_a5.php` prints:
/// - A receipt still sitting in this device's pending-sync queue (created
///   here, not yet sent to `receipt.php`) carries that detail from
///   `ReceiptRepository.queueReceiptForSync`'s own cached row — see
///   `ReceiptModel.narration`/`ReceiptModel.paymentLines`.
/// - A synced receipt carries it from `receipt_listing` itself, cached by
///   `DataSyncService` alongside the summary fields. Party contact/city
///   are still filled in on a best-effort basis from the cached Party
///   list by name (`PartyRepository.cachedPartyByName`) — see
///   `ReceiptController._buildReceiptPdfBytes` — since `receipt_listing`
///   only ever carries a combined name/mobile/city snapshot, not
///   separate fields.
class ReceiptPdfBuilder {
  static const _greenLabel = PdfColor.fromInt(0xFF008200); // rgb(0,130,0)
  static const _borderColor = PdfColor.fromInt(0xFF000000);
  static final _dateFormat = DateFormat('dd-MM-yyyy');
  static final _numberFormat = NumberFormat('#,##0.00');

  static Future<Uint8List> build({
    required ReceiptModel receipt,
    PartyListItem? party,
  }) async {
    final doc = pw.Document(title: 'Receipt');
    final isCancelled = receipt.status == DocStatus.cancelled;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5.landscape.copyWith(
          marginLeft: 8 * PdfPageFormat.mm,
          marginRight: 8 * PdfPageFormat.mm,
          marginTop: 6 * PdfPageFormat.mm,
          marginBottom: 6 * PdfPageFormat.mm,
        ),
        // A single `pw.Page` (not `pw.MultiPage`) with one flat, fixed
        // list of widgets — no `Stack`/`Positioned` and no `Spacer`. Both
        // `EstimatePdfBuilder` and `QuotationPdfBuilder` deliberately
        // avoid those (see their own notes on this pinned `pdf` package
        // version's `SpanningWidget`/auto-flow bugs) in favor of plain,
        // proven-to-work Column/Container/Row nesting, so this sticks to
        // the same known-safe subset rather than risking an untested
        // combination. The CANCELLED stamp is a plain centered rotated
        // block placed inline in the flow, same as those two builders'
        // own `_buildCancelledStamp()`.
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Title sits above the outer box entirely — not inside it — to
            // match the reference PDF.
            pw.Text(
              'Receipt',
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 3),
            // One continuous outer box wraps every section below — the
            // reference PDF reads as a single unbroken rectangle with
            // horizontal divider lines between sections, not a stack of
            // separately-bordered boxes with gaps in between. Each section
            // below supplies only its own bottom border (a divider); the
            // outer Container's left/right/top/bottom border closes the
            // whole thing, and — since nothing between here and the
            // bottom-most section adds its own left/right border — that
            // outer border's sides run unbroken for the box's full height.
            pw.Container(
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _borderColor, width: 0.5)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  _buildCompanyBlock(),
                  if (isCancelled) _buildCancelledStamp(),
                  _buildToAndReceiptMeta(receipt, party),
                  _buildBoxedRow('Remarks', receipt.narration),
                  _buildBoxedRow('Payment Mode', _paymentDetails(receipt),
                      minHeight: _paymentModeRowHeight),
                  _buildBoxedRow(
                      'Total Amount', _numberFormat.format(receipt.totalAmount),
                      valueColor: _greenLabel, bold: true),
                  _buildBoxedRow('Amount in words',
                      IndianCurrencyWords.convertTrailingRupees(
                          receipt.totalAmount),
                      valueColor: _greenLabel),
                  _buildFillerSection(),
                  _buildSignature(),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  // ---- Letterhead --------------------------------------------------------

  static pw.Widget _buildCompanyBlock() {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: _borderColor, width: 0.5)),
      ),
      padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 5),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(child: pw.SizedBox()),
              pw.Text(
                CompanyProfile.name,
                textAlign: pw.TextAlign.center,
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.Expanded(
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text('GST : ${CompanyProfile.gstNumber}',
                      style: const pw.TextStyle(fontSize: 9)),
                ),
              ),
            ],
          ),
          pw.Center(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                for (final line in CompanyProfile.addressLines)
                  pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
                pw.Text('Contact : ${CompanyProfile.contactNumber}',
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- "To" box (left) + "Receipt No / Receipt Date" box (right) --------

  static pw.Widget _buildToAndReceiptMeta(
      ReceiptModel receipt, PartyListItem? party) {
    final mobileNumber =
        receipt.mobileNumber.isNotEmpty ? receipt.mobileNumber : (party?.mobileNumber ?? '');
    final city = receipt.city.isNotEmpty ? receipt.city : (party?.city ?? '');

    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: _borderColor, width: 0.5)),
      ),
      child: pw.Row(
        // No crossAxisAlignment.stretch — see QuotationPdfBuilder's
        // identical row for why this trades a possible slight height
        // mismatch for guaranteed no-crash safety; the mutual left/right
        // borders below (each side draws it) mean whichever column is
        // taller still supplies a full-height divider line either way.
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    right:
                        pw.BorderSide(color: _borderColor, width: 0.5)),
              ),
              padding: const pw.EdgeInsets.all(4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('To',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: _greenLabel)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    receipt.partyName.isNotEmpty
                        ? 'Mr/Mrs. ${receipt.partyName},'
                        : 'Mr/Mrs.',
                    style: pw.TextStyle(
                        fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                  if (city.isNotEmpty)
                    pw.Text('$city,', style: const pw.TextStyle(fontSize: 8)),
                  if (mobileNumber.isNotEmpty)
                    pw.Text('Contact : $mobileNumber',
                        style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Container(
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                    left: pw.BorderSide(color: _borderColor, width: 0.5)),
              ),
              padding: const pw.EdgeInsets.all(4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _metaRow('Receipt No', receipt.receiptNumber),
                  pw.SizedBox(height: 2),
                  _metaRow('Receipt Date', _dateFormat.format(receipt.date)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _metaRow(String label, String value) {
    return pw.Row(
      children: [
        pw.SizedBox(
          width: 60,
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _greenLabel)),
        ),
        pw.Text(' : ', style: const pw.TextStyle(fontSize: 9)),
        pw.Expanded(
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    );
  }

  // ---- Remarks / Payment Mode / Total Amount / Amount in words rows -----

  // Payment Mode gets extra room — matches the reference PDF, where that
  // row is noticeably taller than the single-line rows around it.
  static const _paymentModeRowHeight = 46.0;

  static pw.Widget _buildBoxedRow(
    String label,
    String value, {
    double? minHeight,
    bool bold = false,
    PdfColor? valueColor,
  }) {
    return pw.Container(
      constraints: minHeight == null
          ? null
          : pw.BoxConstraints(minHeight: minHeight),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: _borderColor, width: 0.5)),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 72,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _greenLabel)),
          ),
          pw.Text(' : ', style: const pw.TextStyle(fontSize: 9)),
          pw.Expanded(
            child: pw.Text(value,
                style: pw.TextStyle(
                    fontSize: bold ? 9 : 8,
                    fontWeight: bold ? pw.FontWeight.bold : null,
                    color: valueColor)),
          ),
        ],
      ),
    );
  }

  /// Mirrors `rpt_receipt_a5.php`'s own `$payment_details` build-up:
  /// `<mode> (<bank>) - <amount>` per line, joined with " , ", omitting
  /// the "(<bank>)" part for cash-style modes. Only ever non-empty for a
  /// receipt still in the pending-sync queue — see the class doc.
  static String _paymentDetails(ReceiptModel receipt) {
    if (receipt.paymentLines.isEmpty) return '';
    final parts = <String>[];
    for (final line in receipt.paymentLines) {
      final amount = _numberFormat.format(line.amount);
      parts.add(line.isCash
          ? '${line.paymentModeName} - $amount'
          : '${line.paymentModeName} (${line.bankName}) - $amount');
    }
    return parts.join(' , ');
  }

  // ---- Filler: pad the box down so it "fit to full page" ----------------
  //
  // The reference PDF's outer box always reaches down close to the
  // signature line, with one blank section between "Amount in words" and
  // the signature row rather than leaving open space below the box
  // entirely. This is a fixed A5 `pw.Page` (not `MultiPage`), so there's
  // no page-fit uncertainty to hedge against the way the Estimate/
  // Quotation filler does — a fixed height reliably matches the reference.
  // No bottom border here (unlike the other boxed rows) — there's no
  // divider line directly above the signature row.
  static pw.Widget _buildFillerSection() {
    return pw.Container(
      constraints: const pw.BoxConstraints(minHeight: 60),
    );
  }

  // ---- Signature ----------------------------------------------------------

  static pw.Widget _buildSignature() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('(Verified)',
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('Authorized Signature',
              style:
                  pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // ---- Cancelled watermark --------------------------------------------------

  /// Same proven pattern as `EstimatePdfBuilder._buildCancelledStamp` — a
  /// plain centered rotated block placed inline in the flow, not an
  /// absolutely-positioned overlay (see the note in [build] for why).
  static pw.Widget _buildCancelledStamp() {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Transform.rotate(
        angle: 0.4,
        child: pw.Opacity(
          opacity: 0.35,
          child: pw.Text(
            'CANCELLED',
            style: pw.TextStyle(
              fontSize: 36,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
        ),
      ),
    );
  }
}