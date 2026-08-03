import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:ncw_fireworks/data/models/billing_item_model.dart';
import '../../core/services/data_sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/party_model.dart';
import '../../data/models/receipt_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/searchable_picker_sheet.dart';
import '../../widgets/sync_action_button.dart';
import '../../widgets/view_mode_toggle.dart';
import 'receipt_controller.dart';

class ReceiptListView extends GetView<ReceiptController> {
  const ReceiptListView({super.key});

  static final _df = DateFormat('dd-MM-yyyy');

  @override
  Widget build(BuildContext context) {
    // GetX only disposes a `lazyPut` controller once every route bound to
    // it has been fully popped off the Navigator stack — if the sidebar
    // re-pushes `/receipt` while an earlier visit is still buried further
    // down the stack, `controller` here is the *same* instance as last
    // time, and `onInit()` (which only ever runs once per instance) can't
    // be relied on to reset it. `_ReceiptListFreshVisit` sidesteps that
    // entirely: it's a brand-new widget subtree on every navigation-in
    // (Flutter always builds a fresh `State` for a freshly pushed route),
    // so its `initState()` reliably fires exactly once per visit — see
    // `ReceiptController.resetForFreshVisit`.
    return _ReceiptListFreshVisit(
      controller: controller,
      child: _ReceiptListBody(controller: controller, df: _df),
    );
  }
}

class _ReceiptListBody extends StatelessWidget {
  final ReceiptController controller;
  final DateFormat df;
  const _ReceiptListBody({required this.controller, required this.df});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      routeName: AppRoutes.receiptList,
      title: 'Receipt',
      actions: [
        SyncActionButton(
          // syncAllData() runs the full global sync (Party → Price
          // Upload → Quotation → Estimation → Receipt), not just this
          // screen's own data — see DataSyncService.syncAllData. It only
          // pushes/pulls the cache though, so without reloading here the
          // "Pending sync" badges on this screen would just sit there
          // until something else (search, tab switch, re-entering the
          // page) happened to call loadReceipts() next.
          onSync: () async {
            await Get.find<DataSyncService>().syncAllData();
            await controller.loadReceipts();
          },
        ),
      ],
      // floatingActionButton: FloatingActionButton.extended(
      //   onPressed: () {
      //     controller.startCreate();
      //     Get.toNamed(AppRoutes.receiptForm);
      //   },
      //   backgroundColor: AppColors.gold,
      //   foregroundColor: AppColors.textOnGold,
      //   icon: const Icon(Icons.add_rounded),
      //   label: const Text('Add'),
      // ),
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
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                      child: CircularProgressIndicator(color: AppColors.gold)),
                );
              }
              final list = controller.visibleReceipts;
              if (list.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No receipts found',
                    subtitle: 'Create a new receipt to get started.',
                  ),
                );
              }
              return controller.isTableView.value
                  ? _ReceiptTable(list: list, controller: controller)
                  : Column(
                      children: List.generate(list.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ReceiptTile(
                            receipt: list[i],
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
// Filters: From Date / To Date / Receipt No. search / Agent / Party
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final ReceiptController controller;
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
            const SizedBox(width: 10.0),
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
        const SizedBox(height: 10.0),
        Row(
          children: [
            Expanded(
              child: SearchField(
                hint: 'Receipt No. Search',
                onChanged: controller.setSearch,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10.0),
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
// Party filter — tap to open the searchable "Select Party" sheet, same
// widget/behaviour as the Quotation list screen's Party filter.
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
// Active / Cancel tabs — mirrors Quotation's tab bar, driving
// `receipt_listing`'s `cancelled` request flag.
// ---------------------------------------------------------------------------

class _TabBar extends StatelessWidget {
  final ReceiptTab active;
  final ValueChanged<ReceiptTab> onChanged;
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
        children: ReceiptTab.values.map((tab) {
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
  final ReceiptController controller;
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

class _ReceiptTable extends StatelessWidget {
  final List<ReceiptModel> list;
  final ReceiptController controller;
  const _ReceiptTable({required this.list, required this.controller});

  @override
  Widget build(BuildContext context) {
    final df = ReceiptListView._df;
    final startIndex =
        (controller.currentPage.value - 1) * controller.pageSize.value;
    return AppDataTable(
      columns: const [
        'S.No',
        'Receipt Date',
        'Receipt Number',
        'Agent Name',
        'Party Name',
        'Amount',
        'Action',
      ],
      rows: List.generate(list.length, (i) {
        final r = list[i];
        return [
          Text('${startIndex + i + 1}', style: AppTextStyles.body),
          Text(df.format(r.date), style: AppTextStyles.body),
          Text(r.receiptNumber, style: AppTextStyles.bodyStrong),
          Text(r.agentName, style: AppTextStyles.body),
          SizedBox(
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(r.partyName,
                    style: AppTextStyles.bodyStrong,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('Creator : NCW Fireworks Retail',
                    style: AppTextStyles.caption),
              ],
            ),
          ),
          Text('₹${r.totalAmount.toStringAsFixed(2)}',
              style: AppTextStyles.bodyStrong.copyWith(color: AppColors.gold)),
          _ActionIcons(receipt: r, controller: controller),
        ];
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// List (card) view
// ---------------------------------------------------------------------------

class _ReceiptTile extends StatelessWidget {
  final ReceiptModel receipt;
  final ReceiptController controller;
  const _ReceiptTile({required this.receipt, required this.controller});

  @override
  Widget build(BuildContext context) {
    final df = ReceiptListView._df;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(receipt.receiptNumber,
                    style: AppTextStyles.bodyStrong),
              ),
              if (receipt.isPending)
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
              StatusBadge(status: receipt.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(receipt.partyName, style: AppTextStyles.body),
          const SizedBox(height: 2),
          Text('Agent: ${receipt.agentName}', style: AppTextStyles.caption),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 5),
              Text(df.format(receipt.date), style: AppTextStyles.caption),
              const Spacer(),
              Text('₹${receipt.totalAmount.toStringAsFixed(0)}',
                  style: AppTextStyles.bodyStrong
                      .copyWith(color: AppColors.gold)),
            ],
          ),
          const Divider(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: _ActionIcons(receipt: receipt, controller: controller),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Row/card actions: print, download, share, delete (no edit — receipts can
// only be created or cancelled, never edited, server-side)
// ---------------------------------------------------------------------------

class _ActionIcons extends StatelessWidget {
  final ReceiptModel receipt;
  final ReceiptController controller;
  const _ActionIcons({required this.receipt, required this.controller});

  bool get _isCancelled => receipt.status == DocStatus.cancelled;

  Future<void> _confirmDelete(BuildContext context) async {
    final isPending = receipt.isPending;
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        backgroundColor: AppColors.surfaceElevated,
        title: const Text('Cancel Receipt'),
        content: Text(isPending
            ? 'This receipt hasn\'t synced yet. Cancel it and un-hide the estimate\'s Receipt/Edit options?'
            : 'This will cancel the receipt on the server the next time you Sync. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text('Cancel Receipt'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      controller.deleteReceipt(receipt);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Print',
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.printReceipt(receipt),
          icon: Icon(Icons.print_rounded, color: AppColors.ember, size: 18),
        ),
        IconButton(
          tooltip: 'Download',
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.downloadReceipt(receipt),
          icon: Icon(Icons.download_rounded, color: AppColors.ember, size: 18),
        ),
        IconButton(
          tooltip: 'Share',
          visualDensity: VisualDensity.compact,
          onPressed: () => controller.shareReceipt(receipt),
          icon: Icon(Icons.share_rounded, color: AppColors.teal, size: 18),
        ),
         if (!_isCancelled)
        IconButton(
          tooltip: 'Cancel',
          visualDensity: VisualDensity.compact,
          onPressed: () => _confirmDelete(context),
          icon:
              Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pagination footer
// ---------------------------------------------------------------------------

class _Pager extends StatelessWidget {
  final ReceiptController controller;
  const _Pager({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final countOnPage = controller.visibleReceipts.length;
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
/// exactly once every time the Receipt list screen is freshly navigated
/// to — see the comment in `ReceiptListView.build` for why this can't
/// just live in `ReceiptController.onInit()` alone. Being a
/// `StatefulWidget`, Flutter builds a brand-new `State` for it on every
/// fresh route push regardless of whether GetX handed back a reused
/// controller instance or a new one.
class _ReceiptListFreshVisit extends StatefulWidget {
  final ReceiptController controller;
  final Widget child;
  const _ReceiptListFreshVisit({
    required this.controller,
    required this.child,
  });

  @override
  State<_ReceiptListFreshVisit> createState() =>
      _ReceiptListFreshVisitState();
}

class _ReceiptListFreshVisitState extends State<_ReceiptListFreshVisit> {
  @override
  void initState() {
    super.initState();
    // resetForFreshVisit() mutates Rx values (searchQuery, currentPage,
    // pageSize, activeTab, filterFrom, filterTo, filterParty,
    // isTableView...), which makes every Obx watching them ask to rebuild.
    // Calling that synchronously here — inside initState(), which itself
    // runs as part of mounting this very widget tree — asks Flutter to
    // rebuild a widget while its own ancestors (ReceiptListView) are
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