import 'package:get/get.dart';

import '../../core/constants/api_endpoints.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/cache_keys.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/utils/offline_filter_utils.dart';
import '../models/party/party_detail_response_model.dart';
import '../models/party/party_list_response_model.dart';
import '../models/party/party_save_response_model.dart';

/// Talks to `party.php`. Mirrors [AuthRepository]'s contract: every method
/// either returns a successful, validated result or throws a typed
/// [ApiException] — callers never need to inspect raw response maps.
class PartyRepository {
  PartyRepository({
    ApiClient? apiClient,
    LocalCacheService? cacheService,
  })  : _apiClient = apiClient ?? ApiClient(),
        _cache = cacheService ?? Get.find<LocalCacheService>();

  final ApiClient _apiClient;
  final LocalCacheService _cache;

  /// Creates a new party, or updates an existing one when [editId] is
  /// supplied. All optional fields are sent as empty strings when unset,
  /// matching what the API expects (it treats blank as "not provided") —
  /// except [othersCity], which the API only wants when [city] is
  /// literally `"Others"`; the `others_city` key is omitted entirely
  /// otherwise.
  Future<PartySaveResponseModel> createOrUpdateParty({
    required String creator,
    required String partyName,
    String editId = '',
    String agentId = '',
    String mobileNumber = '',
    String email = '',
    String identification = '',
    String address = '',
    required String state,
    String district = '',
    String city = '',
    String? othersCity,
    String pincode = '',
    String gstNumber = '',
    String openingBalance = '',
    String openingBalanceType = '',
  }) async {
    final body = <String, dynamic>{
      'party_update': '1',
      'creator': creator,
      'party_name': partyName,
      'edit_id': editId,
      'agent_id': agentId,
      'mobile_number': mobileNumber,
      'email': email,
      'identification': identification,
      'address': address,
      'state': state,
      'district': district,
      'city': city,
      'pincode': pincode,
      'gst_number': gstNumber,
      'opening_balance': openingBalance,
      'opening_balance_type': openingBalanceType,
    };
    if (othersCity != null && othersCity.isNotEmpty) {
      body['others_city'] = othersCity;
    }

    final json = await _apiClient.postJson(ApiEndpoints.party, body: body);

    final result = PartySaveResponseModel.fromJson(json);

    if (result.isSuccess) {
      return result;
    }

    // Every non-200 head.code from this endpoint is a business/validation
    // rejection with an already user-presentable message (duplicate name,
    // duplicate mobile, invalid agent, invalid creator, etc).
    throw ApiRequestException(result.message);
  }

  /// Adds or updates one row in the on-device "pending party changes"
  /// queue ([CacheKeys.partyPending]). Every add/edit from the Party form
  /// goes through this — never a direct call to `party.php` — regardless
  /// of whether the device currently has internet. [localId] identifies
  /// the queue entry: saving under the same [localId] again (e.g.
  /// editing a not-yet-synced row a second time before syncing) replaces
  /// its previous entry instead of adding a duplicate. [editId] is the
  /// real server `party_id` when this is an edit of an already-synced
  /// party, or empty for a brand-new party.
  Future<void> queuePartyForSync({
    required String localId,
    String editId = '',
    required String partyName,
    String agentId = '',
    String mobileNumber = '',
    String email = '',
    String identification = '',
    String address = '',
    required String state,
    String district = '',
    String city = '',
    String othersCity = '',
    String pincode = '',
    String gstNumber = '',
    String openingBalance = '',
    String openingBalanceType = '',
  }) async {
    final pending = _cache.getJsonList(CacheKeys.partyPending);
    final row = <String, dynamic>{
      'local_id': localId,
      'edit_id': editId,
      'party_name': partyName,
      'agent_id': agentId,
      'mobile_number': mobileNumber,
      'email': email,
      'identification': identification,
      'address': address,
      'state': state,
      'district': district,
      'city': city,
      'others_city': othersCity,
      'pincode': pincode,
      'gst_number': gstNumber,
      'opening_balance': openingBalance,
      'opening_balance_type': openingBalanceType,
    };
    final updated = [
      ...pending.where((p) => p['local_id'] != localId),
      row,
    ];
    await _cache.putJsonList(CacheKeys.partyPending, updated);
  }

