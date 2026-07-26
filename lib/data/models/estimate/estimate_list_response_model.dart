import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One product line inside an estimate row, used both by a synced row's
/// `_full` cache entry and by a pending-queue row.
class EstimateDetailProductRow {
  final String productId;
  final String productName;
  final String quantity;
  final String unitId;
  final String unitName;
  final String rate;
  final String productDiscount; // "1"/"0" — matches product_discount
  final String amount;

  const EstimateDetailProductRow({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitId,
    required this.unitName,
    required this.rate,
    required this.productDiscount,
    this.amount = '',
  });
}

/// One other-charge line inside an estimate row.
class EstimateDetailChargeRow {
  final String chargeId;
  final String chargeName;
  final String type; // "Plus" or "Minus"
  final String value;

  const EstimateDetailChargeRow({
    required this.chargeId,
    required this.chargeName,
    required this.type,
    required this.value,
  });
}

/// One "Compliment Product" line inside an estimate row — a free/
/// no-charge item added via the form's "+ Add Compliment Products"
/// button (see `EstimationController.addComplimentSelections`), used
/// both by a synced row's `_full` cache entry and by a pending-queue
/// row. Carries no rate/amount — compliment products never affect the
/// estimate's total.
class EstimateDetailComplimentRow {
  final String productId;
  final String productName;
  final String quantity;
  final String unitId;
  final String unitName;

  const EstimateDetailComplimentRow({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unitId = '',
    this.unitName = '',
  });
}

/// One row from `estimate_list` in an `estimate_listing` response — or,
/// when [isPending] is true, one row built from the on-device
/// pending-sync queue ([CacheKeys.estimationPending]) instead.
///
/// `estimate_listing` actually returns every field below per row — party/
/// pricelist/agent ids, the full product line-up, both sections' add/
/// discount values, the charges, and the draft flag — not just the
/// id/number/date/agent/party/qty/total summary this used to parse.
/// [hasFullDetails] is only false for a row cached by an older build of
/// this app that stored just the summary fields; those still need a
/// `show_estimate_id` fetch before they can be edited safely (see
/// `EstimationController.startEdit`). A pending row (built via
/// [fromPendingRow]) always has full details — it was built on this
/// device, nothing to fetch.
class EstimateListItem {
  final String estimateId;
  final String estimateNumber;
  final String estimateDate; // yyyy-MM-dd, as stored server-side
  final String agentNameMobileCity;
  final String partyNameMobileCity;
  final String totalQuantity;
  final double grandTotal;
  final String receiptId;

  /// True for a row sourced from the pending-sync queue rather than the
  /// synced cache — i.e. an add/edit made on this device that hasn't
  /// been sent to the server yet.
  final bool isPending;

  /// For a pending row, the queue entry's own id — used to find/replace
  /// this exact entry later (re-editing before sync, or removing it).
  /// Empty for a synced row.
  final String localId;

  final String partyId;
  final String agentId;
  final String pricelistId;
  final String pricelistName;
  final String convertQuotationId;
  final List<EstimateDetailProductRow> products;
  final String section1AddValue;
  final String section1Discount;
  final String section2AddValue;
  final String section2Discount;
  final List<EstimateDetailChargeRow> charges;
  final bool isDraft;

  /// Free/no-charge "Compliment Products" attached to this estimate —
  /// see `EstimateDetailComplimentRow`. Parsed the same way as
  /// [products]: parallel arrays on a synced row (`compliment_product_id`/
  /// `compliment_product_quantity`, plus name/unit if the server echoes
  /// them), or straight from the pending queue's own `compliment_product_data`
  /// on a not-yet-synced row.
  final List<EstimateDetailComplimentRow> complimentProducts;

  /// True when this is a pending row queuing a Cancel made while offline
  /// (see `EstimationController.deleteEstimation` /
  /// `EstimateRepository.queueEstimateForSync`'s `cancelled` param). Only
  /// ever set on a pending row — a synced row's cancelled state is which
  /// cache tab it's in, not a field on the row itself.
  final bool isCancelled;

  /// Whether every field above is actually known for this row — see the
  /// class doc for when this is false.
  final bool hasFullDetails;

