import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/receipt/id_name.dart';
import '../models/receipt/receipt_balance_response_model.dart';
import '../models/receipt/receipt_bank_response_model.dart';
import '../models/receipt/receipt_bill_lookup_response_model.dart';
import '../models/receipt/receipt_form_init_response_model.dart';
import '../models/receipt/receipt_list_response_model.dart';
import '../models/receipt/receipt_save_response_model.dart';

/// One payment-mode/bank/amount line, as sent inside the parallel
/// `payment_mode_id` / `bank_id` / `amount` arrays on `receipt_update`.
class ReceiptPaymentEntry {
  final String paymentModeId;

  /// Sent verbatim, including `""` for cash-style modes — the server
  /// expects one array slot per payment line either way (see the
  /// Postman example: `bank_id: ["", "<real id>"]`).
  final String bankId;
  final String amount;

  const ReceiptPaymentEntry({
    required this.paymentModeId,
    required this.bankId,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'payment_mode_id': paymentModeId,
        'bank_id': bankId,
        'amount': amount,
      };

  factory ReceiptPaymentEntry.fromJson(Map<String, dynamic> json) =>
      ReceiptPaymentEntry(
        paymentModeId: json['payment_mode_id']?.toString() ?? '',
        bankId: json['bank_id']?.toString() ?? '',
        amount: json['amount']?.toString() ?? '',
      );
}

/// Talks to `receipt.php`. Every method either returns a successful,
/// validated result or throws a typed [ApiException] — callers never need
/// to inspect raw response maps.
class ReceiptRepository {
  ReceiptRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// The `YY-YY` financial-year suffix `receipt_number` gets appended
  /// with — same convention as `EstimateRepository._financialYearSuffix`.
  static String _financialYearSuffix(DateTime date) {
    final startYear = date.month >= 4 ? date.year : date.year - 1;
    String two(int y) => (y % 100).toString().padLeft(2, '0');
    return '${two(startYear)}-${two(startYear + 1)}';
  }

  /// Builds a *provisional* receipt number for a Receipt created
  /// offline: `<billPrefix> - RE<seq>/<FY>` — matching the
  /// `"AKB - RE025/26-27"` shape the real `receipt_data` payload uses,
  /// continuing the highest sequence already used this financial year
  /// across every cached tab (Active/Cancel) and anything still pending
  /// sync, regardless of whether those numbers carry a prefix (older
  /// synced rows on this device may not).
  ///
  /// This is provisional, not reserved: the server is the one that
  /// actually creates the receipt once this syncs, so in principle it
  /// could assign something else — but since `receipt_number` is now a
  /// client-supplied field on `receipt_data` (see
  /// `ReceiptRepository.syncPendingReceipts`), what's generated here is
  /// what actually gets sent and, barring a rejection, what the receipt
  /// keeps.
  String nextReceiptNumber({required String billPrefix}) {
    final fy = _financialYearSuffix(DateTime.now());
    final pattern =
        RegExp('RE(\\d+)/${RegExp.escape(fy)}\$', caseSensitive: false);

    var maxSeq = 0;
    void scan(Iterable<Map<String, dynamic>> rows, String key) {
      for (final row in rows) {
        final number = row[key]?.toString() ?? '';
        final match = pattern.firstMatch(number);
        if (match != null) {
          final seq = int.tryParse(match.group(1)!) ?? 0;
          if (seq > maxSeq) maxSeq = seq;
        }
      }
    }

    scan(_cache.getJsonList(CacheKeys.receiptActive), 'receipt_number');
    scan(_cache.getJsonList(CacheKeys.receiptCancel), 'receipt_number');
    scan(_cache.getJsonList(CacheKeys.receiptPending), 'receipt_number');

    final next = (maxSeq + 1).toString().padLeft(3, '0');
    final prefix = billPrefix.trim();
    return prefix.isEmpty ? 'RE$next/$fy' : '$prefix - RE$next/$fy';
  }