  /// Removes one entry from the pending-sync queue by [localId] — used
  /// when the user deletes a row from the list before it's ever synced,
  /// so it doesn't reappear on the next reload.
  Future<void> removePendingParty(String localId) async {
    final pending = _cache.getJsonList(CacheKeys.partyPending);
    await _cache.putJsonList(
      CacheKeys.partyPending,
      pending.where((p) => p['local_id'] != localId).toList(),
    );
  }

  /// Number of party adds/edits saved on this device that haven't been
  /// sent to the server yet.
  int get pendingPartyCount =>
      _cache.getJsonList(CacheKeys.partyPending).length;

  /// Sends every queued add/edit to `party.php` in a single batch call —
  /// the same `party_update` / `party_data: [...]` shape the endpoint
  /// expects for multiple rows at once. Only ever called from the Sync
  /// button (via [DataSyncService]), and only while online — nothing
  /// else in the app ever calls this.
  ///
  /// On success, clears the queue. On failure (network error, or a
  /// business-rule rejection like a duplicate name), the queue is left
  /// untouched so nothing saved on the device is lost — the next Sync
  /// attempt retries the same batch.
  Future<PartySaveResponseModel> syncPendingParties({
    required String creator,
  }) async {
    final pending = _cache.getJsonList(CacheKeys.partyPending);
    if (pending.isEmpty) {
      return const PartySaveResponseModel(
        code: 200,
        message: 'Nothing to sync',
      );
    }

    final partyData = pending
        .map((row) => {
              'edit_id': row['edit_id'] ?? '',
              'party_name': row['party_name'] ?? '',
              'agent_id': row['agent_id'] ?? '',
              'mobile_number': row['mobile_number'] ?? '',
              'email': row['email'] ?? '',
              'identification': row['identification'] ?? '',
              'address': row['address'] ?? '',
              'state': row['state'] ?? '',
              'district': row['district'] ?? '',
              'city': row['city'] ?? '',
              'others_city': row['others_city'] ?? '',
              'pincode': row['pincode'] ?? '',
              'gst_number': row['gst_number'] ?? '',
              'opening_balance': row['opening_balance'] ?? '',
              'opening_balance_type': row['opening_balance_type'] ?? '',
            })
        .toList();

    final json = await _apiClient.postJson(
      ApiEndpoints.party,
      body: {
        'party_update': '1',
        'creator': creator,
        'party_data': partyData,
      },
    );

    final result = PartySaveResponseModel.fromJson(json);
    if (!result.isSuccess) {
      throw ApiRequestException(result.message);
    }

    // The batch is confirmed on the server now — clear the queue so it
    // isn't sent again. The synced-cache refresh (fetchLiveParties) that
    // follows this is DataSyncService's job, not this repository's.
    await _cache.putJsonList(CacheKeys.partyPending, []);
    return result;
  }

  /// Returns a page of the party list — always from the offline cache
  /// that [DataSyncService]/the Sync button populate, regardless of
  /// whether the device currently has internet.
  ///
  /// The only thing that ever calls the live `party_listing` endpoint is
  /// a manual tap of the Sync button (`DataSyncService.syncAllData`), which
  /// fetches the full, unpaginated list. Browsing the list itself never
  /// hits the network — this keeps behavior identical online and offline
  /// and means a flaky connection can never cause a half-loaded list or
  /// an unexpectedly slow screen while just looking at data.
  ///
  /// [agentId] is accepted for API-shape compatibility but currently
  /// unused — there's no agent filter in the UI, and the cached rows
  /// don't carry an agent id to filter by anyway.
  Future<PartyListResponseModel> listParties({
    String agentId = '',
    String searchText = '',
    int? pageNumber,
    int? pageLimit,
  }) async {
    return _partiesFromCache(
      searchText: searchText,
      pageNumber: pageNumber,
      pageLimit: pageLimit,
    );
  }

