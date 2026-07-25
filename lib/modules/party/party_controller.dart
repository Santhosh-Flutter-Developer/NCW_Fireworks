import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/id_generator.dart';
import '../../data/dummy/dummy_data.dart';
import '../../data/models/party_model.dart';
import '../../data/respositories/party_repository.dart';
import '../../routes/app_routes.dart';

class PartyController extends GetxController {
  PartyController({
    PartyRepository? partyRepository,
    SessionService? sessionService,
  })  : _partyRepository = partyRepository ?? PartyRepository(),
        _sessionService = sessionService ?? Get.find<SessionService>();

  final PartyRepository _partyRepository;
  final SessionService _sessionService;

  final parties = <PartyModel>[].obs;
  final searchQuery = ''.obs;
  final isTableView = false.obs;
  final isSaving = false.obs;
  final isLoadingList = false.obs;
  final isLoadingDetail = false.obs;

  // Pagination (mirrors the web app's Page Limit / Page No controls).
  // The party_listing sample response we have doesn't show a total
  // row/page count, so totalPages is a best guess: trusted when the
  // server does return one, otherwise inferred from whether the last
  // fetch came back with a full page (see _loadParties).
  final pageLimit = 10.obs;
  final pageNo = 1.obs;
  final totalPagesRx = 1.obs;
  static const List<int> pageLimitOptions = [10, 25, 50, 100];
  Timer? _searchDebounce;

  // Dropdown data sources
  List<String> get stateOptions => DummyData.states;
  List<String> districtOptions(String state) =>
      DummyData.districtsByState[state] ?? [];
  List<String> cityOptions(String state) => [
        ...DummyData.citiesByState[state] ?? [],
        'Others',
      ];

  void setFormState(String? value) {
    if (value == null) return;
    formState.value = value;
    formDistrict.value = null;
    setFormCity(null);
  }

  void setFormDistrict(String? value) {
    formDistrict.value = value;
    setFormCity(null);
  }

  void setFormCity(String? value) {
    formCity.value = value;
    if (value != 'Others') othersCityCtrl.clear();
  }

  // Form fields (used by PartyFormView)
  PartyModel? editingParty;
  final formAgent = RxnString();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final emailCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final formState = 'Tamil Nadu'.obs;
  final formDistrict = RxnString();
  final formCity = RxnString();
  final othersCityCtrl = TextEditingController();
  final pincodeCtrl = TextEditingController();
  final identificationCtrl = TextEditingController();
  final gstinCtrl = TextEditingController();
  final openingBalanceCtrl = TextEditingController();
  final formBalanceType = Rx<BalanceType>(BalanceType.credit);

  @override
  void onInit() {
    super.onInit();
    resetForFreshVisit();
  }

  /// Called every time the Party list screen is freshly entered via
  /// navigation (see `_PartyListFreshVisit` in `party_list_view.dart`).
  /// GetX only disposes a `lazyPut` controller once every route bound to
  /// it has been fully popped — if the sidebar pushes `/party` again
  /// while an earlier visit is still further down the Navigator stack,
  /// the *same* controller instance gets reused and `onInit()` never
  /// runs a second time. This puts it back to a clean slate regardless —
  /// search text cleared, page limit back to 10, first page, list view
  /// (not table view) — then reloads. Works the same online or offline
  /// since [loadParties] already falls back to the local cache when
  /// there's no connection.
  void resetForFreshVisit() {
    _searchDebounce?.cancel();
    searchQuery.value = '';
    pageLimit.value = 10;
    pageNo.value = 1;
    isTableView.value = false;
    loadParties();
  }

  /// The current page's rows, as returned by the server. Named
  /// `paginated` to match what [PartyListView] already expects.
  List<PartyModel> get paginated => parties;

  int get totalPages => totalPagesRx.value;

