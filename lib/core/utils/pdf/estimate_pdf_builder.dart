import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:ncw_fireworks/data/models/billing_item_model.dart';
import 'package:ncw_fireworks/data/models/estimation_model.dart';
import 'package:ncw_fireworks/data/models/party/party_list_response_model.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'company_profile.dart';
import 'indian_currency_words.dart';

/// Builds the A4 estimate PDF entirely on-device from data already in
/// hand (the estimate itself, plus its party's full details — see
/// `PartyRepository.cachedPartyById`) — no network call, so Print and
/// Download both work the same whether the device is online or not.
///
/// Structurally identical to `QuotationPdfBuilder` — same MultiPage +
/// no-`pw.Table` + no-`Row`-`stretch` + `_s()` safety pattern (see the
/// notes in [build] and [_s] for why those matter) — with two content
/// differences matching the server's own `rpt_estimate_a4.php`: the
/// "Bill To" block includes more of the party's fields (contact, email,
/// GST, identification), and named Charges lines are shown alongside
/// the section Add/Discount rows.
class EstimatePdfBuilder {
  static const _greenLabel = PdfColor.fromInt(0xFF008200); // rgb(0,130,0)
  static const _headerFill = PdfColor.fromInt(0xFF65727A); // rgb(101,114,122)
  static const _borderColor = PdfColor.fromInt(0xFF000000);
  static final _dateFormat = DateFormat('dd-MM-yyyy');
  static final _numberFormat = NumberFormat('#,##0.00');