  /// Calls the live `party_listing` endpoint directly, no cache fallback.
  /// This is the *only* method in the app that ever does — used
  /// exclusively by [DataSyncService] (both the post-login full sync and
  /// the per-page Sync button), to refresh the offline cache that
  /// [listParties] reads from. Throws on failure exactly like any other
  /// API call here; [DataSyncService] is what catches and reports it.
  Future<PartyListResponseModel> fetchLiveParties({
    String agentId = '',
    String searchText = '',
    int? pageNumber,
    int? pageLimit,
  }) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.party,
      body: {
        'party_listing': '1',
        'filter_agent_id': agentId,
        'search_text': searchText,
        if (pageNumber != null) 'page_number': pageNumber.toString(),
        if (pageLimit != null) 'page_limit': pageLimit.toString(),
      },
    );

    final result = PartyListResponseModel.fromJson(json);
    if (result.isSuccess) return result;

    throw ApiRequestException(result.message);
  }

  /// Full cached details for one party by id — checks the pending queue
  /// first (so an unsynced edit wins), then the synced cache. Used to
  /// build the "Bill To" block when generating a quotation PDF entirely
  /// offline (see `QuotationPdfBuilder`), since a quotation only stores
  /// its party's id, not a full address snapshot.
  PartyListItem? cachedPartyById(String partyId) {
    if (partyId.isEmpty) return null;
    for (final row in _cache.getJsonList(CacheKeys.partyPending)) {
      final item = PartyListItem.fromPendingRow(row);
      if (item.partyId == partyId) return item;
    }
    for (final row in _cache.getJsonList(CacheKeys.party)) {
      final item = PartyListItem.fromJson(row);
      if (item.partyId == partyId) return item;
    }
    return null;
  }

  /// Best-effort full cached details for one party by *name* instead of
  /// id — for callers that only ever got handed a decrypted display name
  /// (e.g. `receipt_listing`'s rows, which carry `party_name` but no
  /// `party_id`), and so have no way to call [cachedPartyById]. Matched
  /// case-insensitively against the same two sources, pending queue
  /// first. Since names aren't unique the way ids are, this returns the
  /// first match and is meant only for enriching a report's "Bill To"
  /// block (contact/city) with best-effort detail — never for anything
  /// that needs a guaranteed-correct single party, like an edit form.
  PartyListItem? cachedPartyByName(String partyName) {
    final needle = partyName.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final row in _cache.getJsonList(CacheKeys.partyPending)) {
      final item = PartyListItem.fromPendingRow(row);
      if (item.partyName.trim().toLowerCase() == needle) return item;
    }
    for (final row in _cache.getJsonList(CacheKeys.party)) {
      final item = PartyListItem.fromJson(row);
      if (item.partyName.trim().toLowerCase() == needle) return item;
    }
    return null;
  }

  /// Builds a page of results from whatever [DataSyncService] last cached,
  /// merged with anything still sitting in the pending-sync queue,
  /// applying the same name search the server would. There's no
  /// agent-id field on the cached rows (the list endpoint never returns
  /// one), so an [agentId] filter can't be honored offline — matches
  /// today's UI, which never sets one anyway.
  PartyListResponseModel _partiesFromCache({
    required String searchText,
    required int? pageNumber,
    required int? pageLimit,
  }) {
    final pendingItems = _cache
        .getJsonList(CacheKeys.partyPending)
        .map(PartyListItem.fromPendingRow)
        .toList();

    // A pending edit of an already-synced party (non-empty edit_id)
    // supersedes that party's stale synced-cache row — otherwise the
    // list would show both the old and the not-yet-synced new version.
    final supersededIds =
        pendingItems.map((p) => p.partyId).where((id) => id.isNotEmpty).toSet();

    final synced = _cache
        .getJsonList(CacheKeys.party)
        .map(PartyListItem.fromJson)
        .where((p) => !supersededIds.contains(p.partyId))
        .toList();

    // Newest pending entries first (most recent add/edit on top), then
    // the synced rows in their existing (already newest-first) order.
    final all = [...pendingItems.reversed, ...synced];

    final filtered = all
        .where((p) => matchesSearch(searchText, [p.partyName]))
        .toList();

    return PartyListResponseModel(
      code: 200,
      message: 'Loaded from offline data',
      items: paginate(filtered, pageNumber, pageLimit),
      totalRecords: filtered.length,
    );
  }

  /// Fetches full details for one party, used to hydrate the Edit form
  /// before saving — the list endpoint only returns id/name/state.
  Future<PartyDetailResponseModel> getPartyDetail(String partyId) async {
    final json = await _apiClient.postJson(
      ApiEndpoints.party,
      body: {'show_party_id': partyId},
    );

    final result = PartyDetailResponseModel.fromJson(json);

    if (result.isSuccess) {
      return result;
    }

    throw ApiRequestException(result.message);
  }
}