import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/estimate/estimate_charge_type_response_model.dart';
import '../models/estimate/estimate_delete_response_model.dart';
import '../models/estimate/estimate_init_response_model.dart';
import '../models/estimate/estimate_list_response_model.dart';
import '../models/estimate/estimate_product_list_response_model.dart';
import '../models/estimate/estimate_save_response_model.dart';
import '../models/estimate/estimate_selected_product_response_model.dart';
import '../models/estimate/id_name.dart';

/// One product line as sent inside `product_data` on `estimate_update`.
class EstimateProductLine {
  final String productId;
  final String quantity;
  final String rate;

  const EstimateProductLine({
    required this.productId,
    required this.quantity,
    required this.rate,
  });

  Map<String, dynamic> toJson() => {
        'product_id': productId,
        'product_quantity': quantity,
        'product_rate': rate,
      };
}

/// One other-charge line, sent as three parallel arrays
/// (`other_charges_id` / `other_charges_type` / `other_charges_value`) on
/// `estimate_update`.
class EstimateChargeLine {
  final String chargeId;
  final String type; // "Plus" or "Minus"
  final String value;
  final String name;

  const EstimateChargeLine({
    required this.chargeId,
    required this.type,
    required this.value,
    this.name = '',
  });

  Map<String, dynamic> toJson() => {
        'other_charges_id': chargeId,
        'other_charges_name': name,
        'other_charges_type': type,
        'other_charges_value': value,
      };
}

/// One other-charge option cached offline for the form's Charges row —
/// its `type` ("Plus"/"Minus") is a fixed property of the charge itself
/// server-side, fetched once per charge at Sync time (see
/// [EstimateRepository.cachedOtherCharges]) instead of via a live
/// `type_other_charges_id` call every time one is picked.
class CachedChargeOption {
  final String id;
  final String name;
  final String type;

  const CachedChargeOption(
      {required this.id, required this.name, required this.type});
}