  /// Fetches the current page/search/limit from `party.php`
  /// (`party_listing`). Every control that changes what page we're
  /// looking at (search, page limit, page number) routes through this.
  Future<void> loadParties() async {
    isLoadingList.value = true;
    try {
      final result = await _partyRepository.listParties(
        searchText: searchQuery.value.trim(),
        pageNumber: pageNo.value,
        pageLimit: pageLimit.value,
      );

      parties.assignAll(result.items.map((item) {
        final knownFullDetails = item.isPending || item.hasFullDetails;
        return PartyModel(
          id: item.isPending ? item.localId : item.partyId,
          serverPartyId: item.partyId.isEmpty ? null : item.partyId,
          agent: item.agentName,
          name: item.partyName.isEmpty ? 'Untitled Party' : item.partyName,
          phone: item.mobileNumber,
          email: item.email,
          address: item.address,
          state: item.state,
          district: item.district,
          city: item.city,
          othersCity: item.othersCity,
          pincode: item.pincode,
          identification: item.identification,
          gstin: item.gstNumber,
          openingBalance: double.tryParse(item.openingBalance) ?? 0,
          balanceType: item.openingBalanceType == '2'
              ? BalanceType.debit
              : BalanceType.credit,
          isDraft: item.isDraft,
          isPending: item.isPending,
          localId: item.isPending ? item.localId : null,
          // A row cached by an older build of this app only has
          // id/name/state — not safe to re-save without fetching the
          // rest first (see PartyController.startEdit).
          hasFullDetails: knownFullDetails,
        );
      }));

      if (result.totalPages != null) {
        totalPagesRx.value = result.totalPages!.clamp(1, 1 << 30);
      } else if (result.totalRecords != null) {
        totalPagesRx.value =
            (result.totalRecords! / pageLimit.value).ceil().clamp(1, 1 << 30);
      } else {
        // No total given anywhere — infer from whether this page was
        // full. A full page means there's probably at least one more;
        // this self-corrects once the user reaches the real last page.
        totalPagesRx.value = result.items.length < pageLimit.value
            ? pageNo.value
            : pageNo.value + 1;
      }
    } on ApiRequestException catch (e) {
      // Some "no rows match" cases may come back as a non-200 business
      // response rather than a 200 with an empty list — treat that as
      // an empty page rather than a scary error toast.
      final looksLikeEmptyResult = e.message.toLowerCase().contains('no') &&
          (e.message.toLowerCase().contains('record') ||
              e.message.toLowerCase().contains('party') ||
              e.message.toLowerCase().contains('data'));
      parties.clear();
      totalPagesRx.value = 1;
      if (!looksLikeEmptyResult) {
        Get.snackbar('Could not load parties', e.message,
            snackPosition: SnackPosition.BOTTOM);
      }
    } on ApiException catch (e) {
      parties.clear();
      totalPagesRx.value = 1;
      Get.snackbar('Could not load parties', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingList.value = false;
    }
  }

  void setSearch(String value) {
    searchQuery.value = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      pageNo.value = 1;
      loadParties();
    });
  }

  void setPageLimit(int limit) {
    pageLimit.value = limit;
    pageNo.value = 1;
    loadParties();
  }

  void setPageNo(int page) {
    pageNo.value = page;
    loadParties();
  }
  void toggleViewMode(bool table) => isTableView.value = table;

  void startCreate() {
    editingParty = null;
    formAgent.value = null;
    nameCtrl.clear();
    phoneCtrl.clear();
    emailCtrl.clear();
    addressCtrl.clear();
    formState.value = 'Tamil Nadu';
    formDistrict.value = null;
    formCity.value = null;
    othersCityCtrl.clear();
    pincodeCtrl.clear();
    identificationCtrl.clear();
    gstinCtrl.clear();
    openingBalanceCtrl.clear();
    formBalanceType.value = BalanceType.credit;
  }

  void _populateFormFrom(PartyModel party) {
    formAgent.value = party.agent.isEmpty ? null : party.agent;
    nameCtrl.text = party.name;
    phoneCtrl.text = party.phone;
    emailCtrl.text = party.email;
    addressCtrl.text = party.address;
    formState.value = party.state.isEmpty ? 'Tamil Nadu' : party.state;
    formDistrict.value = party.district.isEmpty ? null : party.district;
    final knownCities = cityOptions(formState.value);
    if (party.city.isNotEmpty &&
        party.othersCity.isEmpty &&
        !knownCities.contains(party.city)) {
      // The server only ever stores the resolved city text, not whether
      // it originally came from "Others" — a value outside the known
      // list means that's what happened, so re-derive it here.
      formCity.value = 'Others';
      othersCityCtrl.text = party.city;
    } else {
      formCity.value = party.city.isEmpty ? null : party.city;
      othersCityCtrl.text = party.othersCity;
    }
    pincodeCtrl.text = party.pincode;
    identificationCtrl.text = party.identification;
    gstinCtrl.text = party.gstin;
    openingBalanceCtrl.text =
        party.openingBalance == 0 ? '' : party.openingBalance.toString();
    formBalanceType.value = party.balanceType;
  }

  /// Opens the Edit form for [party]. The offline cache now carries every
  /// field `party_listing` returns (see `DataSyncService`/`PartyListItem`),
  /// and every pending (not-yet-synced) row is fully known too — so this
  /// populates the form directly and works with no network call at all in
  /// the normal case. The `show_party_id` fetch below only ever runs for
  /// a row cached by an older build of this app (before full details were
  /// stored) that hasn't been refreshed by a sync yet; it's a one-time
  /// fallback, not something the offline-first flow depends on.
  Future<void> startEdit(PartyModel party) async {
    if (party.hasFullDetails || party.serverPartyId == null) {
      editingParty = party;
      _populateFormFrom(party);
      Get.toNamed(AppRoutes.partyForm);
      return;
    }

    isLoadingDetail.value = true;
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );
    try {
      final detail = await _partyRepository.getPartyDetail(
        party.serverPartyId!,
      );

      party
        ..name = detail.partyName.isEmpty ? party.name : detail.partyName
        ..phone = detail.mobileNumber
        ..email = detail.email
        ..address = detail.address
        ..state = detail.state.isEmpty ? party.state : detail.state
        ..district = detail.district
        ..city = detail.city
        ..othersCity = detail.othersCity
        ..pincode = detail.pincode
        ..identification = detail.identification
        ..gstin = detail.gstNumber
        ..openingBalance = detail.openingBalance
        ..balanceType = detail.openingBalanceType == 2
            ? BalanceType.debit
            : BalanceType.credit
        ..hasFullDetails = true;

      Get.back(); // close the loading dialog
      editingParty = party;
      _populateFormFrom(party);
      Get.toNamed(AppRoutes.partyForm);
    } on ApiException catch (e) {
      Get.back(); // close the loading dialog
      Get.snackbar('Could not open party', e.message,
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoadingDetail.value = false;
    }
  }

  /// Returns a validation error message, or null if the form is valid.
  /// Only Party Name and State are mandatory (matching the web form's `*`
  /// fields); everything else is optional so a Draft can be saved freely.
  String? _validate({required bool isDraft}) {
    if (isDraft) return null;
    if (nameCtrl.text.trim().isEmpty) return 'Party name is required';
    if (nameCtrl.text.trim().length > 60) {
      return 'Party name must be 60 characters or fewer';
    }
    if (phoneCtrl.text.isNotEmpty &&
        !RegExp(r'^\d{10}$').hasMatch(phoneCtrl.text.trim())) {
      return 'Phone number must be exactly 10 digits';
    }
    if (emailCtrl.text.length > 50) {
      return 'Email must be 50 characters or fewer';
    }
    if (pincodeCtrl.text.isNotEmpty &&
        !RegExp(r'^\d{6}$').hasMatch(pincodeCtrl.text.trim())) {
      return 'Pincode must be exactly 6 digits';
    }
    if (formCity.value == 'Others') {
      final othersCity = othersCityCtrl.text.trim();
      if (othersCity.isEmpty) {
        return 'Others city is required';
      }
      if (othersCity.length > 30 || !RegExp(r'^[A-Za-z\s]+$').hasMatch(othersCity)) {
        return 'Others city must be text only, up to 30 characters';
      }
    }
    if (gstinCtrl.text.isNotEmpty &&
        !RegExp(r'^[0-9]{2}[A-Z0-9]{10}[0-9][A-Z][0-9A-Z]$')
            .hasMatch(gstinCtrl.text.trim().toUpperCase())) {
      return 'GST format looks invalid (e.g. 29GGGGG1314R9Z6)';
    }
    return null;
  }

  /// Credit/Debit → the numeric code the API expects for
  /// `opening_balance_type`. Confirmed against the live API's behavior.
  static const Map<BalanceType, String> _balanceTypeCode = {
    BalanceType.credit: '1',
    BalanceType.debit: '2',
  };

  /// Saves the form. This is offline-only, always — a Draft or a regular
  /// Submit/Update both save straight to this device and never call
  /// `party.php` directly, whether or not the internet happens to be
  /// available right now. A regular (non-draft) save is queued in
  /// [CacheKeys.partyPending] via [PartyRepository.queuePartyForSync];
  /// only a manual tap of the Sync button (see [DataSyncService]) ever
  /// sends that queue to the server, in one batch.
  Future<bool> save({bool asDraft = false}) async {
    if (isSaving.value) return false;

    final error = _validate(isDraft: asDraft);
    if (error != null) {
      Get.snackbar('Check the form', error,
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }
    if (!asDraft && nameCtrl.text.trim().isEmpty) {
      Get.snackbar('Missing info', 'Party name is required',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    final session = _sessionService.currentSession.value;
    if (session == null) {
      Get.snackbar('Session expired', 'Please log in again',
          snackPosition: SnackPosition.BOTTOM);
      return false;
    }

    final balance = double.tryParse(openingBalanceCtrl.text) ?? 0;
    final name = nameCtrl.text.trim().isEmpty
        ? 'Untitled Party'
        : nameCtrl.text.trim();

    // party.php has no real "draft" flag in the payload it accepts, and
    // a Draft may have an empty/incomplete name — so a Draft never goes
    // into the sync queue at all; it just lives in the in-memory list on
    // this device until turned into a real save.
    if (asDraft) {
      final savedParty =
          _applyLocally(asDraft: true, balance: balance, name: name);
      Get.back(result: savedParty);
      Get.snackbar('Saved as draft', 'Party saved as a draft on this device',
          snackPosition: SnackPosition.BOTTOM);
      return true;
    }

    isSaving.value = true;
    try {
      // The server no longer assigns `party_id` itself for a brand-new
      // party — the client generates it once, at creation, and sends it
      // as `edit_id` right away (the same pattern already used for
      // Quotation/Estimate ids): the server just stores whatever unique
      // id it's given. Editing an already-synced party reuses its real
      // server id unchanged; editing a still-pending (not yet synced)
      // row reuses the id it was already given, so re-saving before
      // Sync replaces that same queue entry instead of adding a
      // duplicate. Either way, `edit_id` and the queue's `local_id` key
      // end up being the same value — there's no separate "local-only"
      // id to track anymore.
      final String editId = editingParty == null
          ? _newLocalId()
          : (editingParty!.serverPartyId ?? editingParty!.localId ?? _newLocalId());
      final localId = editId;

      await _partyRepository.queuePartyForSync(
        localId: localId,
        editId: editId,
        partyName: name,
        agentId: '', // No agent id source is wired up — agent filter/field was removed from the UI.
        mobileNumber: phoneCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        identification: identificationCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        state: formState.value,
        district: formDistrict.value ?? '',
        city: formCity.value ?? '',
        othersCity:
            formCity.value == 'Others' ? othersCityCtrl.text.trim() : '',
        pincode: pincodeCtrl.text.trim(),
        gstNumber: gstinCtrl.text.trim().toUpperCase(),
        openingBalance: balance == 0 ? '' : balance.toString(),
        openingBalanceType:
            balance == 0 ? '' : _balanceTypeCode[formBalanceType.value]!,
      );

      final wasCreate = editingParty == null;
      final wasAlreadySynced = editingParty?.serverPartyId != null;
      final savedParty = PartyModel(
        id: editId,
        serverPartyId: wasAlreadySynced ? editId : null,
        localId: wasAlreadySynced ? null : editId,
        name: name,
        phone: phoneCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        state: formState.value,
        district: formDistrict.value ?? '',
        city: formCity.value ?? '',
        othersCity:
            formCity.value == 'Others' ? othersCityCtrl.text.trim() : '',
        pincode: pincodeCtrl.text.trim(),
        identification: identificationCtrl.text.trim(),
        gstin: gstinCtrl.text.trim().toUpperCase(),
        openingBalance: balance,
        balanceType: formBalanceType.value,
        isPending: true,
      );
      Get.back(result: savedParty);
      Get.snackbar(
        wasCreate ? 'Saved offline' : 'Updated offline',
        'Saved on this device. Tap Sync when you\'re online to send it to the server.',
        snackPosition: SnackPosition.BOTTOM,
      );
      // Newly-queued rows show up at the top of the merged offline list
      // regardless of page — jump back to page 1 so a create is visible
      // right away; an edit just re-shows the page the user was on.
      if (wasCreate) pageNo.value = 1;
      await loadParties();
      return true;
    } finally {
      isSaving.value = false;
    }
  }

  /// A fresh, unique-enough id for a brand-new pending-queue entry.
  /// Shaped like the server's own `party_id` (a long lowercase hex
  /// string) rather than an obviously-local placeholder, so a party
  /// created offline looks and behaves the same as a synced one
  /// everywhere its id is displayed or matched against.
  String _newLocalId() => IdGenerator.generate();

  /// Mirrors the confirmed save into the in-memory list that backs the
  /// Party list screen. Runs after either a successful API call or a
  /// local-only save.
  PartyModel _applyLocally({
    required bool asDraft,
    required double balance,
    required String name,
  }) {
    if (editingParty != null) {
      editingParty!
        ..agent = formAgent.value ?? ''
        ..name = name
        ..phone = phoneCtrl.text.trim()
        ..email = emailCtrl.text.trim()
        ..address = addressCtrl.text.trim()
        ..state = formState.value
        ..district = formDistrict.value ?? ''
        ..city = formCity.value ?? ''
        ..othersCity = formCity.value == 'Others' ? othersCityCtrl.text.trim() : ''
        ..pincode = pincodeCtrl.text.trim()
        ..identification = identificationCtrl.text.trim()
        ..gstin = gstinCtrl.text.trim().toUpperCase()
        ..openingBalance = balance
        ..balanceType = formBalanceType.value
        ..isDraft = asDraft;
      parties.refresh();
      return editingParty!;
    } else {
      final created = PartyModel(
        id: 'P${(parties.length + 1).toString().padLeft(3, '0')}',
        agent: formAgent.value ?? '',
        name: name,
        phone: phoneCtrl.text.trim(),
        email: emailCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        state: formState.value,
        district: formDistrict.value ?? '',
        city: formCity.value ?? '',
        othersCity:
            formCity.value == 'Others' ? othersCityCtrl.text.trim() : '',
        pincode: pincodeCtrl.text.trim(),
        identification: identificationCtrl.text.trim(),
        gstin: gstinCtrl.text.trim().toUpperCase(),
        openingBalance: balance,
        balanceType: formBalanceType.value,
        isDraft: asDraft,
      );
      parties.insert(0, created);
      return created;
    }
  }

  /// There's no delete endpoint in the API we have for party.php yet —
  /// this only removes the row from the current in-memory page, so a
  /// synced row will reappear next time the list is reloaded. A row
  /// that was still only in the pending-sync queue (never sent to the
  /// server) is fully removed instead, since there's nothing server-side
  /// for it to reappear from.
  void deleteParty(PartyModel party) {
    parties.remove(party);
    if (party.isPending && party.localId != null) {
      _partyRepository.removePendingParty(party.localId!);
    }
    Get.snackbar(
      'Removed from view',
      party.isPending
          ? '${party.name} was removed before it was ever synced.'
          : '${party.name} was removed here, but there\'s no delete API yet — it\'ll reappear on refresh.',
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  void onClose() {
    _searchDebounce?.cancel();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    emailCtrl.dispose();
    addressCtrl.dispose();
    pincodeCtrl.dispose();
    othersCityCtrl.dispose();
    identificationCtrl.dispose();
    gstinCtrl.dispose();
    openingBalanceCtrl.dispose();
    super.onClose();
  }
}