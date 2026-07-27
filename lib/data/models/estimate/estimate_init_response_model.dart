import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One product row inside an existing estimate, as returned by
/// `show_estimate_id`. Only present when editing (`edit_id` was set).
class EstimateDetailProductRow {
  final String productId;
  final String productName;
  final String quantity;
  final String unitId;
  final String unitName;
  final String rate;

  /// `1` when this product's pricelist entry has the discount flag set —
  /// matches the server's own rule for which totals section (1 or 2) the
  /// line belongs to (see estimate.php's `product_discount` handling).
  final String productDiscount;
  final String amount;

  const EstimateDetailProductRow({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitId,
    required this.unitName,
    required this.rate,
    required this.productDiscount,
    required this.amount,
  });
}

/// One other-charge row inside an existing estimate.
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

/// The existing estimate's header + line data, present when `show_estimate_id`
/// was called with a real id. All the "select"-style fields (agent/party/
/// pricelist) come through as *ids*, ready to match against [agentList] /
/// [partyList] / [pricelistList].
class EstimateDetail {
  final String estimateDate; // dd-MM-yyyy, as sent by the server
  final String agentId;
  final String partyId;
  final String pricelistId;
  final List<EstimateDetailProductRow> products;
  final String section1AddValue;
  final String section1Discount;
  final String section2AddValue;
  final String section2Discount;
  final List<EstimateDetailChargeRow> charges;
  final bool drafted;

  const EstimateDetail({
    required this.estimateDate,
    required this.agentId,
    required this.partyId,
    required this.pricelistId,
    required this.products,
    required this.section1AddValue,
    required this.section1Discount,
    required this.section2AddValue,
    required this.section2Discount,
    required this.charges,
    required this.drafted,
  });

  factory EstimateDetail.fromJson(Map<String, dynamic> json) {
    final productIds = readStringList(json['product_id']);
    final productNames = readStringList(json['product_name']);
    final productQty = readStringList(json['product_quantity']);
    final unitIds = readStringList(json['unit_id']);
    final unitNames = readStringList(json['unit_name']);
    final rates = readStringList(json['product_rate']);
    final discountFlags = readStringList(json['product_discount']);
    final amounts = readStringList(json['product_amount']);

    String at(List<String> l, int i) => i < l.length ? l[i] : '';

    final products = <EstimateDetailProductRow>[
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

    final chargeIds = readStringList(json['other_charges_id']);
    final chargeNames = readStringList(json['other_charges_name']);
    final chargeTypes = readStringList(json['other_charges_type']);
    final chargeValues = readStringList(json['other_charges_value']);

    final charges = <EstimateDetailChargeRow>[
      for (var i = 0; i < chargeIds.length; i++)
        if (chargeIds[i].isNotEmpty)
          EstimateDetailChargeRow(
            chargeId: chargeIds[i],
            chargeName: at(chargeNames, i),
            type: at(chargeTypes, i),
            value: at(chargeValues, i),
          ),
    ];

    return EstimateDetail(
      estimateDate: json['estimate_date']?.toString() ?? '',
      agentId: json['agent_id']?.toString() ?? '',
      partyId: json['party_id']?.toString() ?? '',
      pricelistId: json['pricelist_id']?.toString() ?? '',
      products: products,
      section1AddValue: json['section1_add_value']?.toString() ?? '',
      section1Discount: json['section1_discount']?.toString() ?? '',
      section2AddValue: json['section2_add_value']?.toString() ?? '',
      section2Discount: json['section2_discount']?.toString() ?? '',
      charges: charges,
      drafted: json['drafted']?.toString() == '1',
    );
  }

  /// True once real line data has come back — i.e. this was an edit, not a
  /// blank "new estimate" shell.
  bool get hasData => products.isNotEmpty || partyId.isNotEmpty;
}

/// Parses the `{"head": {...}}` envelope returned by `show_estimate_id`.
/// Called with an empty id to bootstrap the *Add* form (dropdown data
/// only) and with a real `estimate_id` to bootstrap the *Edit* form
/// (dropdown data + [detail]).
class EstimateInitResponseModel {
  final int code;
  final String message;
  final EstimateDetail? detail;
  final List<IdName> pricelist;
  final List<IdName> agentList;
  final List<IdName> partyList;
  final List<ChargeOption> otherCharges;

  const EstimateInitResponseModel({
    required this.code,
    required this.message,
    required this.detail,
    required this.pricelist,
    required this.agentList,
    required this.partyList,
    required this.otherCharges,
  });

  bool get isSuccess => code == 200;

  factory EstimateInitResponseModel.fromJson(Map<String, dynamic> json) {
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

    EstimateDetail? detail;
    final rawEstimateList = head['estimate_list'];
    if (rawEstimateList is List && rawEstimateList.isNotEmpty) {
      final row = rawEstimateList.first;
      if (row is Map) {
        final parsed =
            EstimateDetail.fromJson(Map<String, dynamic>.from(row));
        if (parsed.hasData) detail = parsed;
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

    // `other_charges` rows carry their own fixed "Plus"/"Minus" sign as
    // `charges_type` — read directly here so the sign is known the
    // moment the dropdown is populated, with no separate
    // `type_other_charges_id` call needed.
    List<ChargeOption> readChargeOptionList(dynamic raw) {
      final out = <ChargeOption>[];
      if (raw is List) {
        for (final row in raw) {
          if (row is Map) {
            final m = Map<String, dynamic>.from(row);
            out.add(ChargeOption(
              id: m['other_charges_id']?.toString() ?? '',
              name: m['other_charges_name']?.toString() ?? '',
              type: m['charges_type']?.toString() ?? 'Plus',
            ));
          }
        }
      }
      return out;
    }

    return EstimateInitResponseModel(
      code: code,
      message: message,
      detail: detail,
      pricelist: readIdNameList(
          head['pricelist'], 'pricelist_id', 'pricelist_name'),
      agentList:
          readIdNameList(head['agent_list'], 'agent_id', 'agent_name'),
      partyList:
          readIdNameList(head['party_list'], 'party_id', 'party_name'),
      otherCharges: readChargeOptionList(head['other_charges']),
    );
  }
}