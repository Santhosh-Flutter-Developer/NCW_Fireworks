import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ncw_fireworks/core/utils/pdf/estimate_pdf_builder.dart';
import 'package:ncw_fireworks/core/utils/pdf_downloader.dart';
import 'package:printing/printing.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/percent_amount_parser.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/custom_product/custom_product_models.dart';
import '../../data/models/estimate/estimate_product_list_response_model.dart';
import '../../data/models/estimate/id_name.dart';
import '../../data/models/estimation_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/quotation_model.dart';
import '../../data/respositories/custom_product_repository.dart';
import '../../data/respositories/estimate_repository.dart';
import '../../data/respositories/party_repository.dart';
import '../../routes/app_routes.dart';
import '../quotation/quotation_controller.dart';
import '../receipt/receipt_controller.dart';

/// The 3 tabs shown above the Estimate list on the web app.
///
/// Each tab maps to `estimate.php`'s `drafted`/`cancelled` filters on
/// `estimate_listing`: Active is `drafted=0, cancelled=0`, Draft is
/// `drafted=1, cancelled=0`, Cancel is `drafted=0, cancelled=1`.
enum EstimationTab { active, draft, cancel }

extension EstimationTabX on EstimationTab {
  String get label {
    switch (this) {
      case EstimationTab.active:
        return 'Active';
      case EstimationTab.draft:
        return 'Draft';
      case EstimationTab.cancel:
        return 'Cancel';
    }
  }
}

class EstimationController extends GetxController {
  EstimationController({
    EstimateRepository? estimateRepository,
    SessionService? sessionService,
    PartyRepository? partyRepository,
    CustomProductRepository? customProductRepository,
  })  : _estimateRepository = estimateRepository ?? EstimateRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>(),
        _partyRepository = partyRepository ?? PartyRepository(),
        _customProductRepository =
            customProductRepository ?? CustomProductRepository();

  final EstimateRepository _estimateRepository;
  final SessionService _sessionService;
  final PartyRepository _partyRepository;
  final CustomProductRepository _customProductRepository;

  static final DateFormat _apiDateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat _serverStoredDateFormat = DateFormat('yyyy-MM-dd');

  // ---- Shared dropdown data (populated by loadEstimates + the form's
  // init call — both come from the same endpoint's `head`, so either one
  // keeps these current). --------------------------------------------------
  final pricelistOptions = <IdName>[].obs;
  final agentOptions = <IdName>[].obs;
  final parties = <PartyModel>[].obs;
  final otherChargesOptions = <IdName>[].obs;
  final productOptions = <EstimateProductOption>[].obs;
  final isLoadingProducts = false.obs;

  // ---- Add Custom Product dropdown data (synced once at login/Sync via
  // `CustomProductRepository`/`DataSyncService`) --------------------------
  final customCategories = <CustomProductOption>[].obs;
  final customUnits = <CustomProductOption>[].obs;

  List<String> get pricelistNames =>
      pricelistOptions.map((e) => e.name).toList();
  List<String> get agents => agentOptions.map((e) => e.name).toList();

  /// Stock as of the last time each product was looked up via
  /// `selected_product_id`. `product_pricelist_id` (used to list
  /// products) doesn't return stock, so this is only known once a
  /// product's rate/unit has actually been fetched.
  final _stockCache = <String, int>{};
  int stockFor(String productId) => _stockCache[productId] ?? 0;

  /// Each cached other-charge's fixed "Plus"/"Minus" type (see
  /// `EstimateRepository.cachedOtherCharges`) — populated whenever
  /// dropdown data is loaded from cache, read by [addCharge] instead of a
  /// live `type_other_charges_id` call.
  final _chargeTypeById = <String, String>{};

  // ---- List screen state -------------------------------------------------
  final estimations = <EstimationModel>[].obs;
  final searchQuery = ''.obs;
  final activeTab = EstimationTab.active.obs;
  final isTableView = false.obs;
  final Rx<DateTime?> filterFrom = Rx<DateTime?>(null);
  final Rx<DateTime?> filterTo = Rx<DateTime?>(null);
  final Rx<String?> filterAgent = Rx<String?>(null); // agent *name*
  final Rx<String?> filterParty = Rx<String?>(null); // party *name*
  final pageSize = 10.obs;
  final currentPage = 1.obs;
  final isLoadingList = false.obs;

  /// The API doesn't return a total row/page count for `estimate_listing`
  /// — inferred the same way `PartyController` does: trust a full page
  /// means there's probably another one, and self-correct once the user
  /// reaches the real last page.
  final totalPagesRx = 1.obs;
  int get totalPages => totalPagesRx.value;

  /// Bumped on every `loadEstimates()` call; a response is only applied
  /// if it's still the most recent request when it comes back — guards
  /// against rapid page/filter/tab changes firing overlapping requests
  /// whose responses arrive out of order and clobber the current page.
  int _requestId = 0;

  Timer? _searchDebounce;

  // ---- Form state ---------------------------------------------------------
  EstimationModel? editingEstimation;

  /// Set while the Add Estimate form is bootstrapped from an active
  /// quotation (see [startConvertFromQuotation]). Sent back to the server
  /// as `convert_quotation_id` on save, so the new estimate is linked to
  /// its source quotation — which in turn hides that quotation's Convert/
  /// Edit/Delete actions once the list reloads.
  String? _convertQuotationId;
  bool get isConvertingFromQuotation =>
      _convertQuotationId != null && _convertQuotationId!.isNotEmpty;
  final Rx<PartyModel?> selectedParty = Rx<PartyModel?>(null);
  final Rx<String?> selectedAgent = Rx<String?>(null); // agent *name*
  final Rx<String?> selectedAgentId = Rx<String?>(null);
  final Rx<String?> selectedPricelist = Rx<String?>(null); // pricelist *name*
  final Rx<String?> selectedPricelistId = Rx<String?>(null);
  final Rx<DateTime> estimationDate = Rx<DateTime>(DateTime.now());
  final formItems = <BillingItemModel>[].obs;

  /// Free/no-charge "Compliment Products" added via the "+ Add
  /// Compliment Products" button on this form — kept entirely separate
  /// from [formItems] so they never affect [formSubTotal]/[formTotal].
  /// See [addComplimentSelections].
  final complimentItems = <ComplimentItemModel>[].obs;
  final section1Add = 0.0.obs;
  final section1Discount = 0.0.obs;
  final section2Add = 0.0.obs;
  final section2Discount = 0.0.obs;
  final charges = <ChargeLine>[].obs;
  final Rx<String?> selectedChargeId = Rx<String?>(null);
  final isLoadingForm = false.obs;
  final isSaving = false.obs;

  // Persistent controllers so typing doesn't lose focus/cursor position
  // when the totals card rebuilds on every keystroke.
  final section1AddCtrl = TextEditingController();
  final section1DiscountCtrl = TextEditingController();
  final section2AddCtrl = TextEditingController();
  final section2DiscountCtrl = TextEditingController();
  final chargeValueCtrl = TextEditingController();

  // Raw text last typed into the Discount fields — kept separately from
  // section1Discount/section2Discount (which always hold the *resolved*
  // rupee amount) so a "10%" entry can be re-resolved against the section
  // total whenever items are added/removed/edited, not just at typing time.
  String _section1DiscountRaw = '';
  String _section2DiscountRaw = '';