  const EstimateListItem({
    required this.estimateId,
    required this.estimateNumber,
    required this.estimateDate,
    required this.agentNameMobileCity,
    required this.partyNameMobileCity,
    required this.totalQuantity,
    required this.grandTotal,
    this.receiptId = '',
    this.isPending = false,
    this.localId = '',
    this.partyId = '',
    this.agentId = '',
    this.pricelistId = '',
    this.pricelistName = '',
    this.convertQuotationId = '',
    this.products = const [],
    this.section1AddValue = '',
    this.section1Discount = '',
    this.section2AddValue = '',
    this.section2Discount = '',
    this.charges = const [],
    this.isDraft = false,
    this.complimentProducts = const [],
    this.isCancelled = false,
    this.hasFullDetails = false,
  });

  /// `estimate.php` uses the literal string `"N"` as its own database
  /// "not applicable" placeholder wherever a field is empty — a pricelist/
  /// agent/converted-quotation id, or (as three parallel single-element
  /// arrays, `["N"]`/`["Plus"]`/`["0"]`) "no other charges at all". Left
  /// unfiltered, that sentinel gets parsed as if it were a real id and
  /// then faithfully re-sent on every later edit/cancel/sync — e.g. a
  /// phantom "N" charge appearing on an estimate that never had one.
  /// Every id-like field below is read through this so `"N"` is treated
  /// exactly like an empty string, same as the app already treats "".
  static String _orEmpty(dynamic raw) {
    final s = raw?.toString() ?? '';
    return s == 'N' ? '' : s;
  }

  factory EstimateListItem.fromJson(Map<String, dynamic> json) {
    return EstimateListItem(
      estimateId: json['estimate_id']?.toString() ?? '',
      estimateNumber: json['estimate_number']?.toString() ?? '',
      estimateDate: json['estimate_date']?.toString() ?? '',
      agentNameMobileCity: json['agent_name_mobile_city']?.toString() ?? '',
      partyNameMobileCity: json['party_name_mobile_city']?.toString() ?? '',
      totalQuantity: json['total_quantity']?.toString() ?? '',
      grandTotal: readNum(json['grand_total']),
      receiptId: json["receipt_id"]?.toString() ?? '',
      partyId: _orEmpty(json['party_id']),
      agentId: _orEmpty(json['agent_id']),
      pricelistId: _orEmpty(json['pricelist_id']),
      pricelistName: json['pricelist_name']?.toString() ?? '',
      convertQuotationId: _orEmpty(json['convert_quotation_id']),
      products: _readProductRows(json),
      section1AddValue: json['section1_add_value']?.toString() ?? '',
      section1Discount: json['section1_discount']?.toString() ?? '',
      section2AddValue: json['section2_add_value']?.toString() ?? '',
      section2Discount: json['section2_discount']?.toString() ?? '',
      charges: _readChargeRows(json),
      isDraft: json['drafted']?.toString() == '1',
      complimentProducts: _readComplimentRows(json),
      hasFullDetails: json['_full'] == true,
    );
  }