/// Talks to `estimate.php`. Every method either returns a successful,
/// validated result or throws a typed [ApiException] — callers never need
/// to inspect raw response maps.
class EstimateRepository {
  EstimateRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// Bootstraps the Add/Edit Estimate form: dropdown data (pricelist,
  /// agent, party, other charges) plus — when [showEstimateId] is a real
  /// id — the existing estimate's own fields. Pass an empty string to get
  /// just the dropdown data for a brand-new estimate.
  ///
  /// [convertQuotationId], when non-empty, asks the server to prefill the
  /// (otherwise blank) form fields from an active quotation's own party/
  /// pricelist/agent/products instead — used to bootstrap the "Convert to
  /// Estimate" flow from the Quotation list.
  ///
  /// Only called now as a one-time backward-compat fallback — either for
  /// an estimate cached before this app version started storing full
  /// details (see [EstimateListItem.hasFullDetails]), or for a "Convert
  /// to Estimate" whose source quotation row hasn't got full details
  /// cached yet either (see `QuotationModel.hasFullDetails`). The normal
  /// Add/Edit flow, and the normal Convert-to-Estimate flow, use
  /// [cachedPricelists]/[cachedAgents]/[cachedParties]/[cachedOtherCharges]/
  /// [cachedProductsForPricelist] plus the source quotation's own cached
  /// fields instead, and never touch the network.
  Future<EstimateInitResponseModel> getFormInitData({
    String showEstimateId = '',
    String convertQuotationId = '',
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {
        'show_estimate_id': showEstimateId,
        'convert_quotation_id': convertQuotationId,
      },
    );

    final result = EstimateInitResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Pricelist dropdown options for the Add/Edit Estimate form —
  /// refreshed once at login and via the Sync button (see
  /// `DataSyncService._syncEstimateCatalogue`), read here with no
  /// network call.
  List<IdName> cachedPricelists() => _cache
      .getJsonList(CacheKeys.estimationPricelists)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Agent dropdown options for the Add/Edit Estimate form — the same
  /// snapshot [_filterCachedEstimates] reads for its offline agent
  /// filter, refreshed by [DataSyncService]'s regular estimation-list
  /// sync (every synced estimate row carries its agent).
  List<IdName> cachedAgents() => _cache
      .getJsonList(CacheKeys.estimationAgents)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Party dropdown options for the Add/Edit Estimate form — the same
  /// snapshot [_filterCachedEstimates] reads for its offline party
  /// filter.
  List<IdName> cachedParties() => _cache
      .getJsonList(CacheKeys.estimationParties)
      .map((m) => IdName(
            id: m['id']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
          ))
      .toList();

  /// Other-charges dropdown options for the form's Charges row, together
  /// with each charge's fixed "Plus"/"Minus" type — cached once per
  /// charge at Sync so picking a charge offline never needs
  /// `type_other_charges_id`.
  List<CachedChargeOption> cachedOtherCharges() => _cache
      .getJsonList(CacheKeys.estimationOtherCharges)
      .map((m) => CachedChargeOption(
            id: m['other_charges_id']?.toString() ?? '',
            name: m['other_charges_name']?.toString() ?? '',
            type: m['charges_type']?.toString() ?? 'Plus',
          ))
      .toList();

  /// Every product offered under [pricelistId], from the full product
  /// catalogue cached at login/Sync — backs the form's product picker
  /// with no network call.
  List<EstimateProductOption> cachedProductsForPricelist(
    String pricelistId,
  ) =>
      _cache
          .getJsonList(CacheKeys.estimationProducts)
          .where((m) => m['pricelist_id']?.toString() == pricelistId)
          .map(EstimateProductOption.fromJson)
          .toList();

  /// The `YY-YY` financial-year suffix `estimate_number` gets appended
  /// with (e.g. `26-27` for a date in April 2026 – March 2027) — the
  /// same Indian financial year the business already prints on its bills.
  static String _financialYearSuffix(DateTime date) {
    final startYear = date.month >= 4 ? date.year : date.year - 1;
    String two(int y) => (y % 100).toString().padLeft(2, '0');
    return '${two(startYear)}-${two(startYear + 1)}';
  }

  /// Builds the next `estimate_number` for a brand-new estimate:
  /// `<billPrefix>EST<seq>/<FY>` — e.g. `AKBEST031/26-27`, matching
  /// Quotation's own `<billPrefix>QUT<seq>/<FY>` format (no separator
  /// between the prefix and "EST"). The sequence carries on from the
  /// highest number already used this financial year, across every
  /// cached tab (Active/Draft/Cancel) and anything still pending sync,
  /// so numbers stay sequential across multiple offline creates even
  /// before a Sync.
  String nextEstimateNumber({required String billPrefix}) {
    final fy = _financialYearSuffix(DateTime.now());
    final pattern =
        RegExp('EST(\\d+)/${RegExp.escape(fy)}\$', caseSensitive: false);

    var maxSeq = 0;
    void scan(Iterable<Map<String, dynamic>> rows) {
      for (final row in rows) {
        final number = row['estimate_number']?.toString() ?? '';
        final match = pattern.firstMatch(number);
        if (match != null) {
          final seq = int.tryParse(match.group(1)!) ?? 0;
          if (seq > maxSeq) maxSeq = seq;
        }
      }
    }

    scan(_cache.getJsonList(CacheKeys.estimationActive));
    scan(_cache.getJsonList(CacheKeys.estimationDraft));
    scan(_cache.getJsonList(CacheKeys.estimationCancel));
    scan(_cache.getJsonList(CacheKeys.estimationPending));

    final next = (maxSeq + 1).toString().padLeft(3, '0');
    return '$billPrefix - EST$next/$fy';
  }

  /// Adds or updates one row in the on-device "pending estimate changes"
  /// queue ([CacheKeys.estimationPending]). Every add/edit from the
  /// Estimate form — draft or confirmed — goes through this, never a
  /// direct call to `estimate.php`, regardless of whether the device
  /// currently has internet. [localId] identifies the queue entry: saving
  /// under the same [localId] again (e.g. editing a not-yet-synced row a
  /// second time before syncing) replaces its previous entry instead of
  /// adding a duplicate.
  ///
  /// [editId] and [estimateNumber] are now both generated on this device
  /// (see `EstimationController.save` / [nextEstimateNumber]) — the
  /// server no longer assigns either; it just stores whatever unique
  /// `edit_id` and `estimate_number` it's given. For a brand-new estimate
  /// both are freshly generated; for an edit, both must be the same
  /// values the estimate already has, so editing never changes its id or
  /// bill number. [products]/[charges] carry more than the wire format
  /// needs (name/unit alongside id/qty/rate) so a pending row can be
  /// re-opened for editing without a server round trip — only what
  /// `estimate_update` actually expects is sent once
  /// [syncPendingEstimates] runs. [cancelled] defaults false for a normal
  /// add/edit save. Passing `true` is how a Cancel made while offline is
  /// queued too (see `EstimationController.deleteEstimation`) — the batch
  /// endpoint accepts `cancelled: "1"` on any row, synced or not, so a
  /// Cancel is just another entry in the same queue, not a separate call.
  ///
  /// [complimentProducts] is the free/no-charge "Compliment Products"
  /// list from the form's "+ Add Compliment Products" button — each map
  /// carrying `product_id`/`product_name`/`unit_id`/`unit_name`/
  /// `product_quantity`, the same shape as one of [products]'s entries
  /// minus the rate. Stored alongside everything else so re-opening this
  /// pending row for editing shows the compliment products too; only
  /// `product_id`/`product_quantity` are actually sent by
  /// [syncPendingEstimates] (as `compliment_product_id`/
  /// `compliment_product_quantity`).
  Future<void> queueEstimateForSync({
    required String localId,
    required String editId,
    required String estimateNumber,
    String convertQuotationId = '',
    required String drafted,
    bool cancelled = false,
    required String estimateDate, // dd-MM-yyyy
    required String pricelistId,
    String pricelistName = '',
    String agentId = '',
    String agentName = '',
    required String partyId,
    String partyName = '',
    required List<Map<String, String>> products,
    String section1AddValue = '',
    String section1Discount = '',
    String section2AddValue = '',
    String section2Discount = '',
    List<EstimateChargeLine> charges = const [],
    List<Map<String, String>> complimentProducts = const [],
  }) async {
    final pending = _cache.getJsonList(CacheKeys.estimationPending);
    final row = <String, dynamic>{
      'local_id': localId,
      'edit_id': editId,
      'estimate_number': estimateNumber,
      'convert_quotation_id': convertQuotationId,
      'drafted': drafted,
      'cancelled': cancelled ? '1' : '0',
      'estimate_date': estimateDate,
      'pricelist_id': pricelistId,
      'pricelist_name': pricelistName,
      'agent_id': agentId,
      'agent_name': agentName,
      'party_id': partyId,
      'party_name': partyName,
      'product_data': products,
      'section1_add_value': section1AddValue,
      'section1_discount': section1Discount,
      'section2_add_value': section2AddValue,
      'section2_discount': section2Discount,
      'charges': charges.map((c) => c.toJson()).toList(),
      'compliment_product_data': complimentProducts,
    };
    final updated = [
      ...pending.where((p) => p['local_id'] != localId),
      row,
    ];
    await _cache.putJsonList(CacheKeys.estimationPending, updated);
  }

  /// Whether [estimateId] already exists in one of the three synced-tab
  /// caches (Active/Draft/Cancel) — i.e. the server has confirmed this
  /// estimate at least once, as opposed to one still sitting only in the
  /// pending-sync queue that's never actually been sent yet. Decides what
  /// Cancel does for a pending row (see
  /// `EstimationController.deleteEstimation`): queue a `cancelled: "1"`
  /// update if the server already knows about it, or just drop the queue
  /// entry if it doesn't.
  bool existsInSyncedCache(String estimateId) {
    bool inTab(String cacheKey) => _cache
        .getJsonList(cacheKey)
        .any((m) => m['estimate_id']?.toString() == estimateId);
    return inTab(CacheKeys.estimationActive) ||
        inTab(CacheKeys.estimationDraft) ||
        inTab(CacheKeys.estimationCancel);
  }

  /// Removes one entry from the pending-sync queue by [localId] — used
  /// when the user deletes a row from the list before it's ever synced,
  /// so it doesn't reappear on the next reload.
  Future<void> removePendingEstimate(String localId) async {
    final pending = _cache.getJsonList(CacheKeys.estimationPending);
    await _cache.putJsonList(
      CacheKeys.estimationPending,
      pending.where((p) => p['local_id'] != localId).toList(),
    );
  }

  /// Number of estimate adds/edits saved on this device that haven't
  /// been sent to the server yet.
  int get pendingEstimateCount =>
      _cache.getJsonList(CacheKeys.estimationPending).length;

  /// Sends every queued add/edit to `estimate.php` in a single batch call
  /// — the same `estimate_update` / `estimate_data: [...]` shape the
  /// endpoint expects for multiple rows at once. Only ever called from
  /// the Sync button (via [DataSyncService]), and only while online —
  /// nothing else in the app ever calls this.
  ///
  /// On success, clears the queue. On failure (network error, or a
  /// business-rule rejection), the queue is left untouched so nothing
  /// saved on the device is lost — the next Sync attempt retries the
  /// same batch.
  Future<EstimateSaveResponseModel> syncPendingEstimates({
    required String creator,
  }) async {
    final pending = _cache.getJsonList(CacheKeys.estimationPending);
    if (pending.isEmpty) {
      return const EstimateSaveResponseModel(
        code: 200,
        message: 'Nothing to sync',
      );
    }

    final estimateData = pending.map((row) {
      final rawProducts = row['product_data'];
      final products = <Map<String, dynamic>>[
        if (rawProducts is List)
          for (final p in rawProducts)
            if (p is Map)
              {
                'product_id': p['product_id'] ?? '',
                'product_quantity': p['product_quantity'] ?? '',
                'product_rate': p['product_rate'] ?? '',
              },
      ];

      final rawCharges = row['charges'];
      final chargeIds = <String>[];
      final chargeTypes = <String>[];
      final chargeValues = <String>[];
      if (rawCharges is List) {
        for (final c in rawCharges) {
          if (c is Map) {
            chargeIds.add(c['other_charges_id']?.toString() ?? '');
            chargeTypes.add(c['other_charges_type']?.toString() ?? '');
            chargeValues.add(c['other_charges_value']?.toString() ?? '');
          }
        }
      }

      // Compliment products are sent as two parallel arrays — id and
      // quantity only, no rate — matching the "no price" nature of a
      // free/no-charge line.
      final rawCompliments = row['compliment_product_data'];
      final complimentProductIds = <String>[];
      final complimentProductQuantities = <String>[];
      if (rawCompliments is List) {
        for (final c in rawCompliments) {
          if (c is Map) {
            complimentProductIds.add(c['product_id']?.toString() ?? '');
            complimentProductQuantities
                .add(c['product_quantity']?.toString() ?? '');
          }
        }
      }

      return {
        'edit_id': row['edit_id'] ?? '',
        'estimate_number': row['estimate_number'] ?? '',
        'convert_quotation_id': row['convert_quotation_id'] ?? '',
        'drafted': row['drafted'] ?? '0',
        'cancelled': row['cancelled'] ?? '0',
        'estimate_date': row['estimate_date'] ?? '',
        'pricelist_id': row['pricelist_id'] ?? '',
        'agent_id': row['agent_id'] ?? '',
        'party_id': row['party_id'] ?? '',
        'product_data': products,
        'section1_add_value': row['section1_add_value'] ?? '',
        'section1_discount': row['section1_discount'] ?? '',
        'section2_add_value': row['section2_add_value'] ?? '',
        'section2_discount': row['section2_discount'] ?? '',
        'other_charges_id': chargeIds,
        'other_charges_type': chargeTypes,
        'other_charges_value': chargeValues,
        'compliment_product_id': complimentProductIds,
        'compliment_product_quantity': complimentProductQuantities,
      };
    }).toList();

    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {
        'estimate_update': '1',
        'creator': creator,
        'estimate_data': estimateData,
      },
    );

    final result = EstimateSaveResponseModel.fromJson(json);
    if (!result.isSuccess) {
      throw ApiRequestException(result.message);
    }

    await _cache.putJsonList(CacheKeys.estimationPending, []);
    return result;
  }