  @override
  void onInit() {
    super.onInit();
    // Re-resolve percentage-based discounts whenever the items backing a
    // section total change (add/remove/qty edit), so e.g. "10%" always
    // reflects 10% of the *current* section total rather than going stale.
    ever(formItems, (_) {
      section1Discount.value =
          resolvePercentOrAmount(_section1DiscountRaw, formSection1Total);
      section2Discount.value =
          resolvePercentOrAmount(_section2DiscountRaw, formSection2Total);
    });
    loadCustomProductDropdowns();
    resetForFreshVisit();
  }

  /// Category/unit dropdown options for the Add Custom Product form —
  /// read straight from the offline cache [DataSyncService] populates at
  /// login/Sync (`CustomProductRepository.cachedCategories`/
  /// [cachedUnits]). No network call, online or off.
  void loadCustomProductDropdowns() {
    customCategories.assignAll(_customProductRepository.cachedCategories());
    customUnits.assignAll(_customProductRepository.cachedUnits());
  }

  /// Called from the Discount text fields on every keystroke. Accepts a
  /// plain amount ("150") or a percentage of the section total ("10%").
  void setSection1DiscountInput(String raw) {
    _section1DiscountRaw = raw;
    section1Discount.value = resolvePercentOrAmount(raw, formSection1Total);
  }

  void setSection2DiscountInput(String raw) {
    _section2DiscountRaw = raw;
    section2Discount.value = resolvePercentOrAmount(raw, formSection2Total);
  }

  /// Called every time the Estimate list screen is freshly entered via
  /// navigation (see `_EstimationListFreshVisit` in
  /// `estimation_list_view.dart`). GetX only disposes a `lazyPut`
  /// controller once every route bound to it has been fully popped — if
  /// the sidebar pushes `/estimation` again while an earlier visit is
  /// still further down the Navigator stack, the *same* controller
  /// instance gets reused and `onInit()` never runs a second time. This
  /// puts it back to a clean slate regardless — search text cleared, page
  /// size back to 10, first page, Active tab, both date filters cleared,
  /// "All Agents"/"All Partys" selected, list view (not table view) —
  /// then reloads. Works the same online or offline since [loadEstimates]
  /// already falls back to the local cache when there's no connection.
  void resetForFreshVisit() {
    _searchDebounce?.cancel();
    searchQuery.value = '';
    pageSize.value = 10;
    currentPage.value = 1;
    activeTab.value = EstimationTab.active;
    filterFrom.value = null;
    filterTo.value = null;
    filterAgent.value = null;
    filterParty.value = null;
    isTableView.value = false;
    loadEstimates();
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    section1AddCtrl.dispose();
    section1DiscountCtrl.dispose();
    section2AddCtrl.dispose();
    section2DiscountCtrl.dispose();
    chargeValueCtrl.dispose();
    super.onClose();
  }

  /// Pushes the current rx money values into their text controllers.
  /// Called only when the form is reset/loaded — never on every keystroke —
  /// so typing doesn't fight the controller or lose cursor position.
  void _syncMoneyControllers() {
    String fmt(double v) => v == 0 ? '' : v.toStringAsFixed(2);
    section1AddCtrl.text = fmt(section1Add.value);
    section1DiscountCtrl.text = fmt(section1Discount.value);
    section2AddCtrl.text = fmt(section2Add.value);
    section2DiscountCtrl.text = fmt(section2Discount.value);
    // Loaded/reset discounts are always plain resolved amounts, never a
    // percentage — keep the raw trackers in step so the next items-change
    // re-resolve doesn't reapply a stale "%" against the new total.
    _section1DiscountRaw = section1DiscountCtrl.text;
    _section2DiscountRaw = section2DiscountCtrl.text;
  }

  // ---- List loading / filtering / pagination ------------------------------

  String? _agentIdForName(String? name) {
    if (name == null) return null;
    return agentOptions.firstWhereOrNull((a) => a.name == name)?.id;
  }

  String? _partyIdForName(String? name) {
    if (name == null) return null;
    return parties.firstWhereOrNull((p) => p.name == name)?.serverPartyId;
  }

  /// Strips the odd bit of HTML the server sends for a `Direct` agent
  /// (`<span class="text-primary">Direct</span>`) down to plain text.
  String _stripHtml(String raw) => raw.replaceAll(RegExp(r'<[^>]*>'), '');

