import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ncw_fireworks/core/utils/pdf/quotation_pdf_builder.dart';
import 'package:ncw_fireworks/core/utils/pdf_downloader.dart';
import 'package:ncw_fireworks/core/utils/share_service.dart';
import 'package:printing/printing.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/percent_amount_parser.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/custom_product/custom_product_models.dart';
import '../../data/models/party_model.dart';
import '../../data/models/quotation/id_name.dart';
import '../../data/models/quotation/quotation_product_list_response_model.dart';
import '../../data/models/quotation_model.dart';
import '../../data/respositories/custom_product_repository.dart';
import '../../data/respositories/party_repository.dart';
import '../../data/respositories/quotation_repository.dart';
import '../../routes/app_routes.dart';
import '../../widgets/common_widgets.dart';
import '../estimation/estimation_controller.dart';

/// The 3 tabs shown above the Quotation list on the web app.
///
/// Each tab maps to `quotation.php`'s `drafted`/`cancelled` filters on
/// `quotation_listing`: Active is `drafted=0, cancelled=0`, Draft is
/// `drafted=1, cancelled=0`, Cancel is `drafted=0, cancelled=1`.
enum QuotationTab { active, draft, cancel }

extension QuotationTabX on QuotationTab {
  String get label {
    switch (this) {
      case QuotationTab.active:
        return 'Active';
      case QuotationTab.draft:
        return 'Draft';
      case QuotationTab.cancel:
        return 'Cancel';
    }
  }
}

class QuotationController extends GetxController {
  QuotationController({
    QuotationRepository? quotationRepository,
    SessionService? sessionService,
    PartyRepository? partyRepository,
    CustomProductRepository? customProductRepository,
  })  : _quotationRepository = quotationRepository ?? QuotationRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>(),
        _partyRepository = partyRepository ?? PartyRepository(),
        _customProductRepository =
            customProductRepository ?? CustomProductRepository();

  final QuotationRepository _quotationRepository;
  final SessionService _sessionService;
  final PartyRepository _partyRepository;
  final CustomProductRepository _customProductRepository;

  static final DateFormat _apiDateFormat = DateFormat('dd-MM-yyyy');
  static final DateFormat _serverStoredDateFormat = DateFormat('yyyy-MM-dd');

  // ---- Shared dropdown data (populated by loadQuotations + the form's
  // init call — both come from the same endpoint's `head`, so either one
  // keeps these current). --------------------------------------------------
  final pricelistOptions = <IdName>[].obs;
  final parties = <PartyModel>[].obs;
  final otherChargesOptions = <ChargeOption>[].obs;
  final productOptions = <QuotationProductOption>[].obs;
  final isLoadingProducts = false.obs;

  // ---- Add Custom Product dropdown data (synced once at login/Sync via
  // `CustomProductRepository`/`DataSyncService`) --------------------------
  final customCategories = <CustomProductOption>[].obs;
  final customUnits = <CustomProductOption>[].obs;

  List<String> get pricelistNames =>
      pricelistOptions.map((e) => e.name).toList();

  /// Each cached other-charge's fixed "Plus"/"Minus" type (see
  /// `QuotationRepository.cachedOtherCharges`) — populated whenever
  /// dropdown data is loaded from cache, read by [addCharge] instead of a
  /// live `type_other_charges_id` call.
  final _chargeTypeById = <String, String>{};

  // ---- List screen state -------------------------------------------------
  final quotations = <QuotationModel>[].obs;
  final searchQuery = ''.obs;
  final activeTab = QuotationTab.active.obs;
  final isTableView = false.obs;
  final Rx<DateTime?> filterFrom = Rx<DateTime?>(null);
  final Rx<DateTime?> filterTo = Rx<DateTime?>(null);
  final Rx<String?> filterParty = Rx<String?>(null); // party *name*
  final pageSize = 10.obs;
  final currentPage = 1.obs;
  final isLoadingList = false.obs;

  /// The API doesn't return a total row/page count for `quotation_listing`
  /// — inferred the same way `EstimationController` does: trust a full
  /// page means there's probably another one, and self-correct once the
  /// user reaches the real last page.
  final totalPagesRx = 1.obs;
  int get totalPages => totalPagesRx.value;

  /// Bumped on every `loadQuotations()` call; a response is only applied
  /// if it's still the most recent request when it comes back — guards
  /// against rapid page/filter/tab changes firing overlapping requests
  /// whose responses arrive out of order and clobber the current page.
  int _requestId = 0;

  Timer? _searchDebounce;

  // ---- Form state ---------------------------------------------------------
  QuotationModel? editingQuotation;
  final Rx<PartyModel?> selectedParty = Rx<PartyModel?>(null);
  final Rx<String?> selectedPricelist = Rx<String?>(null); // pricelist *name*
  final Rx<String?> selectedPricelistId = Rx<String?>(null);
  final Rx<DateTime> quotationDate = Rx<DateTime>(DateTime.now());
  final formItems = <BillingItemModel>[].obs;
  final section1Add = 0.0.obs;
  final section1Discount = 0.0.obs;
  final section2Add = 0.0.obs;
  final section2Discount = 0.0.obs;
  final charges = <QuotationChargeLine>[].obs;
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

