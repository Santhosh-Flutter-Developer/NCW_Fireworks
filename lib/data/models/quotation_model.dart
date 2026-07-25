import 'billing_item_model.dart';

class QuotationModel {
  final String id;
  final String quotationNo;

  /// The real `quotation_id` on the server, once known. `null` for rows
  /// that only exist locally. Sent back as `edit_id` when saving.
  String? serverQuotationId;
  String partyId;
  String partyName;
  String pricelistId;
  String pricelistName;
  DateTime date;
  List<BillingItemModel> items;
  DocStatus status;
  String notes;

  /// Manual add/discount values applied on top of each section's subtotal,
  /// mirroring the "Add:" / "Discount:" fields under Section 1 / Section 2
  /// on the web app's Add Quotation screen.
  double section1Add;
  double section1Discount;
  double section2Add;
  double section2Discount;

  /// `quotation_listing` only returns a grand total and a qty label per
  /// row — not the full line items. When set (list-sourced rows), [total]
  /// and [qtyLabel] read from these instead of recomputing from [items].
  double? serverGrandTotal;
  String? serverQtyLabel;

  /// The linked estimate's id once this quotation has been converted to
  /// an estimate — empty for quotations that haven't been converted yet.
  /// While non-empty, the Convert/Edit/Delete row actions are hidden.
  String estimateId;

  /// True when this row was built from the on-device pending-sync queue
  /// — an add/edit made on this device that hasn't been sent to
  /// `quotation.php` yet. Drives the "Pending sync" badge on the list.
  bool isPending;

  /// The pending-sync queue entry's own id, when [isPending] is true —
  /// used to update/remove that exact entry on a later edit or delete.
  /// Null for a row that came from the synced server cache.
  String? localId;

  /// Whether every field on this row (party/pricelist/items/sections) is
  /// actually known — false only for a row cached before full details
  /// were stored, which needs a `show_quotation_id` fetch before it's
  /// safe to edit (see `QuotationController.startEdit`).
  bool hasFullDetails;

  QuotationModel({
    required this.id,
    required this.quotationNo,
    this.serverQuotationId,
    required this.partyId,
    required this.partyName,
    this.pricelistId = '',
    this.pricelistName = '',
    required this.date,
    required this.items,
    this.status = DocStatus.draft,
    this.notes = '',
    this.section1Add = 0,
    this.section1Discount = 0,
    this.section2Add = 0,
    this.section2Discount = 0,
    this.serverGrandTotal,
    this.serverQtyLabel,
    this.estimateId = '',
    this.isPending = false,
    this.localId,
    this.hasFullDetails = true,
  });

  /// True once this quotation has been converted to an estimate.
  bool get isConverted => estimateId.isNotEmpty;

  List<BillingItemModel> get section1Items =>
      items.where((i) => i.section == 1).toList();
  List<BillingItemModel> get section2Items =>
      items.where((i) => i.section == 2).toList();

  double get section1Total =>
      section1Items.fold(0, (sum, i) => sum + i.amount);
  double get section2Total =>
      section2Items.fold(0, (sum, i) => sum + i.amount);

  double get subTotal => section1Total + section2Total;
  double get adjustments =>
      (section1Add - section1Discount) + (section2Add - section2Discount);

  /// Automatically rounds the pre-round total to the nearest whole rupee —
  /// no manual entry involved. Positive when the total rounds up, negative
  /// when it rounds down.
  double get roundOff {
    final preRound = subTotal + adjustments;
    return double.parse((preRound.roundToDouble() - preRound).toStringAsFixed(2));
  }

  double get total => serverGrandTotal ?? (subTotal + adjustments + roundOff);

  /// Kept for screens/dashboards that only care about the grand total.
  double get grandTotal => total;

  int get totalQty => items.fold(0, (sum, i) => sum + i.quantity);

  /// e.g. "125 Case" — matches the "Bill Qty" column on the web app.
  String get qtyLabel {
    if (serverQtyLabel != null && serverQtyLabel!.isNotEmpty) {
      return serverQtyLabel!;
    }
    if (items.isEmpty) return '0';
    final unit = items.first.unit.isNotEmpty ? items.first.unit : 'Pcs';
    return '$totalQty $unit';
  }
}