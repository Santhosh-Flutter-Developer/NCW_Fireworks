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
/// **A real limitation, not a bug**: `receipt_listing` (the endpoint that
/// backs the Receipt list/cache — see `ReceiptRepository.listReceipts`)
/// only ever returns `receipt_id`, `receipt_number`, `receipt_date`,
/// `agent_name`, `party_name` and `total_amount` per row — never the
/// Remarks narration or the Payment Mode/Bank/Amount breakdown that
/// `rpt_receipt_a5.php` prints. There is no "load one receipt's full
/// details" endpoint either. So:
/// - A receipt still sitting in this device's pending-sync queue (created
///   here, not yet sent to `receipt.php`) carries that detail already —
///   see `ReceiptModel.narration`/`ReceiptModel.paymentLines`, sourced
///   from `ReceiptRepository.queueReceiptForSync`'s own cached row — and
///   prints exactly like the sample above.
/// - A receipt that's already synced only has the summary fields, so its
///   offline PDF shows the Remarks/Payment Mode boxes as "—" rather than
///   inventing content. Party contact/city are filled in on a best-effort
///   basis from the cached Party list by name (`PartyRepository
///   .cachedPartyByName`) — see `ReceiptController._buildReceiptPdfBytes`.
///   Full parity for synced receipts would need `receipt_listing` to
///   start returning `narration`/`payment_mode_data` per row so this app
///   could cache it.
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
        build: (context) => pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor, width: 0.5)),
          padding: const pw.EdgeInsets.all(6),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Text(
                'Receipt',
                textAlign: pw.TextAlign.center,
                style:
                    pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 3),
              _buildCompanyBlock(),
              pw.SizedBox(height: 4),
              if (isCancelled) _buildCancelledStamp(),
              _buildToAndReceiptMeta(receipt, party),
              _buildBoxedRow('Remarks', receipt.narration),
              _buildBoxedRow('Payment Mode', _paymentDetails(receipt)),
              pw.SizedBox(height: 4),
              _buildTotalAmount(receipt),
              pw.SizedBox(height: 4),
              _buildAmountInWords(receipt),
              pw.SizedBox(height: 18),
              _buildSignature(),
            ],
          ),
        ),
      ),
    );

    return doc.save();
  }

  // ---- Letterhead --------------------------------------------------------

  static pw.Widget _buildCompanyBlock() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          CompanyProfile.name,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        for (final line in CompanyProfile.addressLines)
          pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
        pw.Text('Contact : ${CompanyProfile.contactNumber}',
            style: const pw.TextStyle(fontSize: 9)),
        pw.Text('GST : ${CompanyProfile.gstNumber}',
            style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  // ---- "To" box (left) + "Receipt No / Receipt Date" box (right) --------

  static pw.Widget _buildToAndReceiptMeta(
      ReceiptModel receipt, PartyListItem? party) {
    final mobileNumber =
        receipt.mobileNumber.isNotEmpty ? receipt.mobileNumber : (party?.mobileNumber ?? '');
    final city = receipt.city.isNotEmpty ? receipt.city : (party?.city ?? '');

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
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
                  style:
                      pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
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
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
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

  // ---- Remarks / Payment Mode boxes --------------------------------------

  static pw.Widget _buildBoxedRow(String label, String value) {
    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(top: 4),
      decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _borderColor, width: 0.5)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 68,
            child: pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _greenLabel)),
          ),
          pw.Text(' : ', style: const pw.TextStyle(fontSize: 9)),
          pw.Expanded(
            child: pw.Text(value,
                style: const pw.TextStyle(fontSize: 8)),
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

  // ---- Total amount / amount in words ------------------------------------

  static pw.Widget _buildTotalAmount(ReceiptModel receipt) {
    return pw.Row(
      children: [
        pw.Text('Total Amount ',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(' :  ${_numberFormat.format(receipt.totalAmount)}',
            style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _greenLabel)),
      ],
    );
  }

  static pw.Widget _buildAmountInWords(ReceiptModel receipt) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Amount in words ',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text(' : ', style: const pw.TextStyle(fontSize: 9)),
        pw.Expanded(
          child: pw.Text(
            // `rpt_receipt_a5.php` calls `getIndianCurrency($total_amount)
            // .' Only'` — "Rupees" trails the number (see the sample:
            // "One Thousand Two Hundred and Twenty Rupees Only"), unlike
            // `IndianCurrencyWords.convert` used by Estimate/Quotation.
            IndianCurrencyWords.convertTrailingRupees(receipt.totalAmount),
            style: pw.TextStyle(fontSize: 9, color: _greenLabel),
          ),
        ),
      ],
    );
  }

  // ---- Signature ----------------------------------------------------------

  static pw.Widget _buildSignature() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('(Verified)',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.Text('Authorized Signature',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ],
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