  /// Payment Mode dropdown options for the Add Receipt form — refreshed
  /// once at login and via the Sync button (see
  /// `DataSyncService._syncReceiptCatalogue`), read here with no network
  /// call. Mirrors `EstimateRepository.cachedPricelists`.
  List<IdName> cachedPaymentModes() => _cache
      .getJsonList(CacheKeys.receiptPaymentModes)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Banks linked to [paymentModeId], from the full payment-mode → bank
  /// catalogue cached at login/Sync — backs the Add Receipt form's Bank
  /// dropdown with no network call. An empty list means this mode is
  /// cash-style, same meaning as an empty [ReceiptBankResponseModel.banks].
  List<IdName> cachedBanksForPaymentMode(String paymentModeId) => _cache
      .getJsonList(CacheKeys.receiptBanks)
      .where((m) => m['payment_mode_id']?.toString() == paymentModeId)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Looks up a payment mode's display name by id from the same cached
  /// catalogue [cachedPaymentModes] reads — needed because a queued
  /// receipt's `entries` (see [queueReceiptForSync]) only stores
  /// `payment_mode_id`/`bank_id`, not the names, to keep that cached row
  /// a plain id/amount record. Used by `ReceiptController` to rebuild the
  /// Payment Mode line for the offline PDF (see `ReceiptPdfBuilder`).
  /// Returns the id itself if the mode isn't found in the cache (e.g. an
  /// older cache from before a Sync), so the report still shows *something*
  /// rather than a blank.
  String cachedPaymentModeName(String paymentModeId) {
    if (paymentModeId.isEmpty) return '';
    for (final m in _cache.getJsonList(CacheKeys.receiptPaymentModes)) {
      if (m['id']?.toString() == paymentModeId) {
        return m['name']?.toString() ?? paymentModeId;
      }
    }
    return paymentModeId;
  }

  /// Same as [cachedPaymentModeName] but for a bank id, searched across
  /// every payment mode's banks (not just one), since a queued entry only
  /// has the bank id on its own.
  String cachedBankName(String bankId) {
    if (bankId.isEmpty) return '';
    for (final m in _cache.getJsonList(CacheKeys.receiptBanks)) {
      if (m['id']?.toString() == bankId) {
        return m['name']?.toString() ?? bankId;
      }
    }
    return bankId;
  }