  static Future<Uint8List> build({
    required EstimationModel estimate,
    PartyListItem? party,
  }) async {
    final doc = pw.Document(title: 'Estimate');
    final isCancelled = estimate.status == DocStatus.cancelled;
    final filler = _buildFiller(estimate);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 10 * PdfPageFormat.mm,
          marginRight: 10 * PdfPageFormat.mm,
          marginTop: 8 * PdfPageFormat.mm,
          marginBottom: 8 * PdfPageFormat.mm,
        ),
        // See QuotationPdfBuilder's build() for the full explanation:
        // no header:/footer: callbacks, no `pw.Table`, no `Row` with
        // crossAxisAlignment.stretch anywhere — each is a confirmed (by
        // reading the `pdf` package source directly) way to end up with
        // either TooManyPagesException or an Infinite-height layout
        // exception in this package version. Every top-level item is
        // wrapped with _s() as a result.
        build: (context) => [
          _s(_buildLetterhead(estimate, party)),
          pw.SizedBox(height: 4),
          if (isCancelled) _s(_buildCancelledStamp()),
          for (final row in _buildProductRows(estimate)) _s(row),
          for (final row in _buildComplimentRows(estimate)) _s(row),
          if (filler != null) _s(filler),
          for (final row in _buildTotals(estimate)) _s(row),
          pw.SizedBox(height: 6),
          _s(_buildDeclarationAndSignature(estimate)),
          pw.SizedBox(height: 6),
          _s(_buildFooter()),
        ],
      ),
    );

    return doc.save();
  }

  /// See `QuotationPdfBuilder._s` — identical purpose: shields any
  /// nested `pw.Column`/`pw.Table` from a SpanningWidget bug in this
  /// package version, and stretches [child] to the page's full width.
  static pw.Widget _s(pw.Widget child) {
    return pw.Row(children: [pw.Expanded(child: child)]);
  }

  // ---- Letterhead: title + company block + Bill To / Bill Date box ---

  static pw.Widget _buildLetterhead(
    EstimationModel estimate,
    PartyListItem? party,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Company block, boxed, with the GST number pinned to the top-right
        // corner on the same line as the title (matches the reference PDF)
        // instead of buried as another line inside the centered address.
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor, width: 0.5)),
          padding: const pw.EdgeInsets.fromLTRB(6, 4, 6, 5),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(child: pw.SizedBox()),
                  pw.Text(
                    'Estimate',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold),
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
              pw.SizedBox(height: 2),
              pw.Center(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      CompanyProfile.name,
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    for (final line in CompanyProfile.addressLines)
                      pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Contact : ${CompanyProfile.contactNumber}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        // Bill To / Bill Date+No+HSN as ONE bordered box with a vertical
        // divider between the two halves — rather than two independent
        // boxes — so the outer border always reads as a single box of
        // uniform height (the taller side, almost always "Bill To",
        // supplies the divider's full height; see the note on
        // crossAxisAlignment below for why this can't just be `stretch`).
        pw.Container(
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor, width: 0.5)),
          child: pw.Row(
            // No stretch — see QuotationPdfBuilder's identical row for why.
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        right:
                            pw.BorderSide(color: _borderColor, width: 0.5)),
                  ),
                  padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 3),
                  child: _buildBillTo(party),
                ),
              ),
              pw.Expanded(
                child: pw.Container(
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                        left:
                            pw.BorderSide(color: _borderColor, width: 0.5)),
                  ),
                  padding: const pw.EdgeInsets.fromLTRB(4, 3, 4, 3),
                  child: _buildBillMeta(estimate),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Fuller than the quotation report's Bill To block — matches the
  /// server's sample: name, mobile, address, city, district, state,
  /// pincode, email, GST, and identification, each shown only when known.
  static pw.Widget _buildBillTo(PartyListItem? party) {
    final lines = <String>[];
    if (party != null) {
      if (party.partyName.isNotEmpty) lines.add(party.partyName);
      if (party.mobileNumber.isNotEmpty) {
        lines.add('Contact : ${party.mobileNumber}');
      }
      if (party.address.isNotEmpty) lines.add(party.address);
      final cityLine = [party.city, party.othersCity]
          .where((s) => s.isNotEmpty)
          .join(', ');
      if (cityLine.isNotEmpty) lines.add(cityLine);
      if (party.pincode.isNotEmpty) lines.add(party.pincode);
      if (party.district.isNotEmpty) lines.add('${party.district} (Dist.)');
      if (party.state.isNotEmpty) lines.add(party.state);
      if (party.email.isNotEmpty) lines.add('Email : ${party.email}');
      if (party.gstNumber.isNotEmpty) {
        lines.add('GST IN : ${party.gstNumber}');
      }
      if (party.identification.isNotEmpty) lines.add(party.identification);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Bill To :',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        if (lines.isEmpty)
          pw.Text('Direct', style: const pw.TextStyle(fontSize: 8))
        else ...[
          pw.Text(lines.first,
              style:
                  pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          for (final line in lines.skip(1))
            pw.Text(line, style: const pw.TextStyle(fontSize: 8)),
        ],
      ],
    );
  }

  static pw.Widget _buildBillMeta(EstimationModel estimate) {
    pw.Widget row(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 62,
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
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        row('Bill Date', _dateFormat.format(estimate.date)),
        row('Bill No', estimate.estimationNo),
        row('HSN Code', '3604'),
      ],
    );
  }

  // ---- Cancelled watermark ---------------------------------------------

  static pw.Widget _buildCancelledStamp() {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Transform.rotate(
        angle: 0.4,
        child: pw.Opacity(
          opacity: 0.4,
          child: pw.Text(
            'CANCELLED',
            style: pw.TextStyle(
              fontSize: 40,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.red,
            ),
          ),
        ),
      ),
    );
  }

  // ---- Product rows (deliberately not a pw.Table — see build()'s note) --

  static const _colSNo = 5;
  static const _colProduct = 52;
  static const _colQty = 16;
  static const _colRate = 13;
  static const _colAmount = 14;

  // Minimum content height for one product/compliment table row (a single
  // line of 8pt text plus its 3+3 vertical padding). Applied as a floor,
  // not a fixed height, so it doesn't clip a product name that wraps to
  // two lines — but it does stop an *empty* cell (Rate/Amount on a
  // compliment row, which has no text at all) from collapsing to just its
  // padding and leaving its column-divider border as a short stray line
  // instead of running the full height of the row.
  static const _rowMinHeight = 15.0;

  static pw.Widget _gridCell(
    pw.Widget child, {
    required int flex,
    bool isLast = false,
  }) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        constraints: const pw.BoxConstraints(minHeight: _rowMinHeight),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            right: isLast
                ? pw.BorderSide.none
                : const pw.BorderSide(color: _borderColor, width: 0.5),
          ),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
        child: child,
      ),
    );
  }

  static pw.Widget _productHeaderRow() {
    final style = pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    );
    pw.Widget cell(String text, int flex, {bool isLast = false}) => _gridCell(
          pw.Text(text, style: style, textAlign: pw.TextAlign.center),
          flex: flex,
          isLast: isLast,
        );

    return pw.Container(
      decoration: const pw.BoxDecoration(
        color: _headerFill,
        border: pw.Border(
          top: pw.BorderSide(color: _borderColor, width: 0.5),
          left: pw.BorderSide(color: _borderColor, width: 0.5),
          right: pw.BorderSide(color: _borderColor, width: 0.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          cell('S.No', _colSNo),
          cell('Product', _colProduct),
          cell('Qty', _colQty),
          cell('Rate(Rs.)', _colRate),
          cell('Amount(Rs.)', _colAmount, isLast: true),
        ],
      ),
    );
  }

  static pw.Widget _productRow(int index, BillingItemModel item) {
    final cellStyle = const pw.TextStyle(fontSize: 8);
    final isEven = index.isEven;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: const pw.Border(
          left: pw.BorderSide(color: _borderColor, width: 0.5),
          right: pw.BorderSide(color: _borderColor, width: 0.5),
          bottom: pw.BorderSide(color: _borderColor, width: 0.5),
        ),
        color: isEven ? null : PdfColors.grey100,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _gridCell(
            pw.Text('$index',
                style: pw.TextStyle(
                    fontSize: 8, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
            flex: _colSNo,
          ),
          _gridCell(
            pw.Text(' ${item.productName}', style: cellStyle),
            flex: _colProduct,
          ),
          _gridCell(
            pw.Text('${item.quantity} ${item.unit}',
                style: cellStyle, textAlign: pw.TextAlign.center),
            flex: _colQty,
          ),
          _gridCell(
            pw.Text(_numberFormat.format(item.rate),
                style: cellStyle, textAlign: pw.TextAlign.right),
            flex: _colRate,
          ),
          _gridCell(
            pw.Text(_numberFormat.format(item.amount),
                style: cellStyle, textAlign: pw.TextAlign.right),
            flex: _colAmount,
            isLast: true,
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildProductRows(EstimationModel estimate) {
    final rows = <pw.Widget>[_productHeaderRow()];
    var index = 1;
    for (final item in estimate.items) {
      rows.add(_productRow(index++, item));
    }
    return rows;
  }

  // ---- Compliment Products: separate free-of-charge section -----------
  //
  // Rendered as its own titled section directly under the normal product
  // table, matching the server's `rpt_estimate_a4.php` layout (see the
  // reference PDF). S.No continues on from the paid items so numbering
  // stays sequential across both tables. These rows deliberately carry no
  // Rate/Amount — compliment products are free and must never affect
  // subTotal/roundOff/total (those are computed straight from `items` in
  // EstimationModel and are untouched by this section).

  static pw.Widget _complimentTitleRow() {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _borderColor, width: 0.5),
      ),
      child: pw.Text(
        'Compliment Products',
        style: pw.TextStyle(
            fontSize: 8, fontWeight: pw.FontWeight.bold, color: _greenLabel),
      ),
    );
  }

  static pw.Widget _complimentRow(int index, ComplimentItemModel item) {
    final cellStyle = const pw.TextStyle(fontSize: 8);
    final isEven = index.isEven;

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: const pw.Border(
          left: pw.BorderSide(color: _borderColor, width: 0.5),
          right: pw.BorderSide(color: _borderColor, width: 0.5),
          bottom: pw.BorderSide(color: _borderColor, width: 0.5),
        ),
        color: isEven ? null : PdfColors.grey100,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _gridCell(
            pw.Text('$index',
                style: pw.TextStyle(
                    fontSize: 8, fontWeight: pw.FontWeight.bold),
                textAlign: pw.TextAlign.center),
            flex: _colSNo,
          ),
          _gridCell(
            pw.Text(' ${item.productName}', style: cellStyle),
            flex: _colProduct,
          ),
          _gridCell(
            pw.Text('${item.quantity}',
                style: cellStyle, textAlign: pw.TextAlign.center),
            flex: _colQty,
          ),
          // Rate/Amount columns stay blank — compliment products are free
          // and never contribute to subTotal/roundOff/total.
          _gridCell(pw.SizedBox(), flex: _colRate),
          _gridCell(pw.SizedBox(), flex: _colAmount, isLast: true),
        ],
      ),
    );
  }

  static List<pw.Widget> _buildComplimentRows(EstimationModel estimate) {
    if (estimate.complimentItems.isEmpty) return [];

    final rows = <pw.Widget>[_complimentTitleRow()];
    // S.No continues on from the paid product rows above, matching the
    // reference PDF (paid item #1, then compliment items #2, #3, ...).
    var index = estimate.items.length + 1;
    for (final item in estimate.complimentItems) {
      rows.add(_complimentRow(index++, item));
    }
    return rows;
  }

  // ---- Filler: pad the table down so it "fit to full page" -------------
  //
  // The reference PDF's product/compliment table always stretches down to
  // roughly the same point on the page — the empty space is drawn as one
  // tall bordered block with the same S.No/Product/Qty/Rate/Amount column
  // dividers, not left as blank white space above the totals. A `MultiPage`
  // build() has no way to ask "how much room is left on this page", so
  // this approximates it: budget a fixed height for the item area, subtract
  // what the real rows already used, and fill the remainder with one tall
  // blank row of the same grid. Only kicks in while there's meaningfully
  // more than a row's worth of space left, and is skipped once the item
  // list is long enough that the table would realistically already reach
  // that point (or run onto a second page) on its own.
  static const _tableRowHeight = 14.5;
  static const _tableItemAreaBudget = 380.0;

  static pw.Widget? _buildFiller(EstimationModel estimate) {
    var used = _tableRowHeight + estimate.items.length * _tableRowHeight;
    if (estimate.complimentItems.isNotEmpty) {
      used +=
          _tableRowHeight + estimate.complimentItems.length * _tableRowHeight;
    }
    final fillerHeight = _tableItemAreaBudget - used;
    if (fillerHeight <= _tableRowHeight) return null;
    return _fillerRow(fillerHeight);
  }

  static pw.Widget _fillerCell({required int flex, bool isLast = false}) {
    return pw.Expanded(
      flex: flex,
      child: pw.Container(
        decoration: pw.BoxDecoration(
          border: pw.Border(
            right: isLast
                ? pw.BorderSide.none
                : const pw.BorderSide(color: _borderColor, width: 0.5),
          ),
        ),
      ),
    );
  }

  static pw.Widget _fillerRow(double height) {
    return pw.Container(
      height: height,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: _borderColor, width: 0.5),
          right: pw.BorderSide(color: _borderColor, width: 0.5),
          bottom: pw.BorderSide(color: _borderColor, width: 0.5),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _fillerCell(flex: _colSNo),
          _fillerCell(flex: _colProduct),
          _fillerCell(flex: _colQty),
          _fillerCell(flex: _colRate),
          _fillerCell(flex: _colAmount, isLast: true),
        ],
      ),
    );
  }

  // ---- Totals: per-section add/discount, charges, then summary -------

  static List<pw.Widget> _buildTotals(EstimationModel estimate) {
    final widgets = <pw.Widget>[];

    final sections = [
      (estimate.section1Items, estimate.section1Total, estimate.section1Add,
          estimate.section1Discount),
      (estimate.section2Items, estimate.section2Total, estimate.section2Add,
          estimate.section2Discount),
    ];

    for (final (items, sectionTotal, addValue, discountValue) in sections) {
      if (items.isEmpty) continue;
      widgets.add(_totalRow('Sub Total', sectionTotal));
      if (addValue > 0) widgets.add(_totalRow('Add', addValue));
      if (discountValue > 0) widgets.add(_totalRow('Discount', discountValue));
      if (addValue > 0 || discountValue > 0) {
        widgets.add(
            _totalRow('Total', sectionTotal + addValue - discountValue));
      }
    }

    // Combined summary: Total Quantity (left) + Sub Total (right).
    widgets.add(
      pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Container(
              alignment: pw.Alignment.centerRight,
              padding:
                  const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  left: pw.BorderSide(color: _borderColor, width: 0.5),
                  top: pw.BorderSide(color: _borderColor, width: 0.5),
                  bottom: pw.BorderSide(color: _borderColor, width: 0.5),
                ),
              ),
              child: pw.Text('Total Quantity',
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: _greenLabel)),
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Container(
              alignment: pw.Alignment.center,
              child: pw.Text('${estimate.totalQty} Pcs',
                  style: const pw.TextStyle(fontSize: 8)),
            ),
          ),
          pw.Container(
            width: 90,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            child: pw.Text('Sub Total',
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: _greenLabel)),
          ),
          pw.Container(
            width: 90,
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            child: pw.Text(_numberFormat.format(estimate.subTotal),
                style: const pw.TextStyle(fontSize: 8)),
          ),
        ],
      ),
    );

    // Named charges — e.g. "Packing Charges", "Cash Discount" — shown
    // between the summary row and Round Off, same position as the
    // server report's other_charges rows.
    for (final charge in estimate.charges) {
      if (charge.value == 0) continue;
      final label = charge.value < 0 ? '${charge.name} (-)' : charge.name;
      widgets.add(_totalRow(label, charge.value.abs()));
    }

    widgets.add(_totalRow('Round Off', estimate.roundOff));
    widgets.add(_totalRow('Bill Total', estimate.total, bold: true));

    widgets.add(pw.SizedBox(height: 4));
    widgets.add(
      pw.Container(
        decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _borderColor, width: 0.5)),
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Amount in words : ',
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: _greenLabel)),
            pw.Expanded(
              child: pw.Text(IndianCurrencyWords.convert(estimate.total),
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.Text('E. & O.E', style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );

    return widgets;
  }

  static pw.Widget _totalRow(String label, double value, {bool bold = false}) {
    final style = pw.TextStyle(
      fontSize: 8,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Row(
      children: [
        pw.Expanded(
          child: pw.Container(
            alignment: pw.Alignment.centerRight,
            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            child: pw.Text(label,
                style: style.copyWith(
                    fontWeight: pw.FontWeight.bold, color: _greenLabel)),
          ),
        ),
        pw.Container(
          width: 90,
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _borderColor, width: 0.5)),
          child: pw.Text(_numberFormat.format(value), style: style),
        ),
      ],
    );
  }

  // ---- Declaration + signature ----------------------------------------

  // Shared fixed height for both boxes below — the Declaration box used to
  // size itself purely to its paragraph's natural height while the
  // Signature box was pinned at 45, so the two rarely matched. Giving both
  // the same explicit height keeps them equal regardless of content.
  static const _declarationBoxHeight = 46.0;

  static pw.Widget _buildDeclarationAndSignature(EstimationModel estimate) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 12,
          child: pw.Container(
            height: _declarationBoxHeight,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Declaration : ',
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greenLabel)),
                pw.Text(
                  'We declare that this bill shows the actual price of the '
                  'goods described and that all particulars are true and '
                  'correct.',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ),
        ),
        pw.Expanded(
          flex: 7,
          child: pw.Container(
            height: _declarationBoxHeight,
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _borderColor, width: 0.5)),
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('For ${CompanyProfile.name}',
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: _greenLabel)),
                pw.Text('Authorised Signatory',
                    style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---- Footer -----------------------------------------------------------

  static pw.Widget _buildFooter() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          '*** This is a Computer Generated bill. Hence Digital Signature is not required. ***',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page No : 1',
            style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic),
          ),
        ),
      ],
    );
  }
}