  /// Builds a row from one entry of the pending-sync queue (the same
  /// shape [EstimateRepository.queueEstimateForSync] writes).
  /// [estimateId] here is the row's `edit_id` — the client generates this
  /// (and `estimate_number`) itself now, at creation time, so it's always
  /// populated, even for an estimate not yet sent to the server (see
  /// `EstimationController.save`).
  factory EstimateListItem.fromPendingRow(Map<String, dynamic> row) {
    final rawProducts = row['product_data'];
    final products = <EstimateDetailProductRow>[
      if (rawProducts is List)
        for (final p in rawProducts)
          if (p is Map)
            EstimateDetailProductRow(
              productId: p['product_id']?.toString() ?? '',
              productName: p['product_name']?.toString() ?? '',
              quantity: p['product_quantity']?.toString() ?? '',
              unitId: p['unit_id']?.toString() ?? '',
              unitName: p['unit_name']?.toString() ?? '',
              rate: p['product_rate']?.toString() ?? '',
              productDiscount: p['product_discount']?.toString() ?? '',
            ),
    ];

    final rawCharges = row['charges'];
    final charges = <EstimateDetailChargeRow>[
      if (rawCharges is List)
        for (final c in rawCharges)
          if (c is Map)
            EstimateDetailChargeRow(
              chargeId: c['other_charges_id']?.toString() ?? '',
              chargeName: c['other_charges_name']?.toString() ?? '',
              type: c['other_charges_type']?.toString() ?? 'Plus',
              value: c['other_charges_value']?.toString() ?? '',
            ),
    ];

    final rawCompliments = row['compliment_product_data'];
    final complimentProducts = <EstimateDetailComplimentRow>[
      if (rawCompliments is List)
        for (final c in rawCompliments)
          if (c is Map)
            EstimateDetailComplimentRow(
              productId: c['product_id']?.toString() ?? '',
              productName: c['product_name']?.toString() ?? '',
              quantity: c['product_quantity']?.toString() ?? '',
              unitId: c['unit_id']?.toString() ?? '',
              unitName: c['unit_name']?.toString() ?? '',
            ),
    ];

    return EstimateListItem(
      estimateId: row['edit_id']?.toString() ?? '',
      estimateNumber: row['estimate_number']?.toString() ?? '',
      estimateDate: row['estimate_date']?.toString() ?? '',
      agentNameMobileCity: row['agent_name']?.toString() ?? '',
      partyNameMobileCity: row['party_name']?.toString() ?? '',
      // Set by [ReceiptRepository.markEstimateLocallyConverted] the
      // moment a Receipt is queued against this estimate (even before
      // either side has actually synced), so `isConverted` flips — and
      // the Receipt/Edit icons hide — immediately, offline included.
      receiptId: row['receipt_id']?.toString() ?? '',
      totalQuantity: products
          .fold<int>(0, (sum, p) => sum + (int.tryParse(p.quantity) ?? 0))
          .toString(),
      grandTotal: 0, // Recomputed by the form from its own line items.
      isPending: true,
      localId: row['local_id']?.toString() ?? '',
      partyId: row['party_id']?.toString() ?? '',
      agentId: row['agent_id']?.toString() ?? '',
      pricelistId: row['pricelist_id']?.toString() ?? '',
      pricelistName: row['pricelist_name']?.toString() ?? '',
      convertQuotationId: row['convert_quotation_id']?.toString() ?? '',
      products: products,
      section1AddValue: row['section1_add_value']?.toString() ?? '',
      section1Discount: row['section1_discount']?.toString() ?? '',
      section2AddValue: row['section2_add_value']?.toString() ?? '',
      section2Discount: row['section2_discount']?.toString() ?? '',
      charges: charges,
      isDraft: row['drafted']?.toString() == '1',
      complimentProducts: complimentProducts,
      isCancelled: row['cancelled']?.toString() == '1',
      hasFullDetails: true,
    );
  }

  static List<EstimateDetailProductRow> _readProductRows(
      Map<String, dynamic> json) {
    final productIds = readStringList(json['product_id']);
    final productNames = readStringList(json['product_name']);
    final productQty = readStringList(json['product_quantity']);
    final unitIds = readStringList(json['unit_id']);
    final unitNames = readStringList(json['unit_name']);
    final rates = readStringList(json['product_rate']);
    final discountFlags = readStringList(json['product_discount']);
    final amounts = readStringList(json['product_amount']);

    String at(List<String> l, int i) => i < l.length ? l[i] : '';

    return [
      for (var i = 0; i < productIds.length; i++)
        if (productIds[i].isNotEmpty)
          EstimateDetailProductRow(
            productId: productIds[i],
            productName: at(productNames, i),
            quantity: at(productQty, i),
            unitId: at(unitIds, i),
            unitName: at(unitNames, i),
            rate: at(rates, i),
            productDiscount: at(discountFlags, i),
            amount: at(amounts, i),
          ),
    ];
  }