  /// Bootstraps the Add Receipt form: today's default receipt date plus
  /// the Payment Mode dropdown options. Only called now as a one-time
  /// backward-compat fallback and by [DataSyncService] to refresh
  /// [cachedPaymentModes] — the normal Add Receipt flow reads
  /// [cachedPaymentModes] directly and never touches the network. There's
  /// no "load an existing receipt" mode — Receipts are create-or-delete
  /// only.
  Future<ReceiptFormInitResponseModel> getFormInitData() async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'show_receipt_id': ''},
    );

    final result = ReceiptFormInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Banks linked to a chosen payment mode, for the Bank dropdown. An
  /// empty list back (still `code == 200`) means this mode is cash-style
  /// and has no bank of its own — see [ReceiptBankResponseModel].
  Future<ReceiptBankResponseModel> getBanksForPaymentMode(
    String paymentModeId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'selected_bank_payment_mode': paymentModeId},
    );

    final result = ReceiptBankResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Looks up an active bill (estimate) by its printed number, for the
  /// "Bill Number" field on Billwise Payment. Only called now as a
  /// one-time backward-compat fallback — the Add Receipt form's Bill
  /// Number field is read-only and only ever prefilled from the Estimate
  /// list's Receipt icon (`EstimationController.payReceipt`), which
  /// always knows the source estimate's own id and so uses
  /// [lookupBillByEstimateId] instead, entirely offline. Throws with the
  /// server's own message (`"Empty Estimate"` / `"Invalid Estimate"`)
  /// when not found.
  Future<ReceiptBillLookupResponseModel> lookupBill(String billNumber) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'payment_bill_number': billNumber},
    );

    final result = ReceiptBillLookupResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  static String _stripHtml(String raw) => raw.replaceAll(RegExp(r'<[^>]*>'), '');

  /// Finds [estimateId] in the same estimation cache the Estimate list
  /// itself reads (Active tab, plus anything still only sitting in the
  /// estimate pending-sync queue, matched by that queue entry's own
  /// `local_id` — the same id `EstimationModel.id` exposes for a
  /// not-yet-synced row — since an estimate created offline and not yet
  /// synced can still be paid against) and returns its party/total,
  /// entirely offline. This is what backs the read-only Bill Number field
  /// on Add Receipt now — no network call, no dependency on
  /// `EstimateRepository` itself, just the shared cache keys both
  /// repositories already agree on.
  ///
  /// Throws [ApiRequestException] with the same wording the server would
  /// use (`"Invalid Estimate"`) if the id isn't found in either place —
  /// e.g. a very stale cache from before the estimate was last synced.
  ReceiptBillLookupResponseModel lookupBillByEstimateId(String estimateId) {
    Map<String, dynamic>? findIn(String cacheKey, String idKey) {
      for (final row in _cache.getJsonList(cacheKey)) {
        if (row[idKey]?.toString() == estimateId) return row;
      }
      return null;
    }

    final row = findIn(CacheKeys.estimationActive, 'estimate_id') ??
        findIn(CacheKeys.estimationPending, 'local_id');

    if (row == null) {
      throw const ApiRequestException('Invalid Estimate');
    }

    final party = _stripHtml(row['party_name_mobile_city']?.toString() ??
            row['party_name']?.toString() ??
            '')
        .trim();

    // A synced row carries the server's own `grand_total`; a
    // not-yet-synced pending row doesn't have one yet (see
    // `EstimateListItem.fromPendingRow`'s `grandTotal: 0` comment) — the
    // form only needs a total to show/validate against, so recompute it
    // from the pending row's own product/section/charge fields the same
    // way `EstimationModel.total` would.
    double total;
    final rawGrandTotal = row['grand_total'];
    if (rawGrandTotal != null && double.tryParse(rawGrandTotal.toString()) != null &&
        double.parse(rawGrandTotal.toString()) != 0) {
      total = double.parse(rawGrandTotal.toString());
    } else {
      total = _recomputePendingEstimateTotal(row);
    }

    return ReceiptBillLookupResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      estimateNumber: row['estimate_number']?.toString() ?? '',
      party: party.isEmpty ? 'Direct' : party,
      totalAmount: total,
    );
  }

  /// Best-effort grand-total recompute for a pending (not-yet-synced)
  /// estimate row — product line amounts plus both sections'
  /// add/discount plus charges, mirroring `EstimationModel.total`.
  double _recomputePendingEstimateTotal(Map<String, dynamic> row) {
    double subTotal = 0;
    final rawProducts = row['product_data'];
    if (rawProducts is List) {
      for (final p in rawProducts) {
        if (p is Map) {
          final qty = double.tryParse(p['product_quantity']?.toString() ?? '') ?? 0;
          final rate = double.tryParse(p['product_rate']?.toString() ?? '') ?? 0;
          subTotal += qty * rate;
        }
      }
    }
    double section1Add = double.tryParse(row['section1_add_value']?.toString() ?? '') ?? 0;
    double section1Discount = double.tryParse(row['section1_discount']?.toString() ?? '') ?? 0;
    double section2Add = double.tryParse(row['section2_add_value']?.toString() ?? '') ?? 0;
    double section2Discount = double.tryParse(row['section2_discount']?.toString() ?? '') ?? 0;
    double chargesTotal = 0;
    final rawCharges = row['charges'];
    if (rawCharges is List) {
      for (final c in rawCharges) {
        if (c is Map) {
          final value = double.tryParse(c['other_charges_value']?.toString() ?? '') ?? 0;
          final isMinus = c['other_charges_type']?.toString() == 'Minus';
          chargesTotal += isMinus ? -value.abs() : value.abs();
        }
      }
    }
    return subTotal +
        (section1Add - section1Discount) +
        (section2Add - section2Discount) +
        chargesTotal;
  }

  /// Current balance for a chosen payment mode/bank/account — the
  /// "Account Balance : ..." helper text shown next to the Amount field.
  Future<ReceiptBalanceResponseModel> getAccountBalance(
    String accountBalanceId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'account_balance_id': accountBalanceId},
    );

    final result = ReceiptBalanceResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Returns a page of the Receipt list — always from the offline cache
  /// that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// [cancelled] selects which tab's rows come back (Receipts have no
  /// Draft tab, just Active/Cancel) — pass `'1'`/`'0'` explicitly, same
  /// as the cache is stored per-tab.
  ///
  /// The only thing that ever calls the live `receipt_listing` endpoint
  /// is a manual tap of the Sync button (`DataSyncService.syncAllData`),
  /// which fetches the full, unpaginated list for both tabs. Browsing the
  /// list itself never hits the network — this keeps behavior identical
  /// online and offline and means a flaky connection can never cause a
  /// half-loaded list or an unexpectedly slow screen while just looking
  /// at data.
  Future<ReceiptListResponseModel> listReceipts({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    String cancelled = '0',
    int? pageNumber,
    int? pageLimit,
  }) async {
    return _receiptsFromCache(
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterPartyId: filterPartyId,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `receipt_listing` endpoint directly, no cache
  /// fallback. This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [listReceipts] reads from. Throws on failure exactly like any other
  /// API call here; [DataSyncService] is what catches and reports it.
  Future<ReceiptListResponseModel> fetchLiveReceipts({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterPartyId = '',
    String cancelled = '0',
    int? pageNumber,
    int? pageLimit,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {
        'receipt_listing': '1',
        'filter_from_date': filterFromDate,
        'filter_to_date': filterToDate,
        'search_text': searchText,
        'filter_party_id': filterPartyId,
        'cancelled': cancelled,
        if (pageNumber != null) 'page_number': pageNumber.toString(),
        if (pageLimit != null) 'page_limit': pageLimit.toString(),
      },
    );

    final result = ReceiptListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// [cancelled] picks which cached tab snapshot to read from —
  /// [DataSyncService] stores Active/Cancel separately (Receipts have no
  /// Draft tab), the same split the server's `cancelled` flag produces.
  /// Returns every cached row matching the given filters, unpaginated —
  /// merged with anything still sitting in the receipt pending-sync
  /// queue whose own `cancelled` flag matches: a fresh not-yet-synced
  /// Receipt shows under Active, and one cancelled before it ever synced
  /// (see [cancelPendingReceipt]) shows under Cancel — same tab split a
  /// synced row would end up in either way.
  List<ReceiptListItem> _filterCachedReceipts({
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
  }) {
    final cacheKey =
        cancelled == '1' ? CacheKeys.receiptCancel : CacheKeys.receiptActive;

    final pendingAll = _cache.getJsonList(CacheKeys.receiptPending);

    final pending = pendingAll
        .where((row) => (row['cancelled']?.toString() ?? '0') == cancelled)
        .map(ReceiptListItem.fromPendingRow)
        .toList()
        .reversed
        .toList();

    // A pending cancel *of an already-synced receipt* (see
    // `ReceiptController.deleteReceipt`'s synced branch —
    // `queueReceiptForSync(knownToServer: true, editId: receipt.id, ...)`)
    // has a real `edit_id` matching a row already sitting in the synced
    // cache — without this, that same receipt would show under both
    // Active (its stale synced copy) and Cancel (the new pending row)
    // until the next sync catches up. Mirrors
    // `EstimateRepository._filterCachedEstimates`'s `supersededIds`.
    final supersededIds = pendingAll
        .map((row) => row['edit_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    final synced = _cache
        .getJsonList(cacheKey)
        .map(ReceiptListItem.fromJson)
        .where((r) => !supersededIds.contains(r.receiptId))
        .toList();

    final all = [...pending, ...synced];

    final partyList = _cache
        .getJsonList(CacheKeys.receiptParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    String? nameForId(List<IdName> options, String id) {
      for (final o in options) {
        if (o.id == id) return o.name;
      }
      return null;
    }

    final partyName =
        filterPartyId.isEmpty ? null : nameForId(partyList, filterPartyId);

    return all.where((r) {
      if (!matchesDateRange(r.receiptDate, filterFromDate, filterToDate)) {
        return false;
      }
      if (partyName != null &&
          !r.partyName.toLowerCase().contains(partyName.toLowerCase())) {
        return false;
      }
      return matchesSearch(searchText, [
        r.receiptNumber,
        r.partyName,
        r.agentName,
      ]);
    }).toList();
  }

  ReceiptListResponseModel _receiptsFromCache({
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterPartyId,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final filtered = _filterCachedReceipts(
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterPartyId: filterPartyId,
    );

    final partyList = _cache
        .getJsonList(CacheKeys.receiptParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    return ReceiptListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      partyList: partyList,
      totalRecords: filtered.length,
    );
  }

  // NOTE: `receipt.php`'s `receipt_update` action doesn't take a single
  // receipt's fields at the top level — it always takes a `receipt_data`
  // array, even for one row (see [syncPendingReceipts] below, which is
  // the only thing that ever calls it). There's deliberately no
  // single-receipt equivalent of this method.

  /// Queues a new Billwise Payment receipt on this device instead of
  /// calling `receipt.php` directly — the same offline-first shape every
  /// other "Add/Edit" flow in the app uses (see
  /// `EstimateRepository.queueEstimateForSync`). Only a manual tap of the
  /// Sync button ever actually sends this to the server (see
  /// [syncPendingReceipts]).
  ///
  /// [estimateId] is the source estimate's own id (see
  /// `EstimationController.payReceipt`) — stored purely so
  /// [markEstimateLocallyConverted] and [reapplyPendingConversions] know
  /// which estimate row to flip `isConverted` on; it's never sent to
  /// `receipt.php` itself.
  ///
  /// [editId] is what's actually sent to the server as `edit_id` in the
  /// `receipt_data` batch (see [syncPendingReceipts]) — for a brand-new
  /// receipt this is freshly generated and doubles as [localId], the
  /// same one-id-does-both-jobs convention `EstimationController.save`
  /// uses for a new estimate. To cancel a receipt the server already
  /// knows about (see `ReceiptController.deleteReceipt`), [editId] is
  /// instead that receipt's real server id, [localId] is a fresh id (this
  /// is a new queue entry either way), and [cancelled] is `true` — the
  /// `receipt_data` batch endpoint accepts `cancelled: "1"` against an
  /// existing `edit_id` just as readily as against a brand-new one, the
  /// same "Cancel is just another queued update, not a separate call"
  /// convention `EstimateRepository.queueEstimateForSync` documents.
  /// [billNumber]/[deduction]/[narration]/[entries] for an existing
  /// receipt come from `receipt_listing`'s own per-row fields — cached by
  /// `DataSyncService` and read back off the cached [ReceiptModel] by
  /// `ReceiptController.deleteReceipt` — so the receipt's original data
  /// rides along unchanged with the cancel instead of going out empty.
  ///
  /// [knownToServer] says which of those two cases this is — it decides
  /// whether [syncPendingReceipts] actually sends this row or just drops
  /// it: `false` (the default, a brand-new receipt) means a cancel is
  /// dropped from the queue unsent if it's never synced by the time Sync
  /// runs, since the server never knew about it either way; `true` (a
  /// cancel of an existing receipt) always gets sent, since there's a
  /// real server row to update.
  Future<void> queueReceiptForSync({
    required String localId,
    required String editId,
    String estimateId = '',
    required String receiptNumber,
    String billNumber = '',
    String partyName = '',
    String agentName = 'Direct',
    required String receiptDate, // dd-MM-yyyy
    required String receiptDateIso, // yyyy-MM-dd, for offline date filters
    String deduction = '',
    String narration = '',
    double totalAmount = 0,
    List<ReceiptPaymentEntry> entries = const [],
    bool cancelled = false,
    bool knownToServer = false,
  }) async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    final row = <String, dynamic>{
      'local_id': localId,
      'edit_id': editId,
      'estimate_id': estimateId,
      'receipt_number': receiptNumber,
      'bill_number': billNumber,
      'party_name': partyName,
      'agent_name': agentName,
      'receipt_date': receiptDate,
      'receipt_date_iso': receiptDateIso,
      'deduction': deduction,
      'narration': narration,
      'total_amount': totalAmount,
      'entries': entries.map((e) => e.toJson()).toList(),
      // '0' = still needs to be sent to `receipt.php` as a normal
      // create/update on the next Sync; '1' = a cancel — either a
      // brand-new receipt cancelled offline before it ever synced (see
      // [cancelPendingReceipt], where [syncPendingReceipts] just drops it
      // from the queue instead of creating it only to immediately cancel
      // it), or a cancel of a receipt the server already knows about (see
      // `ReceiptController.deleteReceipt`'s synced branch), which *does*
      // get sent — `receipt_data`'s own `cancelled` field mirrors this
      // one exactly.
      'cancelled': cancelled ? '1' : '0',
      'known_to_server': knownToServer ? '1' : '0',
    };
    final updated = [
      ...pending.where((p) => p['local_id'] != localId),
      row,
    ];
    await _cache.putJsonList(CacheKeys.receiptPending, updated);

    if (estimateId.isNotEmpty) {
      await markEstimateLocallyConverted(
        estimateId: estimateId,
        localReceiptId: localId,
      );
    }
  }

  /// Cancels a Receipt that's still only sitting in the pending-sync
  /// queue — entirely offline, since it was never sent to `receipt.php`
  /// in the first place. Unlike a synced receipt's cancel (which is a
  /// real server-side soft-void), this just flags the queue entry itself
  /// `cancelled` and leaves it in place, so it now shows under the
  /// Cancel tab instead of Active — same as a real cancelled receipt
  /// would — while [syncPendingReceipts] knows to simply drop it from
  /// the queue on the next Sync rather than creating it server-side only
  /// to cancel it right after.
  ///
  /// Also un-marks the source estimate's `receipt_id` (only if it's
  /// still exactly this queue entry's [localId] — never clobbers a real
  /// server-assigned `receipt_id` that might have landed there in the
  /// meantime), so its Receipt/Edit icons come back immediately: the
  /// conversion never actually happened.
  Future<void> cancelPendingReceipt(String localId) async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    Map<String, dynamic>? row;
    for (final p in pending) {
      if (p['local_id'] == localId) {
        row = p;
        row['cancelled'] = '1';
        break;
      }
    }
    if (row != null) {
      await _cache.putJsonList(CacheKeys.receiptPending, pending);
    }

    final estimateId = row?['estimate_id']?.toString() ?? '';
    if (estimateId.isEmpty) return;

    Future<void> unmark(String cacheKey, String idKey) async {
      final rows = _cache.getJsonList(cacheKey);
      var changed = false;
      for (final r in rows) {
        if (r[idKey]?.toString() == estimateId &&
            r['receipt_id']?.toString() == localId) {
          r['receipt_id'] = '';
          changed = true;
        }
      }
      if (changed) await _cache.putJsonList(cacheKey, rows);
    }

    await unmark(CacheKeys.estimationActive, 'estimate_id');
    await unmark(CacheKeys.estimationPending, 'local_id');
  }

  /// Stamps [estimateId]'s cached row — wherever it currently sits: the
  /// synced Active tab, or the estimate's own pending-sync queue if the
  /// estimate itself hasn't been sent to the server yet — with a
  /// non-empty `receipt_id`, so `EstimationModel.isConverted` flips (and
  /// the Estimate list's Receipt/Edit icons hide) the moment a Receipt is
  /// queued against it, offline included, without waiting for either
  /// side to actually sync. A real sync later overwrites this with the
  /// server's own `receipt_id` once the receipt is actually created; see
  /// [reapplyPendingConversions] for why that overwrite is guarded
  /// against happening too early.
  Future<void> markEstimateLocallyConverted({
    required String estimateId,
    required String localReceiptId,
  }) async {
    Future<void> patch(String cacheKey, String idKey) async {
      final rows = _cache.getJsonList(cacheKey);
      var changed = false;
      for (final row in rows) {
        if (row[idKey]?.toString() == estimateId &&
            (row['receipt_id']?.toString() ?? '').isEmpty) {
          row['receipt_id'] = localReceiptId;
          changed = true;
        }
      }
      if (changed) await _cache.putJsonList(cacheKey, rows);
    }

    await patch(CacheKeys.estimationActive, 'estimate_id');
    await patch(CacheKeys.estimationPending, 'local_id');
  }

  /// Safety net called after `DataSyncService` re-pulls a fresh estimate
  /// list from the server: a fresh `estimate_listing` pull only reflects
  /// a receipt that's *itself* already synced, so an estimate paid
  /// offline but not yet synced from the Receipt side would otherwise
  /// have its locally-set `receipt_id` wiped back to empty by that fresh
  /// pull — briefly un-hiding the Receipt/Edit icons until the next Sync.
  /// Re-applies every entry still sitting in the receipt pending-sync
  /// queue, so the icons stay hidden continuously from the moment the
  /// Receipt was created until the server actually confirms it.
  Future<void> reapplyPendingConversions() async {
    final pending = _cache.getJsonList(CacheKeys.receiptPending);
    for (final row in pending) {
      if (row['cancelled']?.toString() == '1') continue;
      final estimateId = row['estimate_id']?.toString() ?? '';
      final localId = row['local_id']?.toString() ?? '';
      if (estimateId.isEmpty || localId.isEmpty) continue;
      await markEstimateLocallyConverted(
        estimateId: estimateId,
        localReceiptId: localId,
      );
    }
  }

  /// Number of Receipts created on this device that haven't been sent to
  /// the server yet.
  int get pendingReceiptCount =>
      _cache.getJsonList(CacheKeys.receiptPending).length;

  /// Sends every queued Receipt to `receipt.php` in a single batch call —
  /// `receipt_update` / `receipt_data: [...]`, the exact
  /// one-call-for-everything shape Estimate/Quotation use (see
  /// `EstimateRepository.syncPendingEstimates`) — a normal new receipt
  /// and a cancel of an existing one both ride in the same
  /// `receipt_data` array, distinguished only by that row's own
  /// `cancelled` flag, never a separate call per row and never a
  /// separate call for cancels.
  ///
  /// **This requires `receipt_update` to actually act on `cancelled`.**
  /// As shared, that field is read into a PHP variable and never
  /// referenced again anywhere else in the handler — it doesn't gate any
  /// SQL, doesn't touch the `deleted` column. For this to work, the
  /// handler needs something like: when `$cancelled[$i] == '1'`, look up
  /// the existing receipt by `edit_id` and set `deleted = 1` on it
  /// directly. A cancel-of-existing row's `against_bill_number`,
  /// `deduction`, `narration`, and `payment_mode_data` are no longer sent
  /// empty — `receipt_listing` returns them per row, `DataSyncService`
  /// caches them alongside every other cached receipt field, and
  /// `ReceiptController.deleteReceipt` reads them straight back off the
  /// cached [ReceiptModel] and passes them into [queueReceiptForSync], so
  /// the same original bill/payment data the receipt was created with
  /// rides along with `cancelled: "1"` here, unchanged. Until the backend
  /// actually acts on `cancelled`, though, a cancel sent this way will
  /// still either no-op or fail `"Add Payment"`, exactly as it did before
  /// this change.
  ///
  /// A receipt cancelled before it ever synced (see
  /// [cancelPendingReceipt]) is still dropped from the queue first,
  /// without being sent at all — same as
  /// `EstimationController.deleteEstimation` does for an estimate
  /// cancelled before the server ever knew about it; there's nothing to
  /// tell the server, it never had this receipt either way.
  ///
  /// On success, the whole queue is cleared — one atomic call, not a
  /// per-row loop, so there's no partial success to track. On failure,
  /// the queue is left completely untouched so nothing saved on the
  /// device is lost — the next Sync attempt retries the same batch.
  Future<void> syncPendingReceipts({required String creator}) async {
    var pending = _cache.getJsonList(CacheKeys.receiptPending);
    if (pending.isEmpty) return;

    final neverSyncedCancelled = pending
        .where((r) =>
            r['cancelled']?.toString() == '1' &&
            r['known_to_server']?.toString() != '1')
        .map((r) => r['local_id']?.toString() ?? '')
        .toSet();
    if (neverSyncedCancelled.isNotEmpty) {
      pending = pending
          .where((r) => !neverSyncedCancelled.contains(r['local_id']?.toString()))
          .toList();
      await _cache.putJsonList(CacheKeys.receiptPending, pending);
    }

    if (pending.isEmpty) return;

    final receiptData = pending.map((row) {
      final rawEntries = row['entries'];
      final paymentModeData = <Map<String, dynamic>>[
        if (rawEntries is List)
          for (final e in rawEntries)
            if (e is Map)
              {
                'payment_mode_id': e['payment_mode_id']?.toString() ?? '',
                'bank_id': e['bank_id']?.toString() ?? '',
                'amount': e['amount']?.toString() ?? '',
              },
      ];

      return {
        'edit_id': row['edit_id']?.toString().isNotEmpty == true
            ? row['edit_id'].toString()
            : row['local_id']?.toString() ?? '',
        'receipt_number': row['receipt_number']?.toString() ?? '',
        'cancelled': row['cancelled']?.toString() ?? '0',
        'receipt_date': row['receipt_date']?.toString() ?? '',
        'against_bill_number': row['bill_number']?.toString() ?? '',
        'deduction': row['deduction']?.toString() ?? '',
        'narration': row['narration']?.toString() ?? '',
        'payment_mode_data': paymentModeData,
      };
    }).toList();

    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {
        'receipt_update': '1',
        'creator': creator,
        'receipt_data': receiptData,
      },
    );

    final result = ReceiptSaveResponseModel.fromJson(json);
    if (!result.isSuccess) {
      throw ApiRequestException(result.message);
    }

    await _cache.putJsonList(CacheKeys.receiptPending, []);
  }

  /// Live single-receipt cancel via `delete_receipt_id`. No longer called
  /// from [syncPendingReceipts] — cancels now ride in the same
  /// `receipt_data` batch as everything else (see that method's doc for
  /// why, and what the backend needs to change for it to actually take
  /// effect). Left here in case a live single-call cancel is ever needed
  /// again, or as a fallback if `receipt_data` cancels turn out not to be
  /// worth pursuing server-side.
  Future<ReceiptDeleteResponseModel> deleteReceipt({
    required String receiptId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.receipt,
      body: {'delete_receipt_id': receiptId},
    );

    final result = ReceiptDeleteResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }
}