  // Raw text last typed into the Add/Discount fields — kept separately from
  // section1Add/section1Discount/section2Add/section2Discount (which always
  // hold the *resolved* rupee amount) so a "10%" entry can be re-resolved
  // against the section total whenever items are added/removed/edited, not
  // just at typing time.
  String _section1AddRaw = '';
  String _section1DiscountRaw = '';
  String _section2AddRaw = '';
  String _section2DiscountRaw = '';

  @override
  void onInit() {
    super.onInit();
    // Re-resolve percentage-based add/discount values whenever the items
    // backing a section total change (add/remove/qty edit), so e.g. "10%"
    // always reflects 10% of the *current* section total rather than going
    // stale.
    ever(formItems, (_) {
      section1Add.value =
          resolvePercentOrAmount(_section1AddRaw, formSection1Total);
      section1Discount.value =
          resolvePercentOrAmount(_section1DiscountRaw, formSection1Total);
      section2Add.value =
          resolvePercentOrAmount(_section2AddRaw, formSection2Total);
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

  /// Called from the Add/Discount text fields on every keystroke. Accepts a
  /// plain amount ("150") or a percentage of the section total ("10%").
  void setSection1AddInput(String raw) {
    _section1AddRaw = raw;
    section1Add.value = resolvePercentOrAmount(raw, formSection1Total);
  }

  void setSection1DiscountInput(String raw) {
    _section1DiscountRaw = raw;
    section1Discount.value = resolvePercentOrAmount(raw, formSection1Total);
  }

  void setSection2AddInput(String raw) {
    _section2AddRaw = raw;
    section2Add.value = resolvePercentOrAmount(raw, formSection2Total);
  }

  void setSection2DiscountInput(String raw) {
    _section2DiscountRaw = raw;
    section2Discount.value = resolvePercentOrAmount(raw, formSection2Total);
  }

  /// Called every time the Quotation list screen is freshly entered via
  /// navigation (see `_QuotationListFreshVisit` in `quotation_list_view.dart`).
  /// GetX only disposes a `lazyPut` controller once every route bound to
  /// it has been fully popped — if the sidebar pushes `/quotation` again
  /// while an earlier visit is still further down the Navigator stack,
  /// the *same* controller instance gets reused and `onInit()` never runs
  /// a second time. This puts it back to a clean slate regardless — search
  /// text cleared, page size back to 10, first page, Active tab, both
  /// date filters cleared, "All Partys" selected, list view (not table
  /// view) — then reloads. Works the same online or offline since
  /// [loadQuotations] already falls back to the local cache when there's
  /// no connection.
  void resetForFreshVisit() {
    _searchDebounce?.cancel();
    searchQuery.value = '';
    pageSize.value = 10;
    currentPage.value = 1;
    activeTab.value = QuotationTab.active;
    filterFrom.value = null;
    filterTo.value = null;
    filterParty.value = null;
    isTableView.value = false;
    loadQuotations();
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
    // Loaded/reset add/discount values are always plain resolved amounts,
    // never a percentage — keep the raw trackers in step so the next
    // items-change re-resolve doesn't reapply a stale "%" against the new
    // total.
    _section1AddRaw = section1AddCtrl.text;
    _section1DiscountRaw = section1DiscountCtrl.text;
    _section2AddRaw = section2AddCtrl.text;
    _section2DiscountRaw = section2DiscountCtrl.text;
  }

  // ---- List loading / filtering / pagination ------------------------------

  String? _partyIdForName(String? name) {
    if (name == null) return null;
    return parties.firstWhereOrNull((p) => p.name == name)?.serverPartyId;
  }

  Future<void> loadQuotations() async {
    final requestId = ++_requestId;
    isLoadingList.value = true;
    try {
      final result = await _quotationRepository.listQuotations(
        filterFromDate: filterFrom.value != null
            ? _apiDateFormat.format(filterFrom.value!)
            : '',
        filterToDate: filterTo.value != null
            ? _apiDateFormat.format(filterTo.value!)
            : '',
        searchText: searchQuery.value.trim(),
        filterPartyId: _partyIdForName(filterParty.value) ?? '',
        pageNumber: currentPage.value,
        pageLimit: pageSize.value,
        drafted: activeTab.value == QuotationTab.draft ? '1' : '0',
        cancelled: activeTab.value == QuotationTab.cancel ? '1' : '0',
      );
      if (requestId != _requestId) return; // A newer request has since started.

      final rowStatus = switch (activeTab.value) {
        QuotationTab.active => DocStatus.active,
        QuotationTab.draft => DocStatus.draft,
        QuotationTab.cancel => DocStatus.cancelled,
      };

      if (result.partyList.isNotEmpty) {
        parties.assignAll(result.partyList.map((p) => PartyModel(
              id: p.id,
              serverPartyId: p.id,
              name: p.name.isEmpty ? 'Untitled Party' : p.name,
              hasFullDetails: false,
            )));
      }

      // Computed once per load — cheap set lookup per row below instead
      // of re-reading the pending estimate queue for every row.
      final locallyConvertedIds =
          _quotationRepository.locallyConvertedQuotationIds();

      quotations.assignAll(result.items.map((item) {
        DateTime date;
        try {
          // Pending (not-yet-synced) rows are stored as dd-MM-yyyy (see
          // QuotationRepository.queueQuotationForSync); synced rows come
          // back from the server as yyyy-MM-dd. Picking the format
          // directly by [item.isPending] avoids the bug where
          // DateFormat('yyyy-MM-dd').parse(...) — the *lenient* parse,
          // not parseStrict — silently "succeeds" on a dd-MM-yyyy string
          // by reinterpreting its digit groups as year/month/day in the
          // wrong order (e.g. "15-01-2026" misread as year 15, causing
          // the day component to overflow into a garbage date like
          // "15-01-0029"), instead of throwing and falling through to
          // the correct format.
          date = item.isPending
              ? _apiDateFormat.parseStrict(item.quotationDate)
              : _serverStoredDateFormat.parseStrict(item.quotationDate);
        } catch (_) {
          try {
            date = _apiDateFormat.parseStrict(item.quotationDate);
          } catch (_) {
            try {
              date = _serverStoredDateFormat.parseStrict(item.quotationDate);
            } catch (_) {
              date = DateTime.now();
            }
          }
        }
        final party = item.partyNameMobileCity.trim();
        final knownFullDetails = item.isPending || item.hasFullDetails;
        // The server only marks this quotation's own estimateId once the
        // converted estimate is actually synced — until then, fall back
        // to the locally-queued conversion so Convert/Edit/Delete hide
        // straight away instead of waiting for a Sync (see
        // `QuotationRepository.locallyConvertedQuotationIds`).
        final ownId = item.isPending ? item.localId : item.quotationId;
        final estimateId = item.estimateId.isNotEmpty
            ? item.estimateId
            : (locallyConvertedIds.contains(ownId) ? ownId : '');
        return QuotationModel(
          id: item.isPending ? item.localId : item.quotationId,
          quotationNo: item.quotationNumber,
          serverQuotationId: item.quotationId.isEmpty ? null : item.quotationId,
          partyId: item.partyId,
          partyName: party.isEmpty ? 'Direct' : party,
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
          status: rowStatus,
          section1Add: double.tryParse(item.section1AddValue) ?? 0,
          section1Discount: double.tryParse(item.section1Discount) ?? 0,
          section2Add: double.tryParse(item.section2AddValue) ?? 0,
          section2Discount: double.tryParse(item.section2Discount) ?? 0,
          charges: item.charges.map((c) {
            final magnitude = double.tryParse(c.value) ?? 0;
            final signed =
                c.type == 'Minus' ? -magnitude.abs() : magnitude.abs();
            return QuotationChargeLine(
              name: c.chargeName,
              value: signed,
              chargeId: c.chargeId,
              type: c.type.isEmpty ? 'Plus' : c.type,
            );
          }).toList(),
          // A pending row's total/qty aren't known server-side yet — let
          // QuotationModel derive them from its own items instead of
          // reading a stale/zero server value.
          serverGrandTotal: item.isPending ? null : item.grandTotal,
          serverQtyLabel: item.isPending ? null : item.totalQuantity,
          estimateId: estimateId,
          isPending: item.isPending,
          localId: item.isPending ? item.localId : null,
          // A row cached by an older build of this app only has the
          // summary fields — not safe to re-save without fetching the
          // rest first (see QuotationController.startEdit).
          hasFullDetails: knownFullDetails,
        );
      }));

      // Prefer the known total row count derived from the last sync (see
      // QuotationRepository._cachedTotalCount) — this stays fixed while
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
              e.message.toLowerCase().contains('quotation') ||
              e.message.toLowerCase().contains('data'));
      quotations.clear();
      totalPagesRx.value = 1;
      if (!looksLikeEmptyResult) {
        Get.snackbar('Could not load quotations', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } on ApiException catch (e) {
      if (requestId != _requestId) return;
      quotations.clear();
      totalPagesRx.value = 1;
      Get.snackbar('Could not load quotations', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (requestId == _requestId) isLoadingList.value = false;
    }
  }

  /// The current page's rows, as returned by the server — the list view
  /// still calls this `pagedFiltered` to match its existing layout code.
  List<QuotationModel> get pagedFiltered => quotations;

  void setSearch(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      currentPage.value = 1;
      loadQuotations();
    });
  }

  void setTab(QuotationTab tab) {
    activeTab.value = tab;
    currentPage.value = 1;
    loadQuotations();
  }

  void setDateFrom(DateTime? date) {
    filterFrom.value = date;
    currentPage.value = 1;
    loadQuotations();
  }

  void setDateTo(DateTime? date) {
    filterTo.value = date;
    currentPage.value = 1;
    loadQuotations();
  }

  void setPartyFilter(String? party) {
    filterParty.value = party;
    currentPage.value = 1;
    loadQuotations();
  }

  void setPageSize(int size) {
    pageSize.value = size;
    currentPage.value = 1;
    loadQuotations();
  }

  void setPageNo(int page) {
    if (isLoadingList.value || page == currentPage.value) return;
    currentPage.value = page;
    loadQuotations();
  }

  void goToPage(int page) => setPageNo(page.clamp(1, totalPages));

  void toggleViewMode(bool table) => isTableView.value = table;

  /// Whether the server has ever confirmed [quotation] — false only for
  /// one still sitting purely in the pending-sync queue, never yet sent.
  /// A pending *edit* of an already-synced quotation still counts as
  /// known, since cancelling it means queuing a `cancelled: "1"` update
  /// for that existing quotation, not just dropping local state. Used by
  /// the list view to show accurate confirm-dialog text for
  /// [deleteQuotation].
  bool isKnownToServer(QuotationModel quotation) {
    final quotationId =
        quotation.serverQuotationId ?? quotation.localId ?? quotation.id;
    return quotationId.isNotEmpty &&
        _quotationRepository.existsInSyncedCache(quotationId);
  }

  /// Cancels a confirmed (non-draft) quotation, or permanently deletes a
  /// draft — mirrors the server's own `delete_quotation_id` rule based
  /// on the quotation's `drafted` flag.
  ///
  /// Cancel is offline-first, just like Add/Edit: cancelling a
  /// quotation the server already knows about queues a `cancelled: "1"`
  /// update in the same pending-sync batch (see
  /// [QuotationRepository.queueQuotationForSync]) and moves it to the
  /// Cancel tab immediately — only a Sync tap actually tells the
  /// server. Deleting a draft still needs the live
  /// `delete_quotation_id` call (unchanged — permanent delete isn't
  /// part of the offline Cancel flow). Either way, a quotation the
  /// server has never confirmed (still only in the pending-sync queue)
  /// just has its queue entry dropped — there's nothing server-side yet
  /// to cancel or delete.
  Future<void> deleteQuotation(QuotationModel quotation) async {
    final quotationId =
        quotation.serverQuotationId ?? quotation.localId ?? quotation.id;
    final knownToServer = isKnownToServer(quotation);

    if (quotation.isPending && !knownToServer) {
      quotations.remove(quotation);
      if (quotation.localId != null) {
        await _quotationRepository.removePendingQuotation(quotation.localId!);
      }
      Get.snackbar(
        'Removed from view',
        '${quotation.quotationNo.isEmpty ? "This quotation" : quotation.quotationNo} was removed before it was ever synced.',
        snackPosition: SnackPosition.BOTTOM,
      );
      return;
    }

    if (quotationId.isEmpty) {
      quotations.remove(quotation);
      return;
    }

    final isDraft = quotation.status == DocStatus.draft;
    if (isDraft) {
      try {
        final result = await _quotationRepository.deleteQuotation(
            quotationId: quotationId);
        Get.snackbar('Draft deleted', result.message,
            snackPosition: SnackPosition.BOTTOM);
        await loadQuotations();
      } on ApiRequestException catch (e) {
        Get.snackbar('Could not delete', e.message,
            snackPosition: SnackPosition.BOTTOM);
      } on ApiException catch (e) {
        Get.snackbar('Could not delete', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
      return;
    }

    // Confirmed quotation known to the server — cancel offline. Queues
    // the same full row a save would (so an edit already sitting in the
    // queue, not yet synced, is updated in place rather than
    // duplicated), just with `cancelled` added.
    await _quotationRepository.queueQuotationForSync(
      localId: quotationId,
      editId: quotationId,
      quotationNumber: quotation.quotationNo,
      drafted: '0',
      cancelled: true,
      quotationDate: _apiDateFormat.format(quotation.date),
      pricelistId: quotation.pricelistId,
      pricelistName: quotation.pricelistName,
      partyId: quotation.partyId,
      partyName: quotation.partyName,
      products: quotation.items
          .map((i) => {
                'product_id': i.productId,
                'product_name': i.productName,
                'unit_id': i.unitId,
                'unit_name': i.unit,
                'product_quantity': i.quantity.toString(),
                'product_rate': i.rate.toString(),
                'product_discount': i.section == 1 ? '1' : '0',
                'is_custom': i.isCustom ? '1' : '0',
              })
          .toList(),
      section1AddValue:
          quotation.section1Add == 0 ? '' : quotation.section1Add.toString(),
      section1Discount: quotation.section1Discount == 0
          ? ''
          : quotation.section1Discount.toString(),
      section2AddValue:
          quotation.section2Add == 0 ? '' : quotation.section2Add.toString(),
      section2Discount: quotation.section2Discount == 0
          ? ''
          : quotation.section2Discount.toString(),
    );

    quotations.remove(quotation);
    Get.snackbar(
      'Cancelled offline',
      'Will be sent to the server next time you Sync.',
      snackPosition: SnackPosition.BOTTOM,
    );
    await loadQuotations();
  }

  // ---- Print / download report PDF ----------------------------------------

  /// Builds the A4 quotation PDF entirely on-device (see
  /// [QuotationPdfBuilder]) — no network call, so this works the same
  /// whether or not the device is online, and whether or not this
  /// quotation has even been synced yet.
  Future<Uint8List> _buildQuotationPdfBytes(QuotationModel quotation) {
    final party = _partyRepository.cachedPartyById(quotation.partyId);
    return QuotationPdfBuilder.build(quotation: quotation, party: party);
  }

  /// Opens the native print/preview dialog for [quotation]'s A4 report.
  Future<void> printQuotation(QuotationModel quotation) async {
    try {
      final bytes = await _buildQuotationPdfBytes(quotation);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (e, st) {
      debugPrint('printQuotation failed: $e\n$st');
      _showPdfErrorDialog('Could not print', e, st);
    }
  }

  Future<void> downloadQuotation(QuotationModel quotation) async {
    try {
      final bytes = await _buildQuotationPdfBytes(quotation);
      await PdfDownloader.saveBytes(
        bytes: bytes,
        fileName: quotation.quotationNo.isEmpty
            ? 'Quotation'
            : quotation.quotationNo,
      );
      Get.snackbar('Downloaded', 'Quotation report saved',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e, st) {
      debugPrint('downloadQuotation failed: $e\n$st');
      _showPdfErrorDialog('Could not download', e, st);
    }
  }

  /// Opens the native share sheet with the on-device PDF attached — see
  /// [_buildQuotationPdfBytes] and `ShareService`'s class doc for what
  /// "offline" covers here, and for why a "Preparing…" overlay covers
  /// the build time and repeat taps are ignored while it's in progress.
  Future<void> shareQuotation(QuotationModel quotation) async {
    final party = _partyRepository.cachedPartyById(quotation.partyId);
    await ShareService.share(
      buildBytes: () => _buildQuotationPdfBytes(quotation),
      fileName:
          quotation.quotationNo.isEmpty ? 'Quotation' : quotation.quotationNo,
      documentLabel: 'Quotation',
      partyName: quotation.partyName,
      phone: party?.mobileNumber,
      onBuildError: (e, st) {
        debugPrint('shareQuotation failed: $e\n$st');
        _showPdfErrorDialog('Could not share', e, st);
      },
    );
  }

  /// A Snackbar truncates long text, which has repeatedly hidden the
  /// actual exception behind a generic "Unable to generate..." message —
  /// this shows the full error (and a copy button for the stack trace)
  /// in a scrollable dialog instead, so a real bug is actually visible
  /// rather than swallowed by the UI.
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

  // ---- Convert to Estimate --------------------------------------------------

  /// Opens the Add Estimate form pre-filled from [quotation]'s own party/
  /// pricelist/products — the Convert action on an active, not-yet-
  /// converted quotation row. Saving that form links the new estimate
  /// back to this quotation, which then hides its Convert/Edit/Delete
  /// actions once the list reloads.
  ///
  /// Passes the whole [quotation] (not just its id) so
  /// `EstimationController.startConvertFromQuotation` can populate the
  /// Estimate form straight from this row's own cached fields — no
  /// network call needed, the same offline-first pattern already used
  /// for editing a quotation or estimate directly (see
  /// `startEdit`/`_populateFormFromModel` on both controllers).
  void convertToEstimate(QuotationModel quotation) {
    final id = quotation.serverQuotationId ?? quotation.id;
    if (id.isEmpty) return;
    // EstimationController is normally registered lazily the first time
    // the Estimate module's own binding runs — put it directly here too,
    // in case Convert is tapped before the user ever opens Estimate.
    final estimationController = Get.isRegistered<EstimationController>()
        ? Get.find<EstimationController>()
        : Get.put(EstimationController());
    estimationController.startConvertFromQuotation(quotation);
    Get.toNamed(AppRoutes.estimationForm);
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

  double get formTotal =>
      formSubTotal + formAdjustments + formChargesTotal + roundOff;

  // ---- Form: charges ----------------------------------------------------

  /// Adds the chosen other-charge with its "Plus"/"Minus" sign.
  /// [rawInput] accepts a plain amount ("150") or a percentage of the
  /// subtotal-after-adjustments ("10%"), same as the Add/Discount fields
  /// — resolved once, at add time, against the current subtotal; unlike
  /// Add/Discount this isn't re-resolved later since each add produces a
  /// discrete charge line rather than a live running value. The sign is
  /// normally read straight from [_chargeTypeById] (cached offline — see
  /// [_loadDropdownDataFromCache]) with no network call; only falls back
  /// to a live `type_other_charges_id` lookup when the charge type isn't
  /// cached, which only happens on the legacy `_loadFormInit` fallback
  /// path (see its doc comment).
  Future<void> addCharge(String rawInput) async {
    final chargeId = selectedChargeId.value;
    final rawValue =
        resolvePercentOrAmount(rawInput, formSubTotal + formAdjustments);
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
        type = (await _quotationRepository.getChargeType(chargeId)).chargesType;
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
    charges.add(QuotationChargeLine(
      name: option.name,
      value: signedValue,
      chargeId: chargeId,
      type: type,
    ));
    selectedChargeId.value = null;
    chargeValueCtrl.clear();
  }

  void removeCharge(int index) => charges.removeAt(index);

  // ---- Form: pricelist selection ------------------------------------------

  /// Switches the form's single active pricelist. A quotation may only
  /// ever hold products from one pricelist at a time — if products are
  /// already selected under a *different* pricelist, this asks for
  /// confirmation before dropping them and switching. Returns whether the
  /// switch actually happened (false if the user cancelled), so callers
  /// like the product picker can keep their own local state in sync.
  Future<bool> selectPricelist(IdName pricelist) async {
    if (selectedPricelistId.value == pricelist.id) return true;

    if (formItems.isNotEmpty) {
      final oldName = selectedPricelist.value ?? 'current';
      final confirmed = await confirmDialog(
        title: 'Switch Price List?',
        message: 'Are you sure you want to remove the already selected '
            "products from the '$oldName' Price List and switch to the "
            "'${pricelist.name}' Price List?",
      );
      if (!confirmed) return false;
      formItems.clear();
    }

    selectedPricelistId.value = pricelist.id;
    selectedPricelist.value = pricelist.name;
    loadProductsForSelectedPricelist();
    return true;
  }

  /// Products offered under the selected pricelist, for the "Add Item"
  /// picker — read straight from the offline catalogue
  /// [DataSyncService] caches at login/Sync
  /// (`QuotationRepository.cachedProductsForPricelist`). No network call,
  /// online or off. Also folds in any custom products added for this
  /// pricelist that haven't been synced yet (see [addCustomProduct]) —
  /// including ones added from the Estimation picker, since the queue is
  /// shared — so they keep showing up here across tab switches, app
  /// restarts, and the other module, exactly like an ordinary catalogue
  /// product. Listed *first*, ahead of the synced catalogue, so a
  /// newly-added custom product is immediately visible at the top of
  /// the picker instead of buried after every catalogue product.
  Future<void> loadProductsForSelectedPricelist() async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      productOptions.clear();
      return;
    }
    final catalogue =
        _quotationRepository.cachedProductsForPricelist(pricelistId);
    final custom = _customProductRepository
        .cachedCustomProductsForPricelist(pricelistId)
        .map(QuotationProductOption.fromCustomRow);
    productOptions.assignAll([...custom, ...catalogue]);
  }

  /// Adds a new custom product — from the Add Custom Product form opened
  /// off the product picker — to the pricelist currently selected there.
  /// Offline-only, always: the product is queued via
  /// [CustomProductRepository.queueCustomProduct] (a queue shared with
  /// Estimation, so this product shows up there too — see
  /// [loadProductsForSelectedPricelist]) and only ever sent to
  /// `product.php` when the person taps Sync on either screen (see
  /// `DataSyncService`). The generated [IdGenerator] id doubles as this
  /// product's permanent id from here on, so it can be picked and added
  /// to the quotation immediately, with no network round trip.
  ///
  /// Returns the newly created [QuotationProductOption] (or `null` on
  /// failure) so the product picker can select it right away, the same
  /// as tapping "Add to Cart" on an ordinary product.
  Future<QuotationProductOption?> addCustomProduct({
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
    // Same "biggest section wins" rule used once this product actually
    // lands on the form (see [_sectionForNewCustomProduct]) — computed
    // here too so `product.php` gets the matching `custom_product_discount`
    // flag for this product from the moment it's queued, not just the
    // quotation/estimate line that references it.
    final section = _sectionForNewCustomProduct();
    await _customProductRepository.queueCustomProduct(
      editId: editId,
      categoryId: categoryId,
      categoryName: categoryName,
      productName: productName,
      unitId: unitId,
      unitName: unitName,
      pricelistId: pricelistId,
      price: price.toString(),
      customProductDiscount: section == 1 ? '1' : '0',
    );
    await loadProductsForSelectedPricelist();
    return productOptions.firstWhereOrNull((p) => p.productId == editId);
  }

  // ---- Form: create / edit bootstrap ------------------------------------

  void _resetFormFields() {
    selectedParty.value = null;
    selectedPricelist.value = null;
    selectedPricelistId.value = null;
    quotationDate.value = DateTime.now();
    formItems.clear();
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
    editingQuotation = null;
    _resetFormFields();
    _loadDropdownDataFromCache();
    if (pricelistOptions.isNotEmpty) {
      // New quotation — default to the first pricelist, matching the
      // web app's Add Quotation screen.
      selectedPricelistId.value = pricelistOptions.first.id;
      selectedPricelist.value = pricelistOptions.first.name;
      loadProductsForSelectedPricelist();
    }
    _syncMoneyControllers();
  }

  /// Opens the Edit form for [quotation]. The offline cache now carries
  /// every field `quotation_listing` returns (see `DataSyncService`/
  /// `QuotationListItem`), and every pending (not-yet-synced) row is
  /// fully known too — so this populates the form directly and works
  /// with no network call at all in the normal case. The
  /// `show_quotation_id` fetch below only ever runs for a row cached by
  /// an older build of this app (before full details were stored) that
  /// hasn't been refreshed by a sync yet; it's a one-time fallback, not
  /// something the offline-first flow depends on.
  void startEdit(QuotationModel quotation) {
    editingQuotation = quotation;
    _resetFormFields();
    _loadDropdownDataFromCache();
    quotationDate.value = quotation.date;

    if (quotation.hasFullDetails) {
      _populateFormFromModel(quotation);
      return;
    }

    isLoadingForm.value = true;
    _loadFormInit(
        showQuotationId: quotation.serverQuotationId ?? quotation.id);
  }

  /// Loads pricelist/party dropdown options from the offline cache that
  /// [DataSyncService] refreshes at login and via Sync — no network call.
  ///
  /// Party options come from [PartyRepository.cachedAllParties] — every
  /// party this device knows about (synced + still-pending) — rather
  /// than `QuotationRepository.cachedParties()`, which only lists
  /// parties that have already appeared on a previously-synced
  /// quotation. That older source meant a brand-new party (or even a
  /// synced one never yet used on a quotation) simply couldn't be
  /// picked here.
  void _loadDropdownDataFromCache() {
    pricelistOptions.assignAll(_quotationRepository.cachedPricelists());
    parties.assignAll(_partyRepository.cachedAllParties().map((p) => PartyModel(
          id: p.isPending ? p.localId : p.partyId,
          serverPartyId: p.partyId.isEmpty ? null : p.partyId,
          localId: p.isPending ? p.localId : null,
          name: p.partyName.isEmpty ? 'Untitled Party' : p.partyName,
          phone: p.mobileNumber,
          isPending: p.isPending,
          hasFullDetails: p.isPending || p.hasFullDetails,
        )));
    final cachedCharges = _quotationRepository.cachedOtherCharges();
    otherChargesOptions.assignAll(cachedCharges
        .map((c) => ChargeOption(id: c.id, name: c.name, type: c.type)));
    _chargeTypeById
      ..clear()
      ..addEntries(cachedCharges.map((c) => MapEntry(c.id, c.type)));
  }

  /// Populates the form directly from [quotation]'s own fields — used
  /// whenever [quotation] already has full details (every pending row,
  /// and every row synced since this app started caching full details).
  void _populateFormFromModel(QuotationModel quotation) {
    if (quotation.pricelistId.isNotEmpty) {
      selectedPricelistId.value = quotation.pricelistId;
      final pl = pricelistOptions
          .firstWhereOrNull((p) => p.id == quotation.pricelistId);
      selectedPricelist.value =
          pl?.name ?? (quotation.pricelistName.isEmpty
              ? null
              : quotation.pricelistName);
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
    charges.assignAll(quotation.charges);
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

  /// Bootstraps the Add/Edit Quotation form via `show_quotation_id` — a
  /// one-time backward-compat fallback for a row cached before this app
  /// version started storing full details (see
  /// `QuotationListItem.hasFullDetails`); the normal offline-first path
  /// is [_loadDropdownDataFromCache] + [_populateFormFromModel], which
  /// never touches the network.
  Future<void> _loadFormInit({required String showQuotationId}) async {
    try {
      final result = await _quotationRepository.getFormInitData(
          showQuotationId: showQuotationId);

      if (result.pricelist.isNotEmpty) pricelistOptions.assignAll(result.pricelist);
      if (result.partyList.isNotEmpty) {
        parties.assignAll(result.partyList.map((p) => PartyModel(
              id: p.id,
              serverPartyId: p.id,
              name: p.name.isEmpty ? 'Untitled Party' : p.name,
              hasFullDetails: false,
            )));
      }
      if (result.otherCharges.isNotEmpty) {
        otherChargesOptions.assignAll(result.otherCharges);
      }
      // `other_charges` rows carry their own fixed "Plus"/"Minus" sign as
      // `charges_type` (see `ChargeOption`), so it's known immediately —
      // no live `type_other_charges_id` lookup needed even on this
      // fallback path.
      _chargeTypeById
        ..clear()
        ..addEntries(
            result.otherCharges.map((c) => MapEntry(c.id, c.type)));

      final detail = result.detail;
      if (detail != null) {
        if (detail.pricelistId.isNotEmpty) {
          final pl = pricelistOptions
              .firstWhereOrNull((p) => p.id == detail.pricelistId);
          selectedPricelistId.value = detail.pricelistId;
          selectedPricelist.value = pl?.name;
        }
        if (detail.partyId.isNotEmpty) {
          selectedParty.value = parties
              .firstWhereOrNull((p) => p.serverPartyId == detail.partyId);
        }
        final parsedDate = _tryParseServerDate(detail.quotationDate);
        if (parsedDate != null) quotationDate.value = parsedDate;

        formItems.assignAll(detail.products.map((row) {
          final section = row.productDiscount == '1' ? 1 : 2;
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
        section1Discount.value =
            double.tryParse(detail.section1Discount) ?? 0;
        section2Add.value = double.tryParse(detail.section2AddValue) ?? 0;
        section2Discount.value =
            double.tryParse(detail.section2Discount) ?? 0;

        charges.assignAll(detail.charges.map((c) {
          final magnitude = double.tryParse(c.value) ?? 0;
          final signed = c.type == 'Minus' ? -magnitude.abs() : magnitude.abs();
          return QuotationChargeLine(
            name: c.chargeName,
            value: signed,
            chargeId: c.chargeId,
            type: c.type.isEmpty ? 'Plus' : c.type,
          );
        }));
      } else if (pricelistOptions.isNotEmpty &&
          (selectedPricelistId.value == null ||
              selectedPricelistId.value!.isEmpty)) {
        // New quotation — default to the first pricelist, matching the
        // web app's Add Quotation screen.
        selectedPricelistId.value = pricelistOptions.first.id;
        selectedPricelist.value = pricelistOptions.first.name;
      }

      _syncMoneyControllers();

      if (selectedPricelistId.value != null &&
          selectedPricelistId.value!.isNotEmpty) {
        await loadProductsForSelectedPricelist();
      }
    } on ApiRequestException catch (e) {
      Get.snackbar('Could not load quotation', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } on ApiException catch (e) {
      Get.snackbar('Could not load quotation', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingForm.value = false;
    }
  }

  // ---- Form: line items ---------------------------------------------------

  /// Section a newly-added Custom Product line should land in: whichever
  /// section currently holds more line items (Section 1 = 3 products,
  /// Section 2 = 1 product → lands in Section 1, and vice versa). A tie
  /// (including an empty form) falls back to Section 2, matching a
  /// custom product's previous fixed default.
  int _sectionForNewCustomProduct() {
    final section1Count = formItems.where((i) => i.section == 1).length;
    final section2Count = formItems.where((i) => i.section == 2).length;
    return section1Count > section2Count ? 1 : 2;
  }

  /// Adds [productId] to the form. Rate/unit/section come straight from
  /// [productOptions] — already loaded for the selected pricelist by
  /// [loadProductsForSelectedPricelist], and `product_pricelist_id`
  /// returns rate/unit/discount-flag for every product already, so no
  /// second `selected_product_id` round-trip is needed (or possible
  /// offline).
  Future<void> addProductById({
    required String productId,
    required String productName,
    int qty = 1,
  }) async {
    final pricelistId = selectedPricelistId.value;
    if (pricelistId == null || pricelistId.isEmpty) {
      Get.snackbar('Select a pricelist',
          'Choose a pricelist before adding products',
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

    // Matches the server's own rule for which totals section a line
    // lands in once saved (see quotation.php's `product_discount` check).
    final section = option.isCustom ? _sectionForNewCustomProduct() : (option.productDiscount ? 1 : 2);

    final existingIndex = formItems.indexWhere(
        (i) => i.productId == productId && i.section == section);
    if (existingIndex >= 0) {
      formItems[existingIndex].quantity += qty;
      formItems.refresh();
    } else {
      formItems.add(BillingItemModel(
        productId: productId,
        productName: productName,
        quantity: qty,
        rate: option.rate,
        unit: option.unitName.isEmpty ? 'Pcs' : option.unitName,
        unitId: option.unitId,
        section: section,
        isCustom: option.isCustom,
      ));
    }
  }

  void updateQuantity(int index, int qty) {
    if (qty < 1) return;
    formItems[index].quantity = qty;
    formItems.refresh();
  }

  /// Adds/updates many products at once from the full-screen product
  /// picker. Unlike [addProductById], this never calls the network —
  /// `product_pricelist_id` (already loaded into [productOptions]) returns
  /// rate/unit/discount-flag for every product, so a multi-select "Add to
  /// Quotation" can apply all of them in one shot.
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

      final section = option.isCustom ? _sectionForNewCustomProduct() : (option.productDiscount ? 1 : 2);

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
          isCustom: option.isCustom,
        ));
      }
    }
    formItems.refresh();
  }

  /// Adds/updates many products at once from the full-screen product
  /// picker, the same as [addProductsFromPicker] — except each product
  /// carries its *own* [QuotationProductOption] snapshot instead of being
  /// looked up in [productOptions].
  ///
  /// This is what lets the picker's pricelist tab bar work: a product
  /// picked under one pricelist tab keeps that tab's rate/unit/section
  /// even after the user switches to another tab (which reloads
  /// [productOptions] out from under it) and picks more products there
  /// before finally tapping "Add to Quotation".
  void addProductSelections(
      List<MapEntry<QuotationProductOption, int>> selections) {
    for (final entry in selections) {
      final option = entry.key;
      final qty = entry.value;
      if (qty <= 0) continue;

      final section = option.isCustom ? _sectionForNewCustomProduct() : (option.productDiscount ? 1 : 2);

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
    selectedParty.value = null;
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
  /// `quotation.php` directly, whether or not the internet happens to be
  /// available right now. Every save (either kind) is queued in
  /// [CacheKeys.quotationPending] via
  /// [QuotationRepository.queueQuotationForSync]; only a manual tap of
  /// the Sync button (see [DataSyncService]) ever sends that queue to
  /// the server, in one batch.
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
      // The server no longer assigns `quotation_id`/`quotation_number`
      // itself — the client generates both, once, at creation:
      // `editId` becomes the quotation's permanent id (used for every
      // later edit and for Convert to Estimate), and `quotationNumber`
      // is the printed bill number. An edit reuses both unchanged —
      // regenerating either here would silently rename an existing
      // quotation.
      final String editId;
      final String quotationNumber;
      if (editingQuotation == null) {
        editId = IdGenerator.generate();
        quotationNumber = _quotationRepository.nextQuotationNumber(
          billPrefix: session.billPrefix,
        );
      } else {
        editId = editingQuotation!.serverQuotationId ??
            editingQuotation!.localId ??
            IdGenerator.generate();
        quotationNumber = editingQuotation!.quotationNo.isNotEmpty
            ? editingQuotation!.quotationNo
            : _quotationRepository.nextQuotationNumber(
                billPrefix: session.billPrefix,
              );
      }
      // The id doubles as the pending-queue entry's key — since it's
      // assigned once at creation and never changes, there's no separate
      // "local-only" id to track the way Party's queue still needs one.
      final localId = editId;

      await _quotationRepository.queueQuotationForSync(
        localId: localId,
        editId: editId,
        quotationNumber: quotationNumber,
        drafted: asDraft ? '1' : '0',
        quotationDate: _apiDateFormat.format(quotationDate.value),
        pricelistId: selectedPricelistId.value ?? '',
        pricelistName: selectedPricelist.value ?? '',
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
                  // Flags a Custom Product line so
                  // [QuotationRepository.syncPendingQuotations] can send
                  // `custom_product_discount` for it — see
                  // [_sectionForNewCustomProduct].
                  'is_custom': i.isCustom ? '1' : '0',
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
            .map((c) => QuotationChargeUpdateLine(
                  chargeId: c.chargeId,
                  type: c.type,
                  value: c.value.abs().toString(),
                  name: c.name,
                ))
            .toList(),
      );

      final wasCreate = editingQuotation == null;
      Get.back();
      Get.snackbar(
        wasCreate ? 'Saved offline' : 'Updated offline',
        'Saved on this device. Tap Sync when you\'re online to send it to the server.',
        snackPosition: SnackPosition.BOTTOM,
      );
      if (wasCreate) currentPage.value = 1;
      activeTab.value = asDraft ? QuotationTab.draft : QuotationTab.active;
      await loadQuotations();
      return true;
    } finally {
      isSaving.value = false;
    }
  }

}