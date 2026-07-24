import '../../../core/network/api_exception.dart';
import 'id_name.dart';

/// One row from `receipt_list` in a `receipt_listing` response — or,
/// when [isPending] is true, one row built from the on-device
/// pending-sync queue ([CacheKeys.receiptPending]) instead: a Receipt
/// created against an estimate on this device that hasn't been sent to
/// `receipt.php` yet.
class ReceiptListItem {
  final String receiptId;
  final String receiptNumber;
  final String receiptDate; // yyyy-MM-dd, as stored server-side
  final String agentName;
  final String partyName;
  final double totalAmount;

  /// True for a row sourced from the pending-sync queue rather than the
  /// synced cache — drives the "Pending sync" badge on the list, same as
  /// `EstimateListItem.isPending`.
  final bool isPending;

  /// For a pending row, the queue entry's own id. Empty for a synced row.
  final String localId;

  /// Remarks text and Payment Mode/Bank/Amount rows. For a pending row
  /// these come straight from the queue entry; for a synced row
  /// `receipt_listing` now returns them itself (`narration`,
  /// `payment_mode_data`) so this app can resend a synced receipt's own
  /// original data — unchanged except `cancelled: "1"` — when it's later
  /// cancelled (see `ReceiptRepository.syncPendingReceipts`). `entries`
  /// uses the same `payment_mode_id`/`bank_id`/`amount` shape either way
  /// — `ReceiptRepository.queueReceiptForSync` stores it, and
  /// `ReceiptPaymentEntry.fromJson` parses it back out.
  final String narration;
  final List<Map<String, dynamic>> entries;

  /// The bill (estimate) number this receipt was raised against — echoed
  /// back on cancel as `against_bill_number`. Only ever known for a
  /// synced row; a pending row's own `bill_number` is read separately by
  /// `ReceiptRepository.queueReceiptForSync`'s caller.
  final String billNumber;

  /// Deduction amount, echoed back on cancel as-is.
  final String deduction;

  const ReceiptListItem({
    required this.receiptId,
    required this.receiptNumber,
    required this.receiptDate,
    required this.agentName,
    required this.partyName,
    required this.totalAmount,
    this.isPending = false,
    this.localId = '',
    this.narration = '',
    this.entries = const [],
    this.billNumber = '',
    this.deduction = '',
  });

  factory ReceiptListItem.fromJson(Map<String, dynamic> json) {
    final rawPaymentModeData = json['payment_mode_data'];
    return ReceiptListItem(
      receiptId: json['receipt_id']?.toString() ?? '',
      receiptNumber: json['receipt_number']?.toString() ?? '',
      receiptDate: json['receipt_date']?.toString() ?? '',
      agentName: json['agent_name']?.toString() ?? '',
      partyName: json['party_name']?.toString() ?? '',
      totalAmount: readNum(json['total_amount']),
      narration: json['narration']?.toString() ?? '',
      entries: rawPaymentModeData is List
          ? rawPaymentModeData
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList()
          : const [],
      billNumber: json['against_bill_number']?.toString() ?? '',
      deduction: json['deduction']?.toString() ?? '',
    );
  }

  /// Builds a row from one entry of the pending-sync queue (the same
  /// shape [ReceiptRepository.queueReceiptForSync] writes). `receiptId`
  /// stays empty — the server assigns the real one once this is actually
  /// synced — but `receiptNumber` is the provisional
  /// `ReceiptRepository.nextReceiptNumber()` value generated at creation,
  /// so this shows in the same `RE0xx/FY` shape a synced row would,
  /// rather than the source estimate's own bill number.
  factory ReceiptListItem.fromPendingRow(Map<String, dynamic> row) {
    final rawEntries = row['entries'];
    return ReceiptListItem(
      receiptId: '',
      receiptNumber: row['receipt_number']?.toString() ?? '',
      receiptDate: row['receipt_date_iso']?.toString() ?? '',
      agentName: row['agent_name']?.toString() ?? '',
      partyName: row['party_name']?.toString() ?? '',
      totalAmount: readNum(row['total_amount']),
      isPending: true,
      localId: row['local_id']?.toString() ?? '',
      narration: row['narration']?.toString() ?? '',
      entries: rawEntries is List
          ? rawEntries.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const [],
      billNumber: row['bill_number']?.toString() ?? '',
      deduction: row['deduction']?.toString() ?? '',
    );
  }
}

/// Parses the `{"head": {...}}` envelope returned for a `receipt_listing`
/// call.
///
/// Also carries `party_list` (same `{party_id, party_name}` shape as
/// `quotation_listing`) so the list screen's Party filter dropdown can be
/// populated the same way the Quotation screen's is.
class ReceiptListResponseModel {
  final int code;
  final String message;
  final List<ReceiptListItem> items;
  final List<IdName> partyList;

  /// Total rows matching the current filters, independent of pagination —
  /// derived from the fully-synced local cache (see
  /// `ReceiptRepository._cachedTotalCount`), not from this particular
  /// page's response. Null when there's no synced snapshot yet to count
  /// against, in which case the caller falls back to inferring "is there
  /// a next page" from whether this page came back full.
  final int? totalRecords;

  const ReceiptListResponseModel({
    required this.code,
    required this.message,
    required this.items,
    required this.partyList,
    this.totalRecords,
  });

  bool get isSuccess => code == 200;

  factory ReceiptListResponseModel.fromJson(Map<String, dynamic> json) {
    final head = json['head'];
    if (head is! Map) {
      throw const InvalidResponseException(
        'Server response was missing the expected "head" field.',
      );
    }

    final items = <ReceiptListItem>[];
    final rawList = head['receipt_list'];
    if (rawList is List) {
      for (final row in rawList) {
        if (row is Map) {
          items.add(ReceiptListItem.fromJson(Map<String, dynamic>.from(row)));
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

    return ReceiptListResponseModel(
      code: readCode(head['code']),
      message: readMsg(head['msg']),
      items: items,
      partyList: readIdNameList(head['party_list'], 'party_id', 'party_name'),
    );
  }
}