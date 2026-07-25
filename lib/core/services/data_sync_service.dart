import 'dart:developer' as developer;

import 'package:get/get.dart';

import '../../data/respositories/custom_product_repository.dart';
import '../../data/respositories/estimate_repository.dart';
import '../../data/respositories/party_repository.dart';
import '../../data/respositories/product_price_repository.dart';
import '../../data/respositories/quotation_repository.dart';
import '../../data/respositories/receipt_repository.dart';
import 'cache_keys.dart';
import 'local_cache_service.dart';
import 'session_service.dart';

/// Pulls the Party / Price Upload / Quotation / Estimation / Receipt
/// lists down from the API and caches them locally.
///
/// This is now the *only* place in the app that ever calls those five
/// list endpoints live. Every list screen's own repository method
/// (`listParties`, `fetchPriceList`, `listQuotations`, `listEstimates`,
/// `listReceipts`) always reads from the offline cache this service
/// populates — online or offline, it makes no difference. Each
/// repository also exposes a `fetchLiveXxx` twin (`fetchLiveParties`,
/// `fetchLivePriceList`, etc.) that actually hits the network; those are
/// used exclusively here, never by a list screen directly.
///
/// Runs in two ways:
/// - [syncAll] — every section, in order — once, right after a
///   *successful online* login (see `LoginController`).
/// - The per-page Sync button — one section at a time (`syncParty`,
///   `syncPriceList`, `syncQuotations`, `syncEstimations`,
///   `syncReceipts`), whenever the person taps it while online.
///
/// Every list endpoint here is server-paginated, but sync deliberately
/// never sends `page_number`/`page_limit` at all — the `fetchLiveXxx`
/// methods treat both as optional and, when omitted, the endpoint
/// returns its full list in one shot. This is exactly the "full list,
/// no pagination" mode the backend is moving towards for sync callers;
/// once every endpoint is confirmed to support it, nothing else here
/// needs to change.
///
/// A single section failing (timeout, server hiccup mid-sync, etc.)
/// never throws out of [syncAll] — the user is already validly logged in
/// by the time this runs, so the worst case is "some lists are stale",
/// not "login is broken". [lastError] surfaces the most recent failure
/// for anyone who wants to show a subtle warning.
class DataSyncService extends GetxService {
  DataSyncService({
    PartyRepository? partyRepository,
    ProductPriceRepository? productPriceRepository,
    QuotationRepository? quotationRepository,
    EstimateRepository? estimateRepository,
    ReceiptRepository? receiptRepository,
    CustomProductRepository? customProductRepository,
    LocalCacheService? cache,
    SessionService? sessionService,
  })  : _partyRepository = partyRepository ?? PartyRepository(),
        _productPriceRepository =
            productPriceRepository ?? ProductPriceRepository(),
        _quotationRepository = quotationRepository ?? QuotationRepository(),
        _estimateRepository = estimateRepository ?? EstimateRepository(),
        _receiptRepository = receiptRepository ?? ReceiptRepository(),
        _customProductRepository =
            customProductRepository ?? CustomProductRepository(),
        _cache = cache ?? Get.find<LocalCacheService>(),
        _sessionService = sessionService ?? Get.find<SessionService>();

  final PartyRepository _partyRepository;
  final ProductPriceRepository _productPriceRepository;
  final QuotationRepository _quotationRepository;
  final EstimateRepository _estimateRepository;
  final ReceiptRepository _receiptRepository;
  final CustomProductRepository _customProductRepository;
  final LocalCacheService _cache;
  final SessionService _sessionService;

  final isSyncing = false.obs;
  final statusMessage = ''.obs;
  final RxnString lastError = RxnString();