  Future<void> loadEstimates() async {
    final requestId = ++_requestId;
    isLoadingList.value = true;
    try {
      final result = await _estimateRepository.listEstimates(
        filterFromDate: filterFrom.value != null
            ? _apiDateFormat.format(filterFrom.value!)
            : '',
        filterToDate: filterTo.value != null
            ? _apiDateFormat.format(filterTo.value!)
            : '',
        searchText: searchQuery.value.trim(),
        filterAgentId: _agentIdForName(filterAgent.value) ?? '',
        filterPartyId: _partyIdForName(filterParty.value) ?? '',
        pageNumber: currentPage.value,
        pageLimit: pageSize.value,
        drafted: activeTab.value == EstimationTab.draft ? '1' : '0',
        cancelled: activeTab.value == EstimationTab.cancel ? '1' : '0',
      );
      if (requestId != _requestId) return; // A newer request has since started.

      final rowStatus = switch (activeTab.value) {
        EstimationTab.active => DocStatus.active,
        EstimationTab.draft => DocStatus.draft,
        EstimationTab.cancel => DocStatus.cancelled,
      };

      if (result.agentList.isNotEmpty) {
        agentOptions.assignAll(result.agentList);
      }
      if (result.partyList.isNotEmpty) {
        parties.assignAll(result.partyList.map((p) => PartyModel(
              id: p.id,
              serverPartyId: p.id,
              name: p.name.isEmpty ? 'Untitled Party' : p.name,
              hasFullDetails: false,
            )));
      }

      estimations.assignAll(result.items.map((item) {
        DateTime date;
        try {
          // Pending (not-yet-synced) rows are stored as dd-MM-yyyy (see
          // EstimateRepository.queueEstimateForSync); synced rows come
          // back from the server as yyyy-MM-dd. Picking the format
          // directly by [item.isPending] avoids the bug where
          // DateFormat('yyyy-MM-dd').parse(...) — the *lenient* parse,
          // not parseStrict — silently "succeeds" on a dd-MM-yyyy string
          // by reinterpreting its digit groups as year/month/day in the
          // wrong order (e.g. "21-07-2026" misread as year 21, causing
          // the day component to overflow into a garbage date), instead
          // of throwing and falling through to the correct format.
          date = item.isPending
              ? _apiDateFormat.parseStrict(item.estimateDate)
              : _serverStoredDateFormat.parseStrict(item.estimateDate);
        } catch (_) {
          try {
            date = _apiDateFormat.parseStrict(item.estimateDate);
          } catch (_) {
            try {
              date = _serverStoredDateFormat.parseStrict(item.estimateDate);
            } catch (_) {
              date = DateTime.now();
            }
          }
        }
        final party = _stripHtml(item.partyNameMobileCity).trim();
        final agent = _stripHtml(item.agentNameMobileCity).trim();
        final knownFullDetails = item.isPending || item.hasFullDetails;
        return EstimationModel(
            id: item.isPending ? item.localId : item.estimateId,
            estimationNo: item.estimateNumber,
            serverEstimateId: item.estimateId.isEmpty ? null : item.estimateId,
            partyId: item.partyId,
            partyName: party.isEmpty ? 'Direct' : party,
            agentId: item.agentId,
            agentName: agent.isEmpty ? 'Direct' : agent,
            pricelistId: item.pricelistId,
            pricelistName: item.pricelistName,
            date: date,
            items: item.products
                .map((p) => BillingItemModel(
                      productId: p.productId,
                      productName: p.productName,
                      quantity: int.tryParse(p.quantity) ?? 1,
                      rate: double.tryParse(p.rate) ?? 0,
                      unit: p.unitName,
                      unitId: p.unitId,
                      section: p.productDiscount == '1' ? 1 : 2,
                    ))
                .toList(),
            complimentItems: item.complimentProducts
                .map((c) => ComplimentItemModel(
                      productId: c.productId,
                      productName: c.productName,
                      quantity: int.tryParse(c.quantity) ?? 1,
                      unit: c.unitName,
                      unitId: c.unitId,
                    ))
                .toList(),
            status: rowStatus,
            section1Add: double.tryParse(item.section1AddValue) ?? 0,
            section1Discount: double.tryParse(item.section1Discount) ?? 0,
            section2Add: double.tryParse(item.section2AddValue) ?? 0,
            section2Discount: double.tryParse(item.section2Discount) ?? 0,
            charges: item.charges
                .map((c) => ChargeLine(
                      name: c.chargeName,
                      value: c.type == 'Minus'
                          ? -(double.tryParse(c.value) ?? 0).abs()
                          : (double.tryParse(c.value) ?? 0).abs(),
                      chargeId: c.chargeId,
                      type: c.type.isEmpty ? 'Plus' : c.type,
                    ))
                .toList(),
            // A pending row's total/qty aren't known server-side yet —
            // let EstimationModel derive them from its own items instead
            // of reading a stale/zero server value.
            serverGrandTotal: item.isPending ? null : item.grandTotal,
            serverQtyLabel: item.isPending ? null : item.totalQuantity,
            receiptId: item.receiptId,
            convertQuotationId: item.convertQuotationId,
            isPending: item.isPending,
            localId: item.isPending ? item.localId : null,
            // A row cached by an older build of this app only has the
            // summary fields — not safe to re-save without fetching the
            // rest first (see EstimationController.startEdit).
            hasFullDetails: knownFullDetails);
      }));

      // Prefer the known total row count derived from the last sync (see
      // EstimateRepository._cachedTotalCount) — this stays fixed while
      // paging instead of growing by one every time Next is tapped. Only
      // falls back to inferring from "was this page full" when nothing's
      // been synced yet to count against.
      final totalRecords = result.totalRecords;
      totalPagesRx.value = totalRecords != null
          ? (totalRecords <= 0
              ? 1
              : (totalRecords / pageSize.value).ceil())
          : (result.items.length < pageSize.value
              ? currentPage.value
              : currentPage.value + 1);
    } on ApiRequestException catch (e) {
      if (requestId != _requestId) return;
      final looksLikeEmptyResult = e.message.toLowerCase().contains('no') &&
          (e.message.toLowerCase().contains('record') ||
              e.message.toLowerCase().contains('estimate') ||
              e.message.toLowerCase().contains('data'));
      estimations.clear();
      totalPagesRx.value = 1;
      if (!looksLikeEmptyResult) {
        Get.snackbar('Could not load estimates', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } on ApiException catch (e) {
      if (requestId != _requestId) return;
      estimations.clear();
      totalPagesRx.value = 1;
      Get.snackbar('Could not load estimates', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (requestId == _requestId) isLoadingList.value = false;
    }
  }

  /// The current page's rows, as returned by the server — the list view
  /// still calls this `pagedFiltered` to match its existing layout code.
  List<EstimationModel> get pagedFiltered => estimations;

  void setSearch(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      currentPage.value = 1;
      loadEstimates();
    });
  }

  void setTab(EstimationTab tab) {
    activeTab.value = tab;
    // See the class doc comment on [EstimationTab] — the server doesn't
    // expose a status to filter by, so this just re-fetches page 1.
    currentPage.value = 1;
    loadEstimates();
  }

  void setDateFrom(DateTime? date) {
    filterFrom.value = date;
    currentPage.value = 1;
    loadEstimates();
  }

  void setDateTo(DateTime? date) {
    filterTo.value = date;
    currentPage.value = 1;
    loadEstimates();
  }

  void setAgentFilter(String? agent) {
    filterAgent.value = agent;
    currentPage.value = 1;
    loadEstimates();
  }

  void setPartyFilter(String? party) {
    filterParty.value = party;
    currentPage.value = 1;
    loadEstimates();
  }

  void setPageSize(int size) {
    pageSize.value = size;
    currentPage.value = 1;
    loadEstimates();
  }

  void setPageNo(int page) {
    if (isLoadingList.value || page == currentPage.value) return;
    currentPage.value = page;
    loadEstimates();
  }

  void goToPage(int page) => setPageNo(page.clamp(1, totalPages));

  void toggleViewMode(bool table) => isTableView.value = table;

  /// Whether the server has ever confirmed [estimation] — false only for
  /// one still sitting purely in the pending-sync queue, never yet sent.
  /// A pending *edit* of an already-synced estimate still counts as
  /// known, since cancelling it means queuing a `cancelled: "1"` update
  /// for that existing estimate, not just dropping local state. Used by
  /// the list view to show accurate confirm-dialog text for
  /// [deleteEstimation].
  bool isKnownToServer(EstimationModel estimation) {
    final estimateId =
        estimation.serverEstimateId ?? estimation.localId ?? estimation.id;
    return estimateId.isNotEmpty &&
        _estimateRepository.existsInSyncedCache(estimateId);
  }

  /// Cancels an estimate — confirmed (Active) or Draft alike — mirroring
  /// the server's own `drafted`/`cancelled` flags.
  ///
  /// Cancel is offline-first for both, just like Add/Edit: cancelling an
  /// estimate the server already knows about queues a
  /// `drafted: "0"` / `cancelled: "1"` update in the same pending-sync
  /// batch (see [EstimateRepository.queueEstimateForSync]) and moves it
  /// to the Cancel tab immediately — only a Sync tap actually tells the
  /// server. This is the same shape whether the estimate being
  /// cancelled was a Draft or already Active. An estimate the server has
  /// never confirmed (still only in the pending-sync queue) just has
  /// its queue entry dropped — there's nothing server-side yet to
  /// cancel.
  Future<void> deleteEstimation(EstimationModel estimation) async {
    final id = estimation.serverEstimateId ?? estimation.localId ?? estimation.id;
    final knownToServer = isKnownToServer(estimation);

    if (estimation.isPending && !knownToServer) {
      estimations.remove(estimation);
      if (estimation.localId != null) {
        await _estimateRepository.removePendingEstimate(estimation.localId!);
      }
      Get.snackbar(
        'Removed from view',
        '${estimation.estimationNo.isEmpty ? "This estimate" : estimation.estimationNo} was removed before it was ever synced.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (id.isEmpty) {
      estimations.remove(estimation);
      return;
    }

    // Known to the server — cancel offline, Draft or Active alike.
    // Queues the same full row a save would (so an edit already sitting
    // in the queue, not yet synced, is updated in place rather than
    // duplicated), just with `drafted: '0'` / `cancelled: '1'` — the
    // server's own on-cancel shape, same for a Draft or an Active
    // estimate being cancelled.
    await _estimateRepository.queueEstimateForSync(
      localId: id,
      editId: id,
      estimateNumber: estimation.estimationNo,
      convertQuotationId: estimation.convertQuotationId,
      drafted: '0',
      cancelled: true,
      estimateDate: _apiDateFormat.format(estimation.date),
      pricelistId: estimation.pricelistId,
      pricelistName: estimation.pricelistName,
      agentId: estimation.agentId,
      agentName: estimation.agentName,
      partyId: estimation.partyId,
      partyName: estimation.partyName,
      products: estimation.items
          .map((i) => {
                'product_id': i.productId,
                'product_name': i.productName,
                'unit_id': i.unitId,
                'unit_name': i.unit,
                'product_quantity': i.quantity.toString(),
                'product_rate': i.rate.toString(),
                'product_discount': i.section == 1 ? '1' : '0',
              })
          .toList(),
      section1AddValue:
          estimation.section1Add == 0 ? '' : estimation.section1Add.toString(),
      section1Discount: estimation.section1Discount == 0
          ? ''
          : estimation.section1Discount.toString(),
      section2AddValue:
          estimation.section2Add == 0 ? '' : estimation.section2Add.toString(),
      section2Discount: estimation.section2Discount == 0
          ? ''
          : estimation.section2Discount.toString(),
      charges: estimation.charges
          .map((c) => EstimateChargeLine(
                chargeId: c.chargeId,
                type: c.type,
                value: c.value.abs().toString(),
                name: c.name,
              ))
          .toList(),
    );

    estimations.remove(estimation);
    Get.snackbar(
      'Cancelled offline',
      'Will be sent to the server next time you Sync.',
      snackPosition: SnackPosition.BOTTOM,
    );
    await loadEstimates();
  }

  // ---- Print / download report PDF ----------------------------------------

  /// Builds the A4 estimate PDF entirely on-device (see
  /// [EstimatePdfBuilder]) — no network call, so this works the same
  /// whether or not the device is online, and whether or not this
  /// estimate has even been synced yet.
  Future<Uint8List> _buildEstimatePdfBytes(EstimationModel estimation) {
    final party = _partyRepository.cachedPartyById(estimation.partyId);
    return EstimatePdfBuilder.build(estimate: estimation, party: party);
  }

  /// Opens the native print/preview dialog for [estimation]'s A4 report.
  Future<void> printEstimate(EstimationModel estimation) async {
    try {
      final bytes = await _buildEstimatePdfBytes(estimation);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e, st) {
      debugPrint('printEstimate failed: $e\n$st');
      _showPdfErrorDialog('Could not print', e, st);
    }
  }

  Future<void> downloadEstimate(EstimationModel estimation) async {
    try {
      final bytes = await _buildEstimatePdfBytes(estimation);
      await PdfDownloader.saveBytes(
        bytes: bytes,
        fileName: estimation.estimationNo.isEmpty
            ? 'Estimate'
            : estimation.estimationNo,
      );
      Get.snackbar('Downloaded', 'Estimate report saved',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e, st) {
      debugPrint('downloadEstimate failed: $e\n$st');
      _showPdfErrorDialog('Could not download', e, st);
    }
  }

  /// See `QuotationController._showPdfErrorDialog` — a Snackbar
  /// truncates long text, which hid the actual exception behind a
  /// generic message more than once; this shows the full error (and
  /// stack trace, selectable/copyable) in a scrollable dialog instead.
  void _showPdfErrorDialog(String title, Object error, StackTrace st) {
    Get.dialog(
      AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText('$error\n\n$st'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---- Receipt shortcut -----------------------------------------------------

  /// Opens Add Receipt pre-filled with this estimate's own bill number —
  /// the Receipt icon on the Estimate list. Mirrors how `convertToEstimate`
  /// on `QuotationController` reaches across into another module's
  /// controller: `ReceiptController` is normally registered lazily the
  /// first time the Receipt module's own binding runs, so put it directly
  /// here too in case this is tapped before Receipt has ever been opened.
  bool _isPayReceiptInFlight = false;
  Future<void> payReceipt(EstimationModel estimation) async {
    if (_isPayReceiptInFlight)
      return; // ignore double taps while we're already working
    _isPayReceiptInFlight = true;
    try {
      final receiptController = Get.isRegistered<ReceiptController>()
          ? Get.find<ReceiptController>()
          : Get.put(ReceiptController());
      await receiptController.startCreate(
          prefillBillNumber: estimation.estimationNo,
          // Same id EstimationModel.id resolves to either way (synced
          // row's server id, or a not-yet-synced row's own local_id) —
          // lets the receipt form flip this exact estimate's
          // `isConverted` the moment it's saved, offline included.
          prefillEstimateId: estimation.serverEstimateId ?? estimation.id);
      Get.toNamed(AppRoutes.receiptForm);
    } finally {
      _isPayReceiptInFlight = false;
    }
  }

  // ---- Form: totals ---------------------------------------------------------

  double get formSection1Total => formItems
      .where((i) => i.section == 1)
      .fold(0.0, (sum, i) => sum + i.amount);
  double get formSection2Total => formItems
      .where((i) => i.section == 2)
      .fold(0.0, (sum, i) => sum + i.amount);
  double get formSubTotal => formSection1Total + formSection2Total;
  double get formAdjustments =>
      (section1Add.value - section1Discount.value) +
      (section2Add.value - section2Discount.value);
  double get formChargesTotal => charges.fold(0.0, (sum, c) => sum + c.value);

  /// Automatically rounds the pre-round total to the nearest whole rupee —
  /// no more manual entry. Positive when the total rounds up, negative
  /// when it rounds down.
  double get roundOff {
    final preRound = formSubTotal + formAdjustments + formChargesTotal;
    return double.parse((preRound.roundToDouble() - preRound).toStringAsFixed(2));
  }

  double get formTotal => formSubTotal + formAdjustments + formChargesTotal + roundOff;

  // ---- Form: charges --------------------------------------------------------

  /// Adds the chosen other-charge with its "Plus"/"Minus" sign. Normally
  /// read straight from [_chargeTypeById] (cached offline — see
  /// [_loadDropdownDataFromCache]) with no network call; only falls back
  /// to a live `type_other_charges_id` lookup when the charge type isn't
  /// cached, which only happens on the legacy `_loadFormInit` fallback
  /// path (see its doc comment).
  Future<void> addCharge(double rawValue) async {
    final chargeId = selectedChargeId.value;
    if (chargeId == null || rawValue == 0) {
      Get.snackbar('Select a charge', 'Choose a charge type and value',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    final option =
        otherChargesOptions.firstWhereOrNull((c) => c.id == chargeId);
    if (option == null) return;

    String type;
    final cachedType = _chargeTypeById[chargeId];
    if (cachedType != null) {
      type = cachedType;
    } else {
      try {
        type = (await _estimateRepository.getChargeType(chargeId)).chargesType;
      } on ApiRequestException catch (e) {
        Get.snackbar('Could not add charge', e.message,
            snackPosition: SnackPosition.BOTTOM);
        return;
      } on ApiException catch (e) {
        Get.snackbar('Could not add charge', e.message,
            snackPosition: SnackPosition.BOTTOM);
        return;
      }
    }

    final signedValue = type == 'Minus' ? -rawValue.abs() : rawValue.abs();
    charges.add(ChargeLine(
      name: option.name,
      value: signedValue,
      chargeId: chargeId,
      type: type,
    ));
    selectedChargeId.value = null;
    chargeValueCtrl.clear();
  }

  void removeCharge(int index) => charges.removeAt(index);

  // ---- Form: pricelist / agent selection -------------------------------

  void selectPricelist(IdName pricelist) {
    if (selectedPricelistId.value == pricelist.id) return;
    selectedPricelistId.value = pricelist.id;
    selectedPricelist.value = pricelist.name;
    loadProductsForSelectedPricelist();
  }

  void selectAgent(IdName? agent) {
    selectedAgentId.value = agent?.id;
    selectedAgent.value = agent?.name;
  }

  /// Products offered under the selected pricelist, for the "Add Item"
  /// picker — read straight from the offline catalogue [DataSyncService]
  /// caches at login/Sync (`EstimateRepository.cachedProductsForPricelist`).
  /// No network call, online or off. Also folds in any custom products
  /// added for this pricelist that haven't been synced yet (see
  /// [addCustomProduct]) — including ones added from the Quotation
  /// picker, since the queue is shared — so they keep showing up here
  /// across tab switches, app restarts, and the other module, exactly
  /// like an ordinary catalogue product. Listed *first*, ahead of the
  /// synced catalogue, so a newly-added custom product is immediately
  /// visible at the top of the picker instead of buried after every
  /// catalogue product.
  Future<void> loadProductsForSelectedPricelist() async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      productOptions.clear();
      return;
    }
    final catalogue =
        _estimateRepository.cachedProductsForPricelist(pricelistId);
    final custom = _customProductRepository
        .cachedCustomProductsForPricelist(pricelistId)
        .map(EstimateProductOption.fromCustomRow);
    productOptions.assignAll([...custom, ...catalogue]);
  }

  /// Adds a new custom product — from the Add Custom Product form opened
  /// off the product picker — to the pricelist currently selected there.
  /// Offline-only, always: the product is queued via
  /// [CustomProductRepository.queueCustomProduct] (a queue shared with
  /// Quotation, so this product shows up there too — see
  /// [loadProductsForSelectedPricelist]) and only ever sent to
  /// `product.php` when the person taps Sync on either screen (see
  /// `DataSyncService`). The generated [IdGenerator] id doubles as this
  /// product's permanent id from here on, so it can be picked and added
  /// to the estimate immediately, with no network round trip.
  ///
  /// Returns the newly created [EstimateProductOption] (or `null` on
  /// failure) so the product picker can select it right away, the same
  /// as tapping "Add to Cart" on an ordinary product.
  Future<EstimateProductOption?> addCustomProduct({
    required String categoryId,
    required String categoryName,
    required String productName,
    required String unitId,
    required String unitName,
    required double price,
  }) async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      Get.snackbar('Select a pricelist',
          'Choose a pricelist before adding a custom product',
          snackPosition: SnackPosition.BOTTOM);
      return null;
    }

    final editId = IdGenerator.generate();
    await _customProductRepository.queueCustomProduct(
      editId: editId,
      categoryId: categoryId,
      categoryName: categoryName,
      productName: productName,
      unitId: unitId,
      unitName: unitName,
      pricelistId: pricelistId,
      price: price.toString(),
    );
    await loadProductsForSelectedPricelist();
    return productOptions.firstWhereOrNull((p) => p.productId == editId);
  }

  // ---- Form: create / edit bootstrap ------------------------------------

  void _resetFormFields() {
    selectedParty.value = null;
    selectedAgent.value = null;
    selectedAgentId.value = null;
    selectedPricelist.value = null;
    selectedPricelistId.value = null;
    estimationDate.value = DateTime.now();
    formItems.clear();
    complimentItems.clear();
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    charges.clear();
    selectedChargeId.value = null;
    productOptions.clear();
    _syncMoneyControllers();
  }

  /// Called after the "+ Add Party" flow (opened from this form's Party
  /// field) creates a new party — or edits one, if that flow is ever
  /// reused for editing. Merges it into the local `parties` dropdown
  /// list (so it's selectable again if the picker is reopened) and
  /// selects it immediately, without needing a network round-trip.
  void addAndSelectParty(PartyModel party) {
    final idx = parties.indexWhere((p) =>
        (party.serverPartyId != null &&
            party.serverPartyId!.isNotEmpty &&
            p.serverPartyId == party.serverPartyId) ||
        (party.localId != null && p.localId == party.localId) ||
        p.id == party.id);
    if (idx == -1) {
      parties.insert(0, party);
    } else {
      parties[idx] = party;
    }
    selectedParty.value = party;
  }

  void startCreate() {
    editingEstimation = null;
    _convertQuotationId = null;
    _resetFormFields();
    _loadDropdownDataFromCache();
    if (pricelistOptions.isNotEmpty) {
      // New estimate — default to the first pricelist, matching the web
      // app's Add Estimate screen.
      selectedPricelistId.value = pricelistOptions.first.id;
      selectedPricelist.value = pricelistOptions.first.name;
      loadProductsForSelectedPricelist();
    }
    _syncMoneyControllers();
  }

  /// Opens the Edit form for [estimation]. The offline cache now carries
  /// every field `estimate_listing` returns (see `DataSyncService`/
  /// `EstimateListItem`), and every pending (not-yet-synced) row is fully
  /// known too — so this populates the form directly and works with no
  /// network call at all in the normal case. The `show_estimate_id` fetch
  /// below only ever runs for a row cached by an older build of this app
  /// (before full details were stored) that hasn't been refreshed by a
  /// sync yet; it's a one-time fallback, not something the offline-first
  /// flow depends on.
  void startEdit(EstimationModel estimation) {
    editingEstimation = estimation;
    _convertQuotationId =
        estimation.convertQuotationId.isEmpty ? null : estimation.convertQuotationId;
    _resetFormFields();
    _loadDropdownDataFromCache();
    estimationDate.value = estimation.date;

    if (estimation.hasFullDetails) {
      _populateFormFromModel(estimation);
      return;
    }

    isLoadingForm.value = true;
    _loadFormInit(showEstimateId: estimation.serverEstimateId ?? estimation.id);
  }

  /// Loads pricelist/agent/party/other-charges dropdown options from the
  /// offline cache that [DataSyncService] refreshes at login and via
  /// Sync — no network call.
  void _loadDropdownDataFromCache() {
    pricelistOptions.assignAll(_estimateRepository.cachedPricelists());
    agentOptions.assignAll(_estimateRepository.cachedAgents());
    parties.assignAll(_estimateRepository.cachedParties().map((p) => PartyModel(
          id: p.id,
          serverPartyId: p.id,
          name: p.name.isEmpty ? 'Untitled Party' : p.name,
          hasFullDetails: false,
        )));
    final cachedCharges = _estimateRepository.cachedOtherCharges();
    otherChargesOptions
        .assignAll(cachedCharges.map((c) => IdName(id: c.id, name: c.name)));
    _chargeTypeById
      ..clear()
      ..addEntries(cachedCharges.map((c) => MapEntry(c.id, c.type)));
  }

  /// Populates the form directly from [estimation]'s own fields — used
  /// whenever [estimation] already has full details (every pending row,
  /// and every row synced since this app started caching full details).
  void _populateFormFromModel(EstimationModel estimation) {
    if (estimation.pricelistId.isNotEmpty) {
      selectedPricelistId.value = estimation.pricelistId;
      final pl = pricelistOptions
          .firstWhereOrNull((p) => p.id == estimation.pricelistId);
      selectedPricelist.value = pl?.name ??
          (estimation.pricelistName.isEmpty ? null : estimation.pricelistName);
    }
    if (estimation.agentId.isNotEmpty) {
      selectedAgentId.value = estimation.agentId;
      final ag =
          agentOptions.firstWhereOrNull((a) => a.id == estimation.agentId);
      selectedAgent.value = ag?.name ?? estimation.agentName;
    }
    if (estimation.partyId.isNotEmpty) {
      selectedParty.value = parties
              .firstWhereOrNull((p) => p.serverPartyId == estimation.partyId) ??
          PartyModel(
            id: estimation.partyId,
            serverPartyId: estimation.partyId,
            name: estimation.partyName,
            hasFullDetails: false,
          );
    }

    formItems.assignAll(estimation.items
        .map((i) => BillingItemModel(
              productId: i.productId,
              productName: i.productName,
              quantity: i.quantity,
              rate: i.rate,
              unit: i.unit,
              unitId: i.unitId,
              section: i.section,
            ))
        .toList());

    complimentItems.assignAll(estimation.complimentItems
        .map((c) => ComplimentItemModel(
              productId: c.productId,
              productName: c.productName,
              quantity: c.quantity,
              unit: c.unit,
              unitId: c.unitId,
              isCustom: c.isCustom,
            ))
        .toList());

    section1Add.value = estimation.section1Add;
    section1Discount.value = estimation.section1Discount;
    section2Add.value = estimation.section2Add;
    section2Discount.value = estimation.section2Discount;
    charges.assignAll(estimation.charges);
    _syncMoneyControllers();

    if (selectedPricelistId.value != null &&
        selectedPricelistId.value!.isNotEmpty) {
      loadProductsForSelectedPricelist();
    }
  }

  /// Bootstraps a brand-new Add Estimate form pre-filled from an active
  /// [quotation]'s own party/pricelist/products — the "Convert to
  /// Estimate" action on the Quotation list. The quotation's own id
  /// (server id once known, otherwise its local id) is kept and sent
  /// back as `convert_quotation_id` when the form is saved.
  ///
  /// Offline-first, mirroring [startEdit]: every quotation row already
  /// carries its own full details (either from the offline cache
  /// `DataSyncService` refreshes at login/Sync, or — for a row not yet
  /// synced — straight from the on-device pending queue), so this reads
  /// [quotation]'s fields directly with no network call in the normal
  /// case. The `show_estimate_id`/`convert_quotation_id` call below only
  /// ever runs for a quotation row cached by an older app version (before
  /// full details were stored) that hasn't been refreshed by a Sync yet
  /// — a one-time backward-compat fallback, not something this flow
  /// depends on.
  void startConvertFromQuotation(QuotationModel quotation) {
    editingEstimation = null;
    final id = quotation.serverQuotationId ?? quotation.id;
    _convertQuotationId = id;
    _resetFormFields();
    _loadDropdownDataFromCache();
    estimationDate.value = quotation.date;

    if (quotation.hasFullDetails) {
      _populateFormFromQuotation(quotation);
      return;
    }

    isLoadingForm.value = true;
    _loadFormInit(showEstimateId: '', convertQuotationId: id);
  }

  /// Populates the Add Estimate form directly from [quotation]'s own
  /// party/pricelist/items/section totals — the offline counterpart of
  /// [_populateFormFromModel], used by [startConvertFromQuotation]
  /// whenever the source quotation already has full details. Quotations
  /// don't carry other-charges, agent, or a stored total (those exist
  /// only for estimates), so — matching a brand-new estimate — those
  /// are left at their [_resetFormFields] defaults for the user to add.
  void _populateFormFromQuotation(QuotationModel quotation) {
    if (quotation.pricelistId.isNotEmpty) {
      selectedPricelistId.value = quotation.pricelistId;
      final pl = pricelistOptions
          .firstWhereOrNull((p) => p.id == quotation.pricelistId);
      selectedPricelist.value = pl?.name ??
          (quotation.pricelistName.isEmpty ? null : quotation.pricelistName);
    }
    if (quotation.partyId.isNotEmpty) {
      selectedParty.value = parties
              .firstWhereOrNull((p) => p.serverPartyId == quotation.partyId) ??
          PartyModel(
            id: quotation.partyId,
            serverPartyId: quotation.partyId,
            name: quotation.partyName,
            hasFullDetails: false,
          );
    }

    formItems.assignAll(quotation.items
        .map((i) => BillingItemModel(
              productId: i.productId,
              productName: i.productName,
              quantity: i.quantity,
              rate: i.rate,
              unit: i.unit,
              unitId: i.unitId,
              section: i.section,
            ))
        .toList());

    section1Add.value = quotation.section1Add;
    section1Discount.value = quotation.section1Discount;
    section2Add.value = quotation.section2Add;
    section2Discount.value = quotation.section2Discount;
    _syncMoneyControllers();

    if (selectedPricelistId.value != null &&
        selectedPricelistId.value!.isNotEmpty) {
      loadProductsForSelectedPricelist();
    }
  }

  DateTime? _tryParseServerDate(String raw) {
    if (raw.isEmpty) return null;
    try {
      return _apiDateFormat.parseStrict(raw);
    } catch (_) {
      return null;
    }
  }

  /// Bootstraps the Add/Edit Estimate form via `show_estimate_id` — a
  /// one-time backward-compat fallback for a row cached before this app
  /// version started storing full details (see
  /// `EstimateListItem.hasFullDetails`), and the path "Convert to
  /// Estimate" always uses (see [startConvertFromQuotation]). The normal
  /// offline-first Add/Edit path is [_loadDropdownDataFromCache] +
  /// [_populateFormFromModel], which never touches the network.
  Future<void> _loadFormInit({
    required String showEstimateId,
    String convertQuotationId = '',
  }) async {
    try {
      final result = await _estimateRepository.getFormInitData(
        showEstimateId: showEstimateId,
        convertQuotationId: convertQuotationId,
      );

      pricelistOptions.assignAll(result.pricelist);
      agentOptions.assignAll(result.agentList);
      parties.assignAll(result.partyList.map((p) => PartyModel(
            id: p.id,
            serverPartyId: p.id,
            name: p.name.isEmpty ? 'Untitled Party' : p.name,
            hasFullDetails: false,
          )));
      otherChargesOptions.assignAll(result.otherCharges);
      // The init endpoint doesn't return each charge's type — resolved
      // lazily by [addCharge] instead when this fallback path is in use.
      _chargeTypeById.clear();

      final detail = result.detail;
      if (detail != null) {
        if (detail.pricelistId.isNotEmpty) {
          final pl = pricelistOptions
              .firstWhereOrNull((p) => p.id == detail.pricelistId);
          selectedPricelistId.value = detail.pricelistId;
          selectedPricelist.value = pl?.name;
        }
        if (detail.agentId.isNotEmpty) {
          final ag =
              agentOptions.firstWhereOrNull((a) => a.id == detail.agentId);
          selectedAgentId.value = detail.agentId;
          selectedAgent.value = ag?.name;
        }
        if (detail.partyId.isNotEmpty) {
          selectedParty.value = parties
              .firstWhereOrNull((p) => p.serverPartyId == detail.partyId);
        }
        final parsedDate = _tryParseServerDate(detail.estimateDate);
        if (parsedDate != null) estimationDate.value = parsedDate;

        formItems.assignAll(detail.products.map((row) {
          final section = row.productDiscount == '1' ? 1 : 2;
          _stockCache.remove(row.productId); // unknown until re-queried
          return BillingItemModel(
            productId: row.productId,
            productName: row.productName,
            quantity: int.tryParse(row.quantity) ?? 1,
            rate: double.tryParse(row.rate) ?? 0,
            unit: row.unitName,
            unitId: row.unitId,
            section: section,
          );
        }));

        section1Add.value = double.tryParse(detail.section1AddValue) ?? 0;
        section1Discount.value = double.tryParse(detail.section1Discount) ?? 0;
        section2Add.value = double.tryParse(detail.section2AddValue) ?? 0;
        section2Discount.value = double.tryParse(detail.section2Discount) ?? 0;

        charges.assignAll(detail.charges.map((c) {
          final magnitude = double.tryParse(c.value) ?? 0;
          final signed = c.type == 'Minus' ? -magnitude.abs() : magnitude.abs();
          return ChargeLine(
            name: c.chargeName,
            value: signed,
            chargeId: c.chargeId,
            type: c.type.isEmpty ? 'Plus' : c.type,
          );
        }));
      } else if (pricelistOptions.isNotEmpty) {
        // New estimate — default to the first pricelist, matching the web
        // app's Add Estimate screen.
        selectedPricelistId.value = pricelistOptions.first.id;
        selectedPricelist.value = pricelistOptions.first.name;
      }

      _syncMoneyControllers();

      if (selectedPricelistId.value != null &&
          selectedPricelistId.value!.isNotEmpty) {
        await loadProductsForSelectedPricelist();
      }
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load estimate', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load estimate', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingForm.value = false;
    }
  }

  // ---- Form: line items ---------------------------------------------------

  /// Adds [productId] to the form. Rate/unit/stock/section come straight
  /// from [productOptions] — already loaded for the selected pricelist by
  /// [loadProductsForSelectedPricelist], and `product_pricelist_id`
  /// returns rate/unit/discount-flag/stock for every product already, so
  /// no second `selected_product_id` round-trip is needed (or possible
  /// offline).
  Future<void> addProductById({
    required String productId,
    required String productName,
    int qty = 1,
  }) async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      Get.snackbar(
          'Select a pricelist', 'Choose a pricelist before adding products',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final option =
        productOptions.firstWhereOrNull((p) => p.productId == productId);
    if (option == null) {
      Get.snackbar('Not available',
          'This product isn\'t available under the selected pricelist',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    _stockCache[productId] = option.currentStock;

    // Matches the server's own rule for which totals section a line
    // lands in once saved (see estimate.php's `product_discount` check).
    final section = option.productDiscount ? 1 : 2;

    final existingIndex = formItems
        .indexWhere((i) => i.productId == productId && i.section == section);
    if (existingIndex >= 0) {
      formItems[existingIndex].quantity += qty;
      formItems.refresh();
    } else {
      formItems.add(BillingItemModel(
        productId: productId,
        productName: productName.isEmpty ? option.productName : productName,
        quantity: qty,
        rate: option.rate,
        unit: option.unitName.isEmpty ? 'Pcs' : option.unitName,
        unitId: option.unitId,
        section: section,
      ));
    }
  }

  /// Adds/updates many products at once from the full-screen product
  /// picker. Unlike [addProductById], this never calls the network —
  /// `product_pricelist_id` (already loaded into [productOptions]) returns
  /// rate/unit/discount-flag/stock for every product, so a multi-select
  /// "Add to Estimate" can apply all of them in one shot.
  ///
  /// [selections] maps `productId` -> desired quantity. A quantity of 0
  /// or a product missing from [productOptions] is skipped.
  void addProductsFromPicker(Map<String, int> selections) {
    for (final entry in selections.entries) {
      final qty = entry.value;
      if (qty <= 0) continue;
      final option =
          productOptions.firstWhereOrNull((p) => p.productId == entry.key);
      if (option == null) continue;

      _stockCache[option.productId] = option.currentStock;
      final section = option.productDiscount ? 1 : 2;

      final existingIndex = formItems.indexWhere(
          (i) => i.productId == option.productId && i.section == section);
      if (existingIndex >= 0) {
        formItems[existingIndex].quantity = qty;
      } else {
        formItems.add(BillingItemModel(
          productId: option.productId,
          productName: option.productName,
          quantity: qty,
          rate: option.rate,
          unit: option.unitName.isEmpty ? 'Pcs' : option.unitName,
          unitId: option.unitId,
          section: section,
        ));
      }
    }
    formItems.refresh();
  }

  /// Adds/updates many products at once from the full-screen product
  /// picker, the same as [addProductsFromPicker] — except each product
  /// carries its *own* [EstimateProductOption] snapshot instead of being
  /// looked up in [productOptions].
  ///
  /// This is what lets the picker's pricelist tab bar work: a product
  /// picked under one pricelist tab keeps that tab's rate/unit/section
  /// even after the user switches to another tab (which reloads
  /// [productOptions] out from under it) and picks more products there
  /// before finally tapping "Add to Estimate".
  void addProductSelections(
      List<MapEntry<EstimateProductOption, int>> selections) {
    for (final entry in selections) {
      final option = entry.key;
      final qty = entry.value;
      if (qty <= 0) continue;

      _stockCache[option.productId] = option.currentStock;
      final section = option.productDiscount ? 1 : 2;

      final existingIndex = formItems.indexWhere(
          (i) => i.productId == option.productId && i.section == section);
      if (existingIndex >= 0) {
        formItems[existingIndex].quantity = qty;
        formItems[existingIndex].rate = option.rate;
      } else {
        formItems.add(BillingItemModel(
          productId: option.productId,
          productName: option.productName,
          quantity: qty,
          rate: option.rate,
          unit: option.unitName.isEmpty ? 'Pcs' : option.unitName,
          unitId: option.unitId,
          section: section,
          isCustom: option.isCustom,
        ));
      }
    }
    formItems.refresh();
  }

  /// Current quantity already on the form for [productId] (any section) —
  /// used to pre-fill the stepper when the product picker is reopened.
  int quantityInFormFor(String productId) {
    final match = formItems.firstWhereOrNull((i) => i.productId == productId);
    return match?.quantity ?? 0;
  }

  // ---- Form: compliment products -----------------------------------------

  /// Adds/updates many free/no-charge "Compliment Products" at once from
  /// [EstimateComplimentProductPickerView]'s "Add Compliment Products"
  /// button — the compliment counterpart of [addProductSelections].
  /// Unlike an ordinary line item, no rate/section is tracked; a
  /// compliment product is just a name + quantity, kept out of every
  /// totals calculation.
  void addComplimentSelections(
      List<MapEntry<EstimateProductOption, int>> selections) {
    for (final entry in selections) {
      final option = entry.key;
      final qty = entry.value;
      if (qty <= 0) continue;

      final existingIndex = complimentItems
          .indexWhere((i) => i.productId == option.productId);
      if (existingIndex >= 0) {
        complimentItems[existingIndex].quantity = qty;
      } else {
        complimentItems.add(ComplimentItemModel(
          productId: option.productId,
          productName: option.productName,
          quantity: qty,
          unit: option.unitName.isEmpty ? 'Pcs' : option.unitName,
          unitId: option.unitId,
          isCustom: option.isCustom,
        ));
      }
    }
    complimentItems.refresh();
  }

  /// Current quantity already on the form for [productId] among
  /// [complimentItems] — used to pre-fill the stepper when the
  /// compliment product picker is reopened.
  int quantityInComplimentFor(String productId) {
    final match =
        complimentItems.firstWhereOrNull((i) => i.productId == productId);
    return match?.quantity ?? 0;
  }

  void updateComplimentQuantity(int index, int qty) {
    if (qty < 1) return;
    complimentItems[index].quantity = qty;
    complimentItems.refresh();
  }

  void removeComplimentItem(int index) {
    complimentItems.removeAt(index);
  }

  void updateQuantity(int index, int qty) {
    if (qty < 1) return;
    formItems[index].quantity = qty;
    formItems.refresh();
  }

  void updateRate(int index, double rate) {
    if (rate < 0) return;
    formItems[index].rate = rate;
    formItems.refresh();
  }

  void moveToSection(int index, int section) {
    formItems[index].section = section;
    formItems.refresh();
  }

  void removeItem(int index) {
    formItems.removeAt(index);
  }

  void clearForm() {
    formItems.clear();
    complimentItems.clear();
    selectedParty.value = null;
    selectedAgent.value = null;
    selectedAgentId.value = null;
    section1Add.value = 0;
    section1Discount.value = 0;
    section2Add.value = 0;
    section2Discount.value = 0;
    charges.clear();
    selectedChargeId.value = null;
    _syncMoneyControllers();
  }

  // ---- Form: save -----------------------------------------------------------

  /// Saves the form. This is offline-only, always — draft or a real
  /// confirm both save straight to this device and never call
  /// `estimate.php` directly, whether or not the internet happens to be
  /// available right now. Every save (either kind) is queued in
  /// [CacheKeys.estimationPending] via
  /// [EstimateRepository.queueEstimateForSync]; only a manual tap of the
  /// Sync button (see [DataSyncService]) ever sends that queue to the
  /// server, in one batch.
  Future<bool> save({required bool asDraft}) async {
    if (isSaving.value) return false;

    // The server relaxes its own validation for drafts (empty party/
    // pricelist/items are fine) — only require them for a real submit.
    if (!asDraft) {
      if (selectedParty.value == null) {
        Get.snackbar('Missing party', 'Please select a party',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
      if (selectedPricelistId.value == null ||
          selectedPricelistId.value!.isEmpty) {
        Get.snackbar('Missing pricelist', 'Please select a pricelist',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
      if (formItems.isEmpty) {
        Get.snackbar('No items', 'Add at least one product',
            snackPosition: SnackPosition.BOTTOM);
        return false;
      }
    }

    final session = _sessionService.currentSession.value;
    if (session == null) {
      Get.snackbar('Session expired', 'Please log in again',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    isSaving.value = true;
    try {
      // The server no longer assigns `estimate_id`/`estimate_number`
      // itself — the client generates both, once, at creation: `editId`
      // becomes the estimate's permanent id (used for every later edit,
      // for Cancel, and for the linked Receipt), and `estimateNumber` is
      // the printed bill number. An edit reuses both unchanged —
      // regenerating either here would silently rename an existing
      // estimate.
      final String editId;
      final String estimateNumber;
      if (editingEstimation == null) {
        editId = IdGenerator.generate();
        estimateNumber = _estimateRepository.nextEstimateNumber(
          billPrefix: session.billPrefix,
        );
      } else {
        editId = editingEstimation!.serverEstimateId ??
            editingEstimation!.localId ??
            IdGenerator.generate();
        estimateNumber = editingEstimation!.estimationNo.isNotEmpty
            ? editingEstimation!.estimationNo
            : _estimateRepository.nextEstimateNumber(
                billPrefix: session.billPrefix,
              );
      }
      // The id doubles as the pending-queue entry's key — since it's
      // assigned once at creation and never changes, there's no separate
      // "local-only" id to track the way Party's queue still needs one.
      final localId = editId;

      final agentName = selectedAgentId.value == null
          ? ''
          : (agentOptions
                  .firstWhereOrNull((a) => a.id == selectedAgentId.value)
                  ?.name ??
              '');

      await _estimateRepository.queueEstimateForSync(
        localId: localId,
        editId: editId,
        estimateNumber: estimateNumber,
        convertQuotationId: _convertQuotationId ?? '',
        drafted: asDraft ? '1' : '0',
        estimateDate: _apiDateFormat.format(estimationDate.value),
        pricelistId: selectedPricelistId.value ?? '',
        pricelistName: selectedPricelist.value ?? '',
        agentId: selectedAgentId.value ?? '',
        agentName: agentName,
        partyId: selectedParty.value?.serverPartyId ??
            selectedParty.value?.id ??
            '',
        partyName: selectedParty.value?.name ?? '',
        products: formItems
            .map((i) => {
                  'product_id': i.productId,
                  'product_name': i.productName,
                  'unit_id': i.unitId,
                  'unit_name': i.unit,
                  'product_quantity': i.quantity.toString(),
                  'product_rate': i.rate.toString(),
                  // Preserves which totals section this line was in, so
                  // re-opening this pending row for editing shows it the
                  // same way — matches the server's own product_discount
                  // rule, just carried locally instead of re-derived.
                  'product_discount': i.section == 1 ? '1' : '0',
                })
            .toList(),
        section1AddValue:
            section1Add.value == 0 ? '' : section1Add.value.toString(),
        section1Discount: section1Discount.value == 0
            ? ''
            : section1Discount.value.toString(),
        section2AddValue:
            section2Add.value == 0 ? '' : section2Add.value.toString(),
        section2Discount: section2Discount.value == 0
            ? ''
            : section2Discount.value.toString(),
        charges: charges
            .map((c) => EstimateChargeLine(
                  chargeId: c.chargeId,
                  type: c.type,
                  value: c.value.abs().toString(),
                  name: c.name,
                ))
            .toList(),
        complimentProducts: complimentItems
            .map((c) => {
                  'product_id': c.productId,
                  'product_name': c.productName,
                  'unit_id': c.unitId,
                  'unit_name': c.unit,
                  'product_quantity': c.quantity.toString(),
                })
            .toList(),
      );

      final wasCreate = editingEstimation == null;
      final convertedQuotationId = _convertQuotationId;
      _convertQuotationId = null;
      Get.back();
      Get.snackbar(
        wasCreate ? 'Saved offline' : 'Updated offline',
        'Saved on this device. Tap Sync when you\'re online to send it to the server.',
        snackPosition: SnackPosition.BOTTOM,
      );
      if (wasCreate) currentPage.value = 1;
      activeTab.value = asDraft ? EstimationTab.draft : EstimationTab.active;
      await loadEstimates();
      // The source quotation's own "converted" flag is only stamped
      // server-side once this estimate is actually synced — nothing to
      // refresh on the Quotation list until then.
      if (convertedQuotationId != null &&
          convertedQuotationId.isNotEmpty &&
          Get.isRegistered<QuotationController>()) {
        unawaited(Get.find<QuotationController>().loadQuotations());
      }
      return true;
    } finally {
      isSaving.value = false;
    }
  }
}