  static List<EstimateDetailChargeRow> _readChargeRows(
      Map<String, dynamic> json) {
    final chargeIds = readStringList(json['other_charges_id']);
    final chargeNames = readStringList(json['other_charges_name']);
    final chargeTypes = readStringList(json['other_charges_type']);
    final chargeValues = readStringList(json['other_charges_value']);

    String at(List<String> l, int i) => i < l.length ? l[i] : '';

    return [
      for (var i = 0; i < chargeIds.length; i++)
        // "N" is estimate.php's own placeholder for "no charge on this
        // row at all" (see [_orEmpty]) — not a real other_charges_id, so
        // it must never be kept as if the estimate actually had a charge.
        if (chargeIds[i].isNotEmpty && chargeIds[i] != 'N')
          EstimateDetailChargeRow(
            chargeId: chargeIds[i],
            chargeName: at(chargeNames, i),
            type: at(chargeTypes, i),
            value: at(chargeValues, i),
          ),
    ];
  }

  /// Reads `compliment_product_id`/`compliment_product_quantity` (plus
  /// `compliment_product_name`/`compliment_unit_id`/
  /// `compliment_unit_name`, if the server echoes them back the same way
  /// it does for [products]) off a synced `estimate_listing` row. Missing
  /// name/unit arrays just leave those fields blank rather than failing
  /// — `compliment_product_id`/`compliment_product_quantity` are the
  /// only two fields this feature actually round-trips through the
  /// server (see `EstimateRepository.syncPendingEstimates`).
  static List<EstimateDetailComplimentRow> _readComplimentRows(
      Map<String, dynamic> json) {
    final productIds = readStringList(json['compliment_product_id']);
    final productNames = readStringList(json['compliment_product_name']);
    final productQty = readStringList(json['compliment_product_quantity']);
    final unitIds = readStringList(json['compliment_unit_id']);
    final unitNames = readStringList(json['compliment_unit_name']);

    String at(List<String> l, int i) => i < l.length ? l[i] : '';

    return [
      for (var i = 0; i < productIds.length; i++)
        // "N" is estimate.php's own placeholder for "nothing here" (see
        // [_orEmpty]) — not a real product id.
        if (productIds[i].isNotEmpty && productIds[i] != 'N')
          EstimateDetailComplimentRow(
            productId: productIds[i],
            productName: at(productNames, i),
            quantity: at(productQty, i),
            unitId: at(unitIds, i),
            unitName: at(unitNames, i),
          ),
    ];
  }
}

/// Parses the `{"head": {...}}` envelope returned for an `estimate_listing`
/// call.
class EstimateListResponseModel {
  final int code;
  final String message;
  final List<EstimateListItem> items;
  final List<IdName> agentList;
  final List<IdName> partyList;

  /// Total rows matching the current filters, independent of pagination —
  /// derived from the fully-synced local cache (see
  /// `EstimateRepository._cachedTotalCount`), not from this particular
  /// page's response. Null when there's no synced snapshot yet to count
  /// against, in which case the caller falls back to inferring "is there
  /// a next page" from whether this page came back full.
  final int? totalRecords;

  const EstimateListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    required this.agentList,
    required this.partyList,
    this.totalRecords,
  });

  bool get isSuccess => code == 200;

  factory EstimateListResponseModel.fromJson(Map<String, dynamic> json) {
    final head = json['head'];
    if (head is! Map) {
      throw const InvalidResponseException(
        'Server response was missing the expected "head" field.',
      );
    }

    final rawCode = head['code'];
    final code = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;

    final rawMsg = head['msg'];
    final message = (rawMsg is String && rawMsg.trim().isNotEmpty)
        ? rawMsg.trim()
        : 'Unexpected response from server.';

    final items = <EstimateListItem>[];
    final rawList = head['estimate_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          items.add(EstimateListItem.fromJson(Map<String, dynamic>.from(row)));
        }
      }
    }

    List<IdName> readIdNameList(dynamic raw, String idKey, String nameKey) {
      final out = <IdName>[];
      if (raw is List) {
        for (final row in raw) {
          if (row is Map) {
            final m = Map<String, dynamic>.from(row);
            out.add(IdName(
              id: m[idKey]?.toString() ?? '',
              name: m[nameKey]?.toString() ?? '',
            ));
          }
        }
      }
      return out;
    }

    return EstimateListResponseModel(
      code: code,
      message: message,
      items: items,
      agentList: readIdNameList(head['agent_list'], 'agent_id', 'agent_name'),
      partyList: readIdNameList(head['party_list'], 'party_id', 'party_name'),
    );
  }
}