  /// Runs the full sync — every section, in order. Intended to run exactly
  /// once, right after a successful online login (see `LoginController`).
  /// Per-module sync buttons on each list screen should call their own
  /// `syncXxx()` method below instead of this, so tapping "Sync" on, say,
  /// the Quotation page doesn't also re-pull Party/Price List/Estimation/
  /// Receipt in the background.
  Future<void> syncAll() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    lastError.value = null;
    try {
      await _runStep('Syncing parties…', _syncParties);
      await _runStep('Syncing price list…', _syncPriceList);
      await _runStep('Syncing quotations…', _syncQuotations);
      await _runStep('Syncing estimations…', _syncEstimations);
      await _runStep('Syncing receipts…', _syncReceipts);
      await _cache.putString(
        CacheKeys.lastSyncedAt,
        DateTime.now().toIso8601String(),
      );
    } finally {
      isSyncing.value = false;
      statusMessage.value = '';
    }
  }

  /// Re-syncs only the Party list's offline cache — used by the Sync
  /// button on the Party screen.
  Future<void> syncParty() =>
      _syncOne('Syncing parties…', _syncParties);

  /// Re-syncs only the Price List's offline cache — used by the Sync
  /// button on the Price Upload screen.
  Future<void> syncPriceList() =>
      _syncOne('Syncing price list…', _syncPriceList);

  /// Re-syncs only the Quotation list's offline cache (all three tabs) —
  /// used by the Sync button on the Quotation screen.
  Future<void> syncQuotations() =>
      _syncOne('Syncing quotations…', _syncQuotations);

  /// Re-syncs only the Estimation list's offline cache (all three tabs) —
  /// used by the Sync button on the Estimate screen.
  Future<void> syncEstimations() =>
      _syncOne('Syncing estimations…', _syncEstimations);

  /// Re-syncs only the Receipt list's offline cache (both tabs) — used by
  /// the Sync button on the Receipt screen.
  Future<void> syncReceipts() =>
      _syncOne('Syncing receipts…', _syncReceipts);

  /// Shared guard/cleanup around a single-module sync — mirrors
  /// [syncAll]'s isSyncing/lastError/statusMessage handling, but for just
  /// one section instead of all five. Doesn't touch [CacheKeys.lastSyncedAt]
  /// since that's meant to reflect a *full* sync, not a partial one.
  Future<void> _syncOne(String label, Future<void> Function() step) async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    lastError.value = null;
    try {
      await _runStep(label, step);
    } finally {
      isSyncing.value = false;
      statusMessage.value = '';
    }
  }

  Future<void> _runStep(String label, Future<void> Function() step) async {
    statusMessage.value = label;
    try {
      await step();
    } catch (e, st) {
      lastError.value = e.toString();
      developer.log(
        'Offline sync step failed: $label',
        error: e,
        stackTrace: st,
        name: 'DataSyncService',
      );
    }
  }

  /// Updates [statusMessage] with exactly what's being synced right now
  /// (e.g. "Syncing quotations — Draft"), for the top status strip in
  /// [AppScaffold] to display while [isSyncing] is true.
  void _announce(String message) {
    statusMessage.value = message;
  }

  /// Pushes anything in the pending-sync queue to `party.php` in one
  /// batch first — this is what the Sync button actually triggers per
  /// the offline-first design: queued adds/edits go out, and only once
  /// that succeeds (or there was nothing queued) does the party list get
  /// re-pulled and re-cached. If the push fails (network error, or a
  /// business-rule rejection such as a duplicate name), this throws and
  /// the pull below never runs — [_runStep] catches it, and the queue is
  /// left intact for the next Sync attempt.
  Future<void> _syncParties() async {
    _announce('Syncing parties');
    final creator = _sessionService.currentSession.value?.userId;
    if (creator != null && creator.isNotEmpty) {
      await _partyRepository.syncPendingParties(creator: creator);
    }

    final result = await _partyRepository.fetchLiveParties();
    // Cache every field `party_listing` gives us (not just id/name/state)
    // so editing a synced party later works entirely offline — see the
    // `_full` marker in `PartyListItem.fromJson`.
    final items = result.items
        .map((p) => {
              'party_id': p.partyId,
              'party_name': p.partyName,
              'state': p.state,
              'agent_id': p.agentId,
              'agent_name': p.agentName,
              'mobile_number': p.mobileNumber,
              'email': p.email,
              'identification': p.identification,
              'address': p.address,
              'district': p.district,
              'city': p.city,
              'others_city': p.othersCity,
              'pincode': p.pincode,
              'gst_number': p.gstNumber,
              'opening_balance': p.openingBalance,
              'opening_balance_type': p.openingBalanceType,
              'draft': p.isDraft ? '1' : '0',
              '_full': true,
            })
        .toList();
    await _cache.putJsonList(CacheKeys.party, items);
  }

  Future<void> _syncPriceList() async {
    _announce('Syncing price list');
    final pricelists = <String, Map<String, dynamic>>{};
    final products = <String, Map<String, dynamic>>{};
    final result = await _productPriceRepository.fetchLivePriceList();
    final rows = result.rows
        .map((r) => {
              'sno': r.sno,
              'pricelist_name': r.pricelistName,
              'product_name': r.productName,
              'price': r.price,
              'price_unit_name': r.unit,
              'discount': r.discountEnabled ? 'ON' : 'OFF',
            })
        .toList();
    for (final p in result.pricelists) {
      pricelists[p.id] = {'pricelist_id': p.id, 'pricelist_name': p.name};
    }
    for (final p in result.products) {
      products[p.id] = {'product_id': p.id, 'product_name': p.name};
    }
    await _cache.putJsonList(CacheKeys.priceRows, rows);
    await _cache.putJsonList(
        CacheKeys.priceLists, pricelists.values.toList());
    await _cache.putJsonList(CacheKeys.priceProducts, products.values.toList());
  }

  /// Pushes anything in the quotation pending-sync queue to
  /// `quotation.php` in one batch first — this is what the Sync button
  /// triggers per the offline-first design: queued adds/edits (draft or
  /// confirmed) go out, and only once that succeeds (or there was
  /// nothing queued) does the quotation list get re-pulled and
  /// re-cached, alongside a refresh of the pricelist/product catalogue
  /// the Add/Edit form reads offline. If the push fails, this throws and
  /// the pull below never runs — [_runStep]/[_syncOne] catch it, and the
  /// queue is left intact for the next Sync attempt.
  Future<void> _syncQuotations() async {
    final creator = _sessionService.currentSession.value?.userId;
    if (creator != null && creator.isNotEmpty) {
      // Push any custom products added from the Quotation product picker
      // first — a queued quotation line may reference one of these by
      // its locally-generated id as `product_id`, so the server needs to
      // know that id before the quotation batch below is sent.
      await _customProductRepository.syncPendingCustomProducts(
        module: CustomProductModule.quotation,
        creator: creator,
      );
      await _quotationRepository.syncPendingQuotations(creator: creator);
    }

    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String drafted,
      required String cancelled,
    }) async {
      _announce('Syncing quotations — $tabLabel');
      final result = await _quotationRepository.fetchLiveQuotations(
        drafted: drafted,
        cancelled: cancelled,
      );
      // Cache every field `quotation_listing` gives us (not just the
      // id/number/date/party/qty/total summary) so editing a synced
      // quotation later works entirely offline — see the `_full` marker
      // in `QuotationListItem.fromJson`.
      final items = result.items
          .map((q) => {
                'quotation_id': q.quotationId,
                'quotation_number': q.quotationNumber,
                'quotation_date': q.quotationDate,
                'party_name_mobile_city': q.partyNameMobileCity,
                'total_quantity': q.totalQuantity,
                'grand_total': q.grandTotal,
                'estimate_id': q.estimateId,
                'party_id': q.partyId,
                'pricelist_id': q.pricelistId,
                'pricelist_name': q.pricelistName,
                'agent_id': q.agentId,
                'product_id': q.products.map((p) => p.productId).join(','),
                'product_name': q.products.map((p) => p.productName).join(','),
                'product_quantity':
                    q.products.map((p) => p.quantity).join(','),
                'unit_id': q.products.map((p) => p.unitId).join(','),
                'unit_name': q.products.map((p) => p.unitName).join(','),
                'product_rate': q.products.map((p) => p.rate).join(','),
                'product_discount':
                    q.products.map((p) => p.productDiscount).join(','),
                'product_amount': q.products.map((p) => p.amount).join(','),
                'section1_add_value': q.section1AddValue,
                'section1_discount': q.section1Discount,
                'section2_add_value': q.section2AddValue,
                'section2_discount': q.section2Discount,
                'drafted': q.isDraft ? '1' : '0',
                '_full': true,
              })
          .toList();
      for (final p in result.partyList) {
        parties[p.id] = {'id': p.id, 'name': p.name};
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Quotation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.quotationActive, 'Active',
        drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.quotationDraft, 'Draft',
        drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.quotationCancel, 'Cancelled',
        drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.quotationParties, parties.values.toList());

    await _syncQuotationCatalogue();
  }

  /// Refreshes the pricelist dropdown + full per-pricelist product
  /// catalogue the Add/Edit Quotation form reads offline
  /// (`QuotationRepository.cachedPricelists`/`cachedProductsForPricelist`).
  /// One quick call for the pricelist list, then one call per pricelist
  /// for its products — for the small number of pricelists a business
  /// like this actually has, this stays fast; if that ever changes,
  /// this is the one place to add a size guard.
  Future<void> _syncQuotationCatalogue() async {
    _announce('Syncing quotation product catalogue');
    final init = await _quotationRepository.getFormInitData();
    await _cache.putJsonList(
      CacheKeys.quotationPricelists,
      init.pricelist.map((p) => {'id': p.id, 'name': p.name}).toList(),
    );

    final allProducts = <Map<String, dynamic>>[];
    for (final pricelist in init.pricelist) {
      final result =
          await _quotationRepository.getProductsForPricelist(pricelist.id);
      allProducts.addAll(result.products.map((p) => {
            'pricelist_id': pricelist.id,
            'product_id': p.productId,
            'product_name': p.productName,
            'unit_id': p.unitId,
            'unit_name': p.unitName,
            'rate': p.rate,
            'product_discount': p.productDiscount ? '1' : '0',
            'current_stock': p.currentStock,
          }));
    }
    await _cache.putJsonList(CacheKeys.quotationProducts, allProducts);
    await _syncCustomProductCatalogue();
  }

  /// Refreshes the category/unit dropdowns for the Add Custom Product
  /// form (shared by both the Quotation and Estimation product pickers)
  /// from `product.php`'s `add_custom_product` call. Called from both
  /// catalogue syncs — whichever of Quotation/Estimation Sync runs
  /// first keeps this current, so it never depends on a full [syncAll].
  Future<void> _syncCustomProductCatalogue() async {
    _announce('Syncing custom product options');
    try {
      final init = await _customProductRepository.getInitData();
      await _cache.putJsonList(
        CacheKeys.customProductCategories,
        init.categories.map((c) => {'id': c.id, 'name': c.name}).toList(),
      );
      await _cache.putJsonList(
        CacheKeys.customProductUnits,
        init.units.map((u) => {'id': u.id, 'name': u.name}).toList(),
      );
    } catch (_) {
      // Keep whatever was already cached rather than failing the whole
      // catalogue sync over this one lookup.
    }
  }

  /// Pushes anything in the pending-sync queue to `estimate.php` in one
  /// batch first — same reasoning as [_syncQuotations]: queued adds/edits
  /// (including an offline Cancel) go out, and only once that succeeds
  /// (or there was nothing queued) does the estimate list get re-pulled
  /// and re-cached. If the push fails, this throws and the pull below
  /// never runs — [_runStep]/[_syncOne] catch it, and the queue is left
  /// intact for the next Sync attempt.
  Future<void> _syncEstimations() async {
    final creator = _sessionService.currentSession.value?.userId;
    if (creator != null && creator.isNotEmpty) {
      // Same reasoning as `_syncQuotations`: push custom products added
      // from the Estimation product picker before the estimates that may
      // reference one of them by its locally-generated id.
      await _customProductRepository.syncPendingCustomProducts(
        module: CustomProductModule.estimation,
        creator: creator,
      );
      await _estimateRepository.syncPendingEstimates(creator: creator);
    }

    final agents = <String, Map<String, dynamic>>{};
    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String drafted,
      required String cancelled,
    }) async {
      _announce('Syncing estimations — $tabLabel');
      final result = await _estimateRepository.fetchLiveEstimates(
        drafted: drafted,
        cancelled: cancelled,
      );
      // Cache every field `estimate_listing` gives us (not just the
      // id/number/date/agent/party/qty/total summary) so editing a
      // synced estimate later works entirely offline — see the `_full`
      // marker in `EstimateListItem.fromJson`.
      final items = result.items
          .map((e) => {
                'estimate_id': e.estimateId,
                'estimate_number': e.estimateNumber,
                'estimate_date': e.estimateDate,
                'agent_name_mobile_city': e.agentNameMobileCity,
                'party_name_mobile_city': e.partyNameMobileCity,
                'total_quantity': e.totalQuantity,
                'grand_total': e.grandTotal,
                'receipt_id': e.receiptId,
                'party_id': e.partyId,
                'agent_id': e.agentId,
                'pricelist_id': e.pricelistId,
                'pricelist_name': e.pricelistName,
                'convert_quotation_id': e.convertQuotationId,
                'product_id': e.products.map((p) => p.productId).join(','),
                'product_name': e.products.map((p) => p.productName).join(','),
                'product_quantity':
                    e.products.map((p) => p.quantity).join(','),
                'unit_id': e.products.map((p) => p.unitId).join(','),
                'unit_name': e.products.map((p) => p.unitName).join(','),
                'product_rate': e.products.map((p) => p.rate).join(','),
                'product_discount':
                    e.products.map((p) => p.productDiscount).join(','),
                'product_amount': e.products.map((p) => p.amount).join(','),
                'section1_add_value': e.section1AddValue,
                'section1_discount': e.section1Discount,
                'section2_add_value': e.section2AddValue,
                'section2_discount': e.section2Discount,
                'other_charges_id':
                    e.charges.map((c) => c.chargeId).join(','),
                'other_charges_name':
                    e.charges.map((c) => c.chargeName).join(','),
                'other_charges_type': e.charges.map((c) => c.type).join(','),
                'other_charges_value':
                    e.charges.map((c) => c.value).join(','),
                'drafted': e.isDraft ? '1' : '0',
                '_full': true,
              })
          .toList();
      for (final a in result.agentList) {
        agents[a.id] = {'id': a.id, 'name': a.name};
      }
      for (final p in result.partyList) {
        parties[p.id] = {'id': p.id, 'name': p.name};
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Same three tabs as the Estimation list screen: Active, Draft, Cancel.
    await syncTab(CacheKeys.estimationActive, 'Active',
        drafted: '0', cancelled: '0');
    await syncTab(CacheKeys.estimationDraft, 'Draft',
        drafted: '1', cancelled: '0');
    await syncTab(CacheKeys.estimationCancel, 'Cancelled',
        drafted: '0', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.estimationAgents, agents.values.toList());
    await _cache.putJsonList(
        CacheKeys.estimationParties, parties.values.toList());

    // The fresh pull above only reflects a receipt that's itself already
    // synced — an estimate paid offline whose receipt hasn't gone
    // through yet would otherwise have its locally-set `receipt_id`
    // wiped back to empty here, briefly un-hiding its Receipt/Edit icons
    // until the next Sync. Re-stamp anything still in the receipt
    // pending-sync queue right away.
    await _receiptRepository.reapplyPendingConversions();

    await _syncEstimateCatalogue();
  }

  /// Refreshes the pricelist dropdown, the full per-pricelist product
  /// catalogue, and the other-charges dropdown (each charge's fixed
  /// "Plus"/"Minus" type resolved once here) that the Add/Edit Estimate
  /// form reads offline (`EstimateRepository.cachedPricelists`/
  /// `cachedProductsForPricelist`/`cachedOtherCharges`). Mirrors
  /// [_syncQuotationCatalogue] — one call for the pricelist + other-
  /// charges lists, then one call per pricelist for its products, then
  /// one call per other-charge for its type.
  Future<void> _syncEstimateCatalogue() async {
    _announce('Syncing estimate product catalogue');
    final init = await _estimateRepository.getFormInitData();
    await _cache.putJsonList(
      CacheKeys.estimationPricelists,
      init.pricelist.map((p) => {'id': p.id, 'name': p.name}).toList(),
    );

    final allProducts = <Map<String, dynamic>>[];
    for (final pricelist in init.pricelist) {
      final result =
          await _estimateRepository.getProductsForPricelist(pricelist.id);
      allProducts.addAll(result.products.map((p) => {
            'pricelist_id': pricelist.id,
            'product_id': p.productId,
            'product_name': p.productName,
            'unit_id': p.unitId,
            'unit_name': p.unitName,
            'rate': p.rate,
            'product_discount': p.productDiscount ? '1' : '0',
            'current_stock': p.currentStock,
          }));
    }
    await _cache.putJsonList(CacheKeys.estimationProducts, allProducts);

    final chargeRows = <Map<String, dynamic>>[];
    for (final charge in init.otherCharges) {
      String type = 'Plus';
      try {
        final typeResult = await _estimateRepository.getChargeType(charge.id);
        type = typeResult.chargesType;
      } catch (_) {
        // Keep the default "Plus" rather than failing the whole sync
        // over one charge's type lookup.
      }
      chargeRows.add({
        'other_charges_id': charge.id,
        'other_charges_name': charge.name,
        'charges_type': type,
      });
    }
    await _cache.putJsonList(CacheKeys.estimationOtherCharges, chargeRows);
    await _syncCustomProductCatalogue();
  }

  Future<void> _syncReceipts() async {
    final creator = _sessionService.currentSession.value?.userId;
    if (creator != null && creator.isNotEmpty) {
      // Sends every Receipt created offline against an estimate to
      // `receipt.php`, one at a time (see
      // `ReceiptRepository.syncPendingReceipts` for why — no batch
      // endpoint like Estimate/Quotation have). A failure here is
      // reported by `_runStep`/`_syncOne` like any other step, but
      // whatever already went through in the loop stays synced either
      // way.
      await _receiptRepository.syncPendingReceipts(creator: creator);
    }

    final parties = <String, Map<String, dynamic>>{};

    Future<void> syncTab(
      String cacheKey,
      String tabLabel, {
      required String cancelled,
    }) async {
      _announce('Syncing receipts — $tabLabel');
      final result = await _receiptRepository.fetchLiveReceipts(
        cancelled: cancelled,
      );
      final items = result.items
          .map((r) => {
                'receipt_id': r.receiptId,
                'receipt_number': r.receiptNumber,
                'receipt_date': r.receiptDate,
                'agent_name': r.agentName,
                'party_name': r.partyName,
                'total_amount': r.totalAmount,
                'against_bill_number': r.billNumber,
                'deduction': r.deduction,
                'narration': r.narration,
                'payment_mode_data': r.entries,
              })
          .toList();
      for (final p in result.partyList) {
        parties[p.id] = {'id': p.id, 'name': p.name};
      }
      await _cache.putJsonList(cacheKey, items);
    }

    // Receipts only have Active/Cancel — no draft state.
    await syncTab(CacheKeys.receiptActive, 'Active', cancelled: '0');
    await syncTab(CacheKeys.receiptCancel, 'Cancelled', cancelled: '1');
    await _cache.putJsonList(
        CacheKeys.receiptParties, parties.values.toList());

    // In case this step ran before `_syncEstimations` did (e.g. the user
    // tapped Sync from the Receipt screen, running only this step) —
    // keep any estimate whose receipt hasn't synced yet marked converted.
    await _receiptRepository.reapplyPendingConversions();

    await _syncReceiptCatalogue();
  }

  /// Refreshes the Payment Mode dropdown and, per mode, its linked Bank
  /// dropdown — cached so the Add Receipt form (`ReceiptController`)
  /// never needs the network. Mirrors [_syncEstimateCatalogue].
  Future<void> _syncReceiptCatalogue() async {
    _announce('Syncing receipt payment modes');
    final init = await _receiptRepository.getFormInitData();
    await _cache.putJsonList(
      CacheKeys.receiptPaymentModes,
      init.paymentModes.map((m) => {'id': m.id, 'name': m.name}).toList(),
    );

    final allBanks = <Map<String, dynamic>>[];
    for (final mode in init.paymentModes) {
      try {
        final result = await _receiptRepository.getBanksForPaymentMode(mode.id);
        allBanks.addAll(result.banks.map((b) => {
              'payment_mode_id': mode.id,
              'id': b.id,
              'name': b.name,
            }));
      } catch (_) {
        // Keep whatever banks were already cached for this mode rather
        // than failing the whole sync over one mode's bank lookup.
      }
    }
    await _cache.putJsonList(CacheKeys.receiptBanks, allBanks);
  }
}