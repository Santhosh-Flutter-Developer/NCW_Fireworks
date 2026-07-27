/// Key names used in [LocalCacheService] for everything [DataSyncService]
/// pulls down after a successful online login. Centralized here so the
/// sync side (writes) and the future offline-read side (repositories
/// reading cache-first) always agree on the same keys.
class CacheKeys {
  CacheKeys._();

  static const party = 'party_list';

  /// Queue of Party adds/edits made on this device that haven't been sent
  /// to `party.php` yet. Every save from the Party form — create or edit,
  /// online or offline — lands here first; only a manual tap of the Sync
  /// button ever drains it (see [PartyRepository.queuePartyForSync] /
  /// [PartyRepository.syncPendingParties]).
  static const partyPending = 'party_pending';

  static const priceRows = 'price_list_rows';
  static const priceLists = 'price_list_options';
  static const priceProducts = 'price_list_products';

  static const quotationActive = 'quotation_active';
  static const quotationDraft = 'quotation_draft';
  static const quotationCancel = 'quotation_cancel';
  static const quotationParties = 'quotation_parties';

  /// Queue of Quotation adds/edits made on this device that haven't been
  /// sent to `quotation.php` yet. Every save from the Quotation form —
  /// draft or confirmed, create or edit, online or offline — lands here
  /// first, and so does an offline Cancel (see
  /// `QuotationController.deleteQuotation`); only a manual tap of the
  /// Sync button ever drains it (see
  /// [QuotationRepository.queueQuotationForSync] /
  /// [QuotationRepository.syncPendingQuotations]).
  static const quotationPending = 'quotation_pending';

  /// Pricelist dropdown options (`{pricelist_id, pricelist_name}`) for the
  /// Add/Edit Quotation form — synced once at login and via Sync, so
  /// opening the form never needs the network.
  static const quotationPricelists = 'quotation_pricelists';

  /// The full product catalogue for every pricelist (id, name, unit,
  /// rate, discount flag, each tagged with its `pricelist_id`) — backs
  /// the form's product picker entirely offline.
  static const quotationProducts = 'quotation_products';

  /// Other-charges dropdown options for the Add/Edit Quotation form's
  /// Charges row (`{other_charges_id, other_charges_name, charges_type}`)
  /// — synced once at login and via Sync, same shape as
  /// [estimationOtherCharges], so opening the form never needs the
  /// network.
  static const quotationOtherCharges = 'quotation_other_charges';

  static const estimationActive = 'estimation_active';
  static const estimationDraft = 'estimation_draft';
  static const estimationCancel = 'estimation_cancel';
  static const estimationAgents = 'estimation_agents';
  static const estimationParties = 'estimation_parties';

  /// Queue of Estimate adds/edits made on this device that haven't been
  /// sent to `estimate.php` yet. Every save from the Estimate form —
  /// draft or confirmed, create or edit, online or offline — lands here
  /// first, and so does an offline Cancel (see
  /// `EstimationController.deleteEstimation`); only a manual tap of the
  /// Sync button ever drains it (see
  /// [EstimateRepository.queueEstimateForSync] /
  /// [EstimateRepository.syncPendingEstimates]).
  static const estimationPending = 'estimation_pending';

  /// Pricelist dropdown options (`{id, name}`) for the Add/Edit Estimate
  /// form — synced once at login and via Sync, so opening the form never
  /// needs the network.
  static const estimationPricelists = 'estimation_pricelists';

  /// The full product catalogue for every pricelist (id, name, unit,
  /// rate, discount flag, current stock, each tagged with its
  /// `pricelist_id`) — backs the Estimate form's product picker entirely
  /// offline.
  static const estimationProducts = 'estimation_products';

  /// Other-charges dropdown options (`{id, name, type}`) for the Add/Edit
  /// Estimate form's Charges row — `type` ("Plus"/"Minus") is fetched once
  /// per charge at Sync time so picking a charge offline never needs
  /// `type_other_charges_id`.
  static const estimationOtherCharges = 'estimation_other_charges';

  static const receiptActive = 'receipt_active';
  static const receiptCancel = 'receipt_cancel';
  static const receiptParties = 'receipt_parties';

  /// Queue of Receipts (Bill Payments) created against an estimate on
  /// this device that haven't been sent to `receipt.php` yet. Every
  /// "convert Estimate to Receipt" made from the Estimate list — online
  /// or offline — lands here first; only a manual tap of the Sync button
  /// ever drains it (see [ReceiptRepository.queueReceiptForSync] /
  /// [ReceiptRepository.syncPendingReceipts]). Each entry also carries
  /// the source estimate's own id so the Estimate list can immediately
  /// hide that estimate's Receipt/Edit icons — see
  /// [ReceiptRepository.markEstimateLocallyConverted].
  static const receiptPending = 'receipt_pending';

  /// Payment Mode dropdown options (`{id, name}`) for the Add Receipt
  /// form — synced once at login and via Sync, so opening the form never
  /// needs the network.
  static const receiptPaymentModes = 'receipt_payment_modes';

  /// Bank dropdown options per payment mode (`{payment_mode_id, id,
  /// name}`) for the Add Receipt form's Bank field — cached once per
  /// payment mode at Sync time so picking a bank offline never needs a
  /// live `selected_bank_payment_mode` call.
  static const receiptBanks = 'receipt_banks';


  /// ISO-8601 timestamp string of the last time [DataSyncService.syncAll]
  /// completed (even if some individual steps failed).
  static const lastSyncedAt = 'meta_last_synced_at';

  /// Category dropdown options (`{category_id, category_name}`) for the
  /// Add Custom Product form — synced once at login/Sync from
  /// `product.php`'s `add_custom_product` call
  /// (see `CustomProductRepository.getInitData`), read offline by both
  /// the Quotation and Estimation product pickers.
  static const customProductCategories = 'custom_product_categories';

  /// Unit dropdown options (`{unit_id, unit_name}`) for the Add Custom
  /// Product form — same source/refresh as [customProductCategories].
  static const customProductUnits = 'custom_product_units';

  /// Queue of custom products added from either the Quotation or
  /// Estimation product picker that haven't been sent to `product.php`
  /// yet. Deliberately shared between both modules — see
  /// `CustomProductRepository`'s class doc — so a custom product added
  /// while building a quotation shows up in the Estimation picker (for
  /// the same pricelist) immediately, and vice versa. Only a manual tap
  /// of the Sync button on *either* screen ever drains it (see
  /// `CustomProductRepository.queueCustomProduct` /
  /// `syncPendingCustomProducts`), and always *before* that Sync pushes
  /// the quotations/estimates themselves, so a line referencing a custom
  /// product's locally-generated id is never sent before the server
  /// knows that id.
  static const customProductPending = 'custom_product_pending';
}