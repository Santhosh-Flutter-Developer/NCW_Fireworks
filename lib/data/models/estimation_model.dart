import 'billing_item_model.dart';

/// A single named charge/deduction line — e.g. "Packing Charges",
/// "Cash Discount", "Tax Amount" — added via the "Charges: Select / Value / +"
/// row on the web app's Add Estimate screen. [value] can be negative for
/// deduction-style charges like Cash Discount.
class ChargeLine {
  String name;
  double value;

  /// The server's `other_charges_id`, when this line came from (or was
  /// matched against) the API's other-charges list. Required to send the
  /// line back on `estimate_update`.
  String chargeId;

  /// "Plus" or "Minus", as looked up from `type_other_charges_id`. Kept
  /// alongside the already-signed [value] so the exact server value can
  /// be resent verbatim.
  String type;

  ChargeLine({
    required this.name,
    required this.value,
    this.chargeId = '',
    this.type = 'Plus',
  });
}

class EstimationModel {
  final String id;
  final String estimationNo;

  /// The real `estimate_id` on the server, once known. `null` for rows
  /// that only exist locally. Sent back as `edit_id` when saving.
  String? serverEstimateId;
  String partyId;
  String partyName;
  String agentId;
  String agentName;
  String pricelistId;
  String pricelistName;
  DateTime date;
  List<BillingItemModel> items;
  DocStatus status;
  String notes;

  /// Manual add/discount values applied on top of each section's subtotal,
  /// mirroring the "Add:" / "Discount:" fields under Section 1 / Section 2
  /// on the web app's Add Estimate screen.
  double section1Add;
  double section1Discount;
  double section2Add;
  double section2Discount;

  /// Named charges stacked on top of the subtotal — "Charges" row.
  List<ChargeLine> charges;

  /// `estimate_listing` only returns a grand total and a qty label per
  /// row — not the full line items. When set (list-sourced rows), [total]
  /// and [qtyLabel] read from these instead of recomputing from [items].
  double? serverGrandTotal;
  String? serverQtyLabel;

  String receiptId;

  /// The source quotation's id when this estimate was created via
  /// "Convert to Estimate" — sent back as `convert_quotation_id` on save.
  /// Empty otherwise.
  String convertQuotationId;

  /// True when this row was built from the on-device pending-sync queue
  /// — an add/edit made on this device that hasn't been sent to
  /// `estimate.php` yet. Drives the "Pending sync" badge on the list.
  bool isPending;

  /// The pending-sync queue entry's own id, when [isPending] is true —
  /// used to update/remove that exact entry on a later edit or delete.
  /// Null for a row that came from the synced server cache.
  String? localId;

  /// Whether every field on this row (party/pricelist/agent/items/
  /// sections/charges) is actually known — false only for a row cached
  /// before full details were stored, which needs a `show_estimate_id`
  /// fetch before it's safe to edit (see `EstimationController.startEdit`).
  bool hasFullDetails;

  EstimationModel({
    required this.id,
    required this.estimationNo,
    this.serverEstimateId,
    required this.partyId,
    required this.partyName,
    this.agentId = '',
    this.agentName = 'Direct',
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
    List<ChargeLine>? charges,
    this.serverGrandTotal,
    this.serverQtyLabel,
    this.receiptId = "",
    this.convertQuotationId = '',
    this.isPending = false,
    this.localId,
    this.hasFullDetails = true,
  }) : charges = charges ?? [];

  bool get isConverted => receiptId.isNotEmpty;

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
  double get chargesTotal => charges.fold(0, (sum, c) => sum + c.value);

  /// Automatically rounds the pre-round total to the nearest whole rupee —
  /// no manual entry involved. Positive when the total rounds up, negative
  /// when it rounds down.
  double get roundOff {
    final preRound = subTotal + adjustments + chargesTotal;
    return double.parse((preRound.roundToDouble() - preRound).toStringAsFixed(2));
  }

  double get total =>
      serverGrandTotal ?? (subTotal + adjustments + chargesTotal + roundOff);

  /// Kept for screens/dashboards that only care about the grand total.
  double get grandTotal => total;

  int get totalQty => items.fold(0, (sum, i) => sum + i.quantity);

  /// e.g. "6 Case" — matches the "Bill Qty" column on the web app.
  String get qtyLabel {
    if (serverQtyLabel != null && serverQtyLabel!.isNotEmpty) {
      return serverQtyLabel!;
    }
    if (items.isEmpty) return '0';
    final unit = items.first.unit.isNotEmpty ? items.first.unit : 'Pcs';
    return '$totalQty $unit';
  }
}