  /// Returns a page of the estimate list — always from the offline
  /// cache that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// [drafted] and [cancelled] select which tab's rows come back — pass
  /// `'1'`/`'0'` explicitly for Active / Draft / Cancel rather than
  /// leaving them blank, same as the cache is stored per-tab.
  ///
  /// The only thing that ever calls the live `estimate_listing` endpoint
  /// is a manual tap of the Sync button (`DataSyncService.syncAllData`),
  /// which fetches the full, unpaginated list for all three tabs.
  /// Browsing the list itself never hits the network — this keeps
  /// behavior identical online and offline and means a flaky connection
  /// can never cause a half-loaded list or an unexpectedly slow screen
  /// while just looking at data.
  Future<EstimateListResponseModel> listEstimates({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterAgentId = '',
    String filterPartyId = '',
    int? pageNumber,
    int? pageLimit,
    String drafted = '0',
    String cancelled = '0',
  }) async {
    return _estimatesFromCache(
      drafted: drafted,
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterAgentId: filterAgentId,
      filterPartyId: filterPartyId,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `estimate_listing` endpoint directly, no cache
  /// fallback. This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [listEstimates] reads from. Throws on failure exactly like any other
  /// API call here; [DataSyncService] is what catches and reports it.
  Future<EstimateListResponseModel> fetchLiveEstimates({
    String filterFromDate = '',
    String filterToDate = '',
    String searchText = '',
    String filterAgentId = '',
    String filterPartyId = '',
    int? pageNumber,
    int? pageLimit,
    String drafted = '0',
    String cancelled = '0',
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {
        'estimate_listing': '1',
        'filter_from_date': filterFromDate,
        'filter_to_date': filterToDate,
        'search_text': searchText,
        'filter_agent_id': filterAgentId,
        'filter_party_id': filterPartyId,
        if (pageNumber != null) 'page_number': pageNumber.toString(),
        if (pageLimit != null) 'page_limit': pageLimit.toString(),
        'drafted': drafted,
        'cancelled': cancelled,
      },
    );

    final result = EstimateListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// [drafted]/[cancelled] pick which cached tab snapshot to read from —
  /// [DataSyncService] stores Active/Draft/Cancel separately, the same
  /// split the server's `drafted`/`cancelled` flags produce. Returns
  /// every cached row matching [filterFromDate]/[filterToDate]/
  /// [searchText]/[filterAgentId]/[filterPartyId], unpaginated — merged
  /// with anything still sitting in the pending-sync queue that belongs
  /// to this tab.
  List<EstimateListItem> _filterCachedEstimates({
    required String drafted,
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterAgentId,
    required String filterPartyId,
  }) {
    final pendingAll = _cache
        .getJsonList(CacheKeys.estimationPending)
        .map(EstimateListItem.fromPendingRow)
        .toList();

    // A pending row queuing a Cancel (see
    // `EstimationController.deleteEstimation`) always shows under the
    // Cancel tab, regardless of its drafted flag — everything else only
    // shows up under the tab matching its own drafted state.
    final pendingForTab = pendingAll.where((e) {
      if (cancelled == '1') return e.isCancelled;
      if (e.isCancelled) return false;
      return (e.isDraft ? '1' : '0') == drafted;
    }).toList();

    // A pending edit of an already-synced estimate (non-empty edit_id)
    // supersedes that estimate's stale synced-cache row, wherever it
    // currently sits — otherwise editing a Draft into a confirmed
    // estimate would leave a stale copy behind in the Draft tab while the
    // updated one shows in Active.
    final supersededIds =
        pendingAll.map((e) => e.estimateId).where((id) => id.isNotEmpty).toSet();

    final cacheKey = cancelled == '1'
        ? CacheKeys.estimationCancel
        : (drafted == '1'
            ? CacheKeys.estimationDraft
            : CacheKeys.estimationActive);

    final synced = _cache
        .getJsonList(cacheKey)
        .map(EstimateListItem.fromJson)
        .where((e) => !supersededIds.contains(e.estimateId))
        .toList();

    final all = [...pendingForTab.reversed, ...synced];

    final agentList = _cache
        .getJsonList(CacheKeys.estimationAgents)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();
    final partyList = _cache
        .getJsonList(CacheKeys.estimationParties)
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

    final agentName =
        filterAgentId.isEmpty ? null : nameForId(agentList, filterAgentId);
    final partyName =
        filterPartyId.isEmpty ? null : nameForId(partyList, filterPartyId);

    return all.where((e) {
      if (!matchesDateRange(e.estimateDate, filterFromDate, filterToDate)) {
        return false;
      }
      // No per-row agent/party id on this endpoint either — only the
      // combined "name / mobile / city" strings — so filters are matched
      // by whether that string mentions the selected name.
      if (agentName != null &&
          !e.agentNameMobileCity.toLowerCase().contains(agentName.toLowerCase())) {
        return false;
      }
      if (partyName != null &&
          !e.partyNameMobileCity.toLowerCase().contains(partyName.toLowerCase())) {
        return false;
      }
      return matchesSearch(searchText, [
        e.estimateNumber,
        e.agentNameMobileCity,
        e.partyNameMobileCity,
      ]);
    }).toList();
  }

  EstimateListResponseModel _estimatesFromCache({
    required String drafted,
    required String cancelled,
    required String filterFromDate,
    required String filterToDate,
    required String searchText,
    required String filterAgentId,
    required String filterPartyId,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final filtered = _filterCachedEstimates(
      drafted: drafted,
      cancelled: cancelled,
      filterFromDate: filterFromDate,
      filterToDate: filterToDate,
      searchText: searchText,
      filterAgentId: filterAgentId,
      filterPartyId: filterPartyId,
    );

    final agentList = _cache
        .getJsonList(CacheKeys.estimationAgents)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();
    final partyList = _cache
        .getJsonList(CacheKeys.estimationParties)
        .map((m) => IdName(
              id: m['id']?.toString() ?? '',
              name: m['name']?.toString() ?? '',
            ))
        .toList();

    return EstimateListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      agentList: agentList,
      partyList: partyList,
      totalRecords: filtered.length,
    );
  }

  /// Products offered under a given pricelist, for the "Add Item" picker.
  Future<EstimateProductListResponseModel> getProductsForPricelist(
    String pricelistId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {'product_pricelist_id': pricelistId},
    );

    final result = EstimateProductListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Rate / unit / current stock / discount-section for one product under
  /// one pricelist — only ever used now as a backward-compat fallback
  /// (see [getFormInitData]); the normal Add/Edit flow reads this same
  /// data straight out of [cachedProductsForPricelist] instead.
  Future<EstimateSelectedProductResponseModel> getSelectedProductDetail({
    required String productId,
    required String pricelistId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {
        'selected_product_id': productId,
        'pricelist_id': pricelistId,
      },
    );

    final result = EstimateSelectedProductResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Whether a chosen other-charge is added ("Plus") or deducted
  /// ("Minus"). Only ever used now as a backward-compat fallback (see
  /// [getFormInitData]); the normal Add/Edit flow reads this from
  /// [cachedOtherCharges] instead.
  Future<EstimateChargeTypeResponseModel> getChargeType(
    String otherChargesId,
  ) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {'type_other_charges_id': otherChargesId},
    );

    final result = EstimateChargeTypeResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Creates a new estimate, or updates an existing one when [editId] is
  /// supplied. Only ever used now as a backward-compat fallback path —
  /// the normal Add/Edit flow always goes through [queueEstimateForSync] /
  /// [syncPendingEstimates] instead, never calling `estimate.php` directly
  /// from the form.
  Future<EstimateSaveResponseModel> saveEstimate({
    required String creator,
    String editId = '',
    String convertQuotationId = '',
    required String estimateDate, // dd-MM-yyyy
    required String pricelistId,
    String agentId = '',
    required String partyId,
    required List<EstimateProductLine> products,
    String section1AddValue = '',
    String section1Discount = '',
    String section2AddValue = '',
    String section2Discount = '',
    List<EstimateChargeLine> charges = const [],
  }) async {
    final body = <String, dynamic>{
      'estimate_update': '1',
      'creator': creator,
      'edit_id': editId,
      'convert_quotation_id': convertQuotationId,
      'estimate_date': estimateDate,
      'pricelist_id': pricelistId,
      'agent_id': agentId,
      'party_id': partyId,
      'product_data': products.map((p) => p.toJson()).toList(),
      'section1_add_value': section1AddValue,
      'section1_discount': section1Discount,
      'section2_add_value': section2AddValue,
      'section2_discount': section2Discount,
      'other_charges_id': charges.map((c) => c.chargeId).toList(),
      'other_charges_type': charges.map((c) => c.type).toList(),
      'other_charges_value': charges.map((c) => c.value).toList(),
    };

    final json = await _apiClient.postJson(ApiEndpoints.estimate, body: body);

    final result = EstimateSaveResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Deletes/cancels an estimate via the live `delete_estimate_id` call.
  /// No longer called anywhere in the normal flow — both Draft and
  /// Active Cancel now go through the offline-first
  /// [queueEstimateForSync] path instead (see
  /// `EstimationController.deleteEstimation`). Kept only as a
  /// backward-compat fallback.
  Future<EstimateDeleteResponseModel> deleteEstimate({
    required String estimateId,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.estimate,
      body: {'delete_estimate_id': estimateId},
    );

    final result = EstimateDeleteResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }
}