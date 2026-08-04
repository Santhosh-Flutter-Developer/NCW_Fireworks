import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../core/services/data_sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/billing_item_model.dart';
import '../../data/models/party_model.dart';
import '../../data/models/quotation_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/searchable_picker_sheet.dart';
import '../../widgets/sync_action_button.dart';
import '../../widgets/view_mode_toggle.dart';
import 'quotation_controller.dart';
import 'quotation_product_picker_view.dart';

class QuotationListView extends GetView<QuotationController> {
  const QuotationListView({super.key});

  static final _df = DateFormat('dd-MM-yyyy');

  @override
  Widget build(BuildContext context) {
    // GetX only disposes a `lazyPut` controller once every route bound to
    // it has been fully popped off the Navigator stack — if the sidebar
    // re-pushes `/quotation` while an earlier visit is still buried further
    // down the stack, `controller` here is the *same* instance as last
    // time, and `onInit()` (which only ever runs once per instance) can't
    // be relied on to reset it. `_QuotationListFreshVisit` sidesteps that
    // entirely: it's a brand-new widget subtree on every navigation-in
    // (Flutter always builds a fresh `State` for a freshly pushed route),
    // so its `initState()` reliably fires exactly once per visit — see
    // `QuotationController.resetForFreshVisit`.
    return _QuotationListFreshVisit(
      controller: controller,
      child: _QuotationListBody(controller: controller, df: _df),
    );
  }
}

class _QuotationListBody extends StatelessWidget {
  final QuotationController controller;
  final DateFormat df;
  const _QuotationListBody({required this.controller, required this.df});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      routeName: AppRoutes.quotationList,
      title: 'Quotation',
      actions: [
        SyncActionButton(
          // syncAllData() runs the full global sync (Party → Price
          // Upload → Quotation → Estimation → Receipt), not just this
          // screen's own data — see DataSyncService.syncAllData. It only
          // pushes/pulls the cache though, so without reloading here the
          // "Pending sync" badges on this screen would just sit there
          // until something else (search, tab switch, re-entering the
          // page) happened to call loadQuotations() next.
          onSync: () async {
            await Get.find<DataSyncService>().syncAllData();
            await controller.loadQuotations();
          },
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          controller.startCreate();
          // New quotations start on the product picker (pricelists as
          // tabs, products underneath) instead of the empty form — the
          // form only appears once products have been chosen.
          Get.to(() => const QuotationProductPickerView(isEntryPoint: true));
        },
        backgroundColor: AppColors.gold,
        foregroundColor: AppColors.textOnGold,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: Responsive.horizontalPadding(context),
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FilterBar(controller: controller, df: df),
            const SizedBox(height: 14),
            Obx(() => _TabBar(
                  active: controller.activeTab.value,
                  onChanged: controller.setTab,
                )),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _PageSizeSelector(controller: controller),
                Obx(
                  () => ViewModeToggle(
                    isTableView: controller.isTableView.value,
                    onChanged: controller.toggleViewMode,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Obx(() {
              if (controller.isLoadingList.value) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.gold)),
                );
              }
              final list = controller.pagedFiltered;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: EmptyState(
                    icon: Icons.request_quote_rounded,
                    title: 'No quotations found',
                    subtitle: 'Create a new quotation to get started.',
                  ),
                );
              }
              return controller.isTableView.value
                  ? _QuotationTable(list: list, controller: controller)
                  : Column(
                      children: List.generate(list.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _QuotationTile(
                            quotation: list[i],
                            controller: controller,
                          ),
                        );
                      }),
                    );
            }),
            const SizedBox(height: 14),
            _Pager(controller: controller),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters: From Date / To Date / Bill No. search / Party
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final QuotationController controller;
  final DateFormat df;
  const _FilterBar({required this.controller, required this.df});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Obx(() => Expanded(
                  child: _DateField(
                    label: 'From Date',
                    date: controller.filterFrom.value,
                    df: df,
                    onTap: () => _pickDate(context, controller.filterFrom.value,
                        controller.setDateFrom),
                  ),
                )),
            const SizedBox(
              width: 10.0,
            ),
            Obx(() => Expanded(
                  child: _DateField(
                    label: 'To Date',
                    date: controller.filterTo.value,
                    df: df,
                    onTap: () => _pickDate(context, controller.filterTo.value,
                        controller.setDateTo),
                  ),
                )),
          ],
        ),
        const SizedBox(
          height: 10.0,
        ),
        Row(
          children: [
            Expanded(
              child: SearchField(
                hint: 'Bill No. Search',
                onChanged: controller.setSearch,
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 10.0,
        ),
        Row(
          children: [
            Expanded(
              child: Obx(() => _PartyFilterField(
                    value: controller.filterParty.value,
                    parties: controller.parties,
                    onSelected: controller.setPartyFilter,
                  )),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickDate(BuildContext context, DateTime? current,
      ValueChanged<DateTime?> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) onPicked(picked);
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final DateFormat df;
  final VoidCallback onTap;
  const _DateField(
      {required this.label,
      required this.date,
      required this.df,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                date != null ? df.format(date!) : label,
                style: AppTextStyles.body.copyWith(
                  color: date != null
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Party filter — tap to open the searchable "Select Party" sheet
// ---------------------------------------------------------------------------

class _PartyFilterField extends StatelessWidget {
  final String? value; // party *name*, or null for "All Partys"
  final List<PartyModel> parties;
  final ValueChanged<String?> onSelected;
  const _PartyFilterField({
    required this.value,
    required this.parties,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showSearchablePickerSheet<PartyModel>(
        title: 'Select Party',
        searchHint: 'Search party name or phone',
        itemsGetter: () => parties,
        labelOf: (p) => '${p.name} ${p.phone}',
        itemBuilder: (context, p) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.surfaceHigh,
            child: Text(p.initials,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textPrimary)),
          ),
          title: Text(p.name, style: AppTextStyles.bodyStrong),
          subtitle: p.phone.isEmpty
              ? null
              : Text(p.phone, style: AppTextStyles.caption),
        ),
        onSelected: (p) => onSelected(p.name),
        topAction: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Get.back();
            onSelected(null);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('All Partys',
                style:
                    AppTextStyles.bodyStrong.copyWith(color: AppColors.gold)),
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value ?? 'All Partys',
                style: AppTextStyles.body.copyWith(
                  color: value != null
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active / Draft / Cancel tabs
// ---------------------------------------------------------------------------

class _TabBar extends StatelessWidget {
  final QuotationTab active;
  final ValueChanged<QuotationTab> onChanged;
  const _TabBar({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: QuotationTab.values.map((tab) {
          final selected = tab == active;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => onChanged(tab),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  gradient: selected ? AppColors.goldGradient : null,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  tab.label,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.textOnGold
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entries-per-page selector
// ---------------------------------------------------------------------------

class _PageSizeSelector extends StatelessWidget {
  final QuotationController controller;
  const _PageSizeSelector({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: Obx(
              () => DropdownButton<int>(
                value: controller.pageSize.value,
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                dropdownColor: AppColors.surfaceElevated,
                items: const [10, 25, 50, 100]
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) controller.setPageSize(v);
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('entries per page', style: AppTextStyles.caption),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Table view
// ---------------------------------------------------------------------------

class _QuotationTable extends StatelessWidget {
  final List<QuotationModel> list;
  final QuotationController controller;
  const _QuotationTable({required this.list, required this.controller});

  @override
  Widget build(BuildContext context) {
    final df = QuotationListView._df;
    final startIndex =
        (controller.currentPage.value - 1) * controller.pageSize.value;
    return AppDataTable(
      columns: const [
        'S.No',
        'Bill Date',
        'Bill Number',
        'Party Name',
        'Bill Value',
        'Bill Qty',
        'Action',
      ],
      rows: List.generate(list.length, (i) {
        final q = list[i];
        return [
          Text('${startIndex + i + 1}', style: AppTextStyles.body),
          Text(df.format(q.date), style: AppTextStyles.body),
          Text(q.quotationNo, style: AppTextStyles.bodyStrong),
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(q.partyName,
                          style: AppTextStyles.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (q.isPending)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.skyBlue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Pending',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.skyBlue,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                Text('Creator : NCW Fireworks Retail',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          Text('₹${q.total.toStringAsFixed(2)}',
              style: AppTextStyles.bodyStrong.copyWith(color: AppColors.gold)),
          Text(q.qtyLabel, style: AppTextStyles.body),
          _ActionIcons(quotation: q, controller: controller),
        ];
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// List (card) view
// ---------------------------------------------------------------------------

class _QuotationTile extends StatelessWidget {
  final QuotationModel quotation;
  final QuotationController controller;
  const _QuotationTile({required this.quotation, required this.controller});

  @override
  Widget build(BuildContext context) {
    final df = QuotationListView._df;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          controller.startEdit(quotation);
          Get.toNamed(AppRoutes.quotationForm);
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(quotation.quotationNo,
                        style: AppTextStyles.bodyStrong),
                  ),
                  if (quotation.isPending)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.skyBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Pending sync',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.skyBlue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  StatusBadge(status: quotation.status),
                ],
              ),
              const SizedBox(height: 4),
              Text(quotation.partyName, style: AppTextStyles.body),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text(df.format(quotation.date), style: AppTextStyles.caption),
                  const SizedBox(width: 14),
                  Icon(Icons.inventory_2_outlined,
                      size: 13, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text(quotation.qtyLabel, style: AppTextStyles.caption),
                  const Spacer(),
                  Text('₹${quotation.total.toStringAsFixed(0)}',
                      style: AppTextStyles.bodyStrong
                          .copyWith(color: AppColors.gold)),
                ],
              ),
              const Divider(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child:
                    _ActionIcons(quotation: quotation, controller: controller),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row/card actions: print, download, share, convert, edit, delete
// ---------------------------------------------------------------------------

class _ActionIcons extends StatelessWidget {
  final QuotationModel quotation;
  final QuotationController controller;
  const _ActionIcons({required this.quotation, required this.controller});

  @override
  Widget build(BuildContext context) {
    final isDraft = quotation.status == DocStatus.draft;
    final isCancelled = quotation.status == DocStatus.cancelled;
    // Once a quotation has been converted (estimate_id is no longer
    // empty), it's read-only on this screen — only Print/Download remain.
    final isConverted = quotation.isConverted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Print',
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.printQuotation(quotation),
          icon: Icon(Icons.print_rounded, color: AppColors.ember, size: 18),
        ),
        IconButton(
          tooltip: 'Download',
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.downloadQuotation(quotation),
          icon: Icon(Icons.file_download_rounded,
              color: AppColors.skyBlue, size: 18),
        ),
        IconButton(
          tooltip: 'Share',
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.shareQuotation(quotation),
          icon: Icon(Icons.share_rounded, color: AppColors.teal, size: 18),
        ),
        WhatsAppIconButton(
          onPressed: () => controller.shareQuotationToWhatsApp(quotation),
        ),
        if (!isConverted) ...[
          if (!isCancelled && !isDraft)
            IconButton(
              tooltip: 'Convert to Estimate',
              visualDensity: VisualDensity.compact,
              onPressed: () => controller.convertToEstimate(quotation),
              icon:
                  Icon(Icons.sync_alt_rounded, color: AppColors.gold, size: 18),
            ),
          if (!isCancelled)
            IconButton(
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                controller.startEdit(quotation);
                Get.toNamed(AppRoutes.quotationForm);
              },
              icon: Icon(Icons.edit_rounded, color: AppColors.teal, size: 18),
            ),
          if (!isCancelled)
            IconButton(
              tooltip:
                  !controller.isKnownToServer(quotation) ? 'Remove' : 'Cancel',
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDelete(context, isDraft),
              icon: Icon(Icons.delete_outline_rounded,
                  color: AppColors.danger, size: 18),
            ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, bool isDraft) async {
    final neverSynced = !controller.isKnownToServer(quotation);
    final title = neverSynced ? 'Remove this?' : 'Cancel quotation?';
    final message = neverSynced
        ? '${quotation.quotationNo.isEmpty ? "This quotation" : quotation.quotationNo} hasn\'t been synced yet — it will just be removed from this device.'
        : '${quotation.quotationNo} will be cancelled and moved to the Cancel tab — sent to the server next time you Sync.';
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: Text(title, style: AppTextStyles.h3),
        content: Text(message, style: AppTextStyles.body),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: Text(neverSynced ? 'Remove' : 'Cancel Quotation',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteQuotation(quotation);
    }
  }
}

// ---------------------------------------------------------------------------
// Pagination footer
// ---------------------------------------------------------------------------

class _Pager extends StatelessWidget {
  final QuotationController controller;
  const _Pager({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final countOnPage = controller.quotations.length;
      final pages = controller.totalPages;
      final page = controller.currentPage.value;
      final busy = controller.isLoadingList.value;

      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Text(
            countOnPage == 0
                ? 'No entries on this page'
                : 'Showing $countOnPage ${countOnPage == 1 ? 'entry' : 'entries'}',
            style: AppTextStyles.caption,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: page > 1 && !busy
                    ? () => controller.goToPage(page - 1)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$page / $pages',
                    style: AppTextStyles.bodyStrong
                        .copyWith(color: AppColors.textOnGold)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: page < pages && !busy
                    ? () => controller.goToPage(page + 1)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
              ),
            ],
          ),
        ],
      );
    });
  }
}

/// Forces a reset to defaults (empty search, page size 10, page 1, Active
/// tab, cleared date filters, "All Partys", list view, plus a reload)
/// exactly once every time the Quotation list screen is freshly navigated
/// to — see the comment in `QuotationListView.build` for why this can't
/// just live in `QuotationController.onInit()` alone. Being a
/// `StatefulWidget`, Flutter builds a brand-new `State` for it on every
/// fresh route push regardless of whether GetX handed back a reused
/// controller instance or a new one.
class _QuotationListFreshVisit extends StatefulWidget {
  final QuotationController controller;
  final Widget child;
  const _QuotationListFreshVisit({
    required this.controller,
    required this.child,
  });

  @override
  State<_QuotationListFreshVisit> createState() =>
      _QuotationListFreshVisitState();
}

class _QuotationListFreshVisitState extends State<_QuotationListFreshVisit> {
  @override
  void initState() {
    super.initState();
    // resetForFreshVisit() mutates Rx values (searchQuery, currentPage,
    // pageSize, activeTab, filterFrom, filterTo, filterParty,
    // isTableView...), which makes every Obx watching them ask to rebuild.
    // Calling that synchronously here — inside initState(), which itself
    // runs as part of mounting this very widget tree — asks Flutter to
    // rebuild a widget while its own ancestors (QuotationListView) are
    // still mid-build, which throws "setState() or markNeedsBuild() called
    // during build". Deferring to right after this frame finishes avoids
    // that entirely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.resetForFreshVisit();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}