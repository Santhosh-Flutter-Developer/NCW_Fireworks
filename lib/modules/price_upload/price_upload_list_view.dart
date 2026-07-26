import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../core/services/data_sync_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/responsive.dart';
import '../../data/models/product_price_list_model.dart';
import '../../routes/app_routes.dart';
import '../../widgets/app_data_table.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/sync_action_button.dart';
import '../../widgets/view_mode_toggle.dart';
import 'price_upload_controller.dart';

class PriceUploadListView extends GetView<PriceUploadController> {
  const PriceUploadListView({super.key});

  @override
  Widget build(BuildContext context) {
    // GetX only disposes a `lazyPut` controller once every route bound to
    // it has been fully popped off the Navigator stack — if the sidebar
    // re-pushes this route while an earlier visit is still buried
    // further down the stack, `controller` here is the *same* instance
    // as last time, and `onInit()` (which only ever runs once per
    // instance) can't be relied on to reset it. `_PriceUploadFreshVisit`
    // sidesteps that entirely: it's a brand-new widget subtree on every
    // navigation-in (Flutter always builds a fresh `State` for a freshly
    // pushed route), so its `initState()` reliably fires exactly once
    // per visit — see `PriceUploadController.resetForFreshVisit`.
    return _PriceUploadFreshVisit(
      controller: controller,
      child: AppScaffold(
        routeName: AppRoutes.priceUpload,
        title: 'Product Price',
        actions: [
          SyncActionButton(
            // syncAllData() runs the full global sync (Party → Price
            // Upload → Quotation → Estimation → Receipt), not just this
            // screen's own data — see DataSyncService.syncAllData. It
            // only pushes/pulls the cache though, so without reloading
            // here this screen's rows wouldn't reflect the fresh sync
            // until something else (filter change, pagination,
            // re-entering the page) happened to call fetchPriceList()
            // next.
            onSync: () async {
              await Get.find<DataSyncService>().syncAllData();
              await controller.fetchPriceList();
            },
          ),
        ],
        body: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.horizontalPadding(context),
            vertical: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FilterBar(controller: controller),
              const SizedBox(height: 16),
              Row(
                children: [
                  _PageSizeSelector(controller: controller),
                  const Spacer(),
                  Obx(
                    () => _CircleIconButton(
                      icon: Icons.file_download_rounded,
                      color: AppColors.success,
                      tooltip: 'Export',
                      isBusy: controller.isExporting.value,
                      onTap: controller.isExporting.value
                          ? null
                          : controller.exportToExcel,
                    ),
                  ),
                  const SizedBox(
                    width: 8.0,
                  ),
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
                if (controller.isLoading.value && controller.rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final error = controller.errorText.value;
                if (error != null) {
                  return _ErrorState(message: error, onRetry: controller.retry);
                }
                final list = controller.rows;
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: EmptyState(
                      icon: Icons.sell_outlined,
                      title: 'No prices found',
                      subtitle: 'Try a different pricelist or product filter.',
                    ),
                  );
                }
                return Stack(
                  children: [
                    controller.isTableView.value
                        ? _PriceTable(list: list, controller: controller)
                        : Column(
                            children: List.generate(list.length, (i) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _PriceTile(
                                  row: list[i],
                                  controller: controller,
                                ),
                              );
                            }),
                          ),
                    if (controller.isLoading.value)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 3,
                            color: AppColors.gold,
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: 14),
              _Pager(controller: controller),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

/// Forces a reset to defaults (both filters back to "All", page limit 10,
/// page 1, list view) exactly once every time the Price Upload screen is
/// freshly navigated to — see the comment in `PriceUploadListView.build`
/// for why this can't just live in `PriceUploadController.onInit()`
/// alone. Being a `StatefulWidget`, Flutter builds a brand-new `State`
/// for it on every fresh route push regardless of whether GetX handed
/// back a reused controller instance or a new one.
class _PriceUploadFreshVisit extends StatefulWidget {
  final PriceUploadController controller;
  final Widget child;
  const _PriceUploadFreshVisit({
    required this.controller,
    required this.child,
  });

  @override
  State<_PriceUploadFreshVisit> createState() =>
      _PriceUploadFreshVisitState();
}

class _PriceUploadFreshVisitState extends State<_PriceUploadFreshVisit> {
  @override
  void initState() {
    super.initState();
    // resetForFreshVisit() mutates Rx values, which makes every Obx
    // watching them ask to rebuild. Calling that synchronously here —
    // inside initState(), which itself runs as part of mounting this
    // very widget tree — asks Flutter to rebuild a widget while its own
    // ancestors (PriceUploadListView) are still mid-build, which throws
    // "setState() or markNeedsBuild() called during build". Deferring to
    // right after this frame finishes avoids that entirely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.resetForFreshVisit();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ---------------------------------------------------------------------------
// Filters: Pricelist / Product dropdowns + Export + Upload actions,
// matching the toolbar above the web app's Product Price table.
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final PriceUploadController controller;
  const _FilterBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final isWide = Responsive.isTablet(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Obx(() => _LabeledDropdown(
                label: 'Pricelist',
                value: controller.filterPricelistId.value,
                hint: 'Select Pricelist',
                items: controller.pricelistOptions
                    .map((o) => MapEntry(o.id, o.name))
                    .toList(),
                onChanged: controller.setFilterPricelist,
              )),
        ),
        SizedBox(width: isWide ? 14 : 8),
        Expanded(
          child: Obx(() => _LabeledDropdown(
                label: 'Product',
                value: controller.filterProductId.value,
                hint: 'Select Product',
                items: controller.productOptions
                    .map((o) => MapEntry(o.id, o.name))
                    .toList(),
                onChanged: controller.setFilterProduct,
              )),
        ),
        // SizedBox(width: isWide ? 14 : 8),
        // _CircleIconButton(
        //   icon: Icons.file_download_rounded,
        //   color: AppColors.success,
        //   tooltip: 'Export',
        //   onTap: () => Get.snackbar('Export', 'Coming soon',
        //       snackPosition: SnackPosition.BOTTOM),
        // ),
        // const SizedBox(width: 8),
        // _CircleIconButton(
        //   icon: Icons.upload_file_rounded,
        //   color: AppColors.surfaceHigh,
        //   iconColor: AppColors.textPrimary,
        //   tooltip: 'Upload Price',
        //   onTap: () => Get.bottomSheet(
        //     _UploadPriceSheet(controller: controller),
        //     isScrollControlled: true,
        //   ),
        // ),
      ],
    );
  }
}

/// A dropdown whose displayed items are (id, label) pairs — the API's
/// filters run on opaque `pricelist_id`/`product_id` values, not names.
class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final String hint;
  final List<MapEntry<String, String>> items;
  final ValueChanged<String?> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Guard against a stale selection no longer present in the option
    // list (e.g. options haven't loaded yet).
    final safeValue = items.any((e) => e.key == value) ? value : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safeValue,
              isExpanded: true,
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.textMuted),
              hint: Text(
                hint,
                style: AppTextStyles.body.copyWith(color: AppColors.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
              dropdownColor: AppColors.surfaceElevated,
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('All',
                      style: AppTextStyles.body
                          .copyWith(color: AppColors.textMuted)),
                ),
                ...items.map(
                  (e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isBusy;

  const _CircleIconButton({
    required this.icon,
    required this.color,
    this.iconColor = Colors.white,
    required this.tooltip,
    required this.onTap,
    this.isBusy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isBusy ? color.withOpacity(0.6) : color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: isBusy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                    ),
                  )
                : Icon(icon, size: 18, color: iconColor),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entries-per-page selector
// ---------------------------------------------------------------------------

class _PageSizeSelector extends StatelessWidget {
  final PriceUploadController controller;
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
          child: Obx(
            () => DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: controller.pageLimit.value,
                style:
                    AppTextStyles.body.copyWith(color: AppColors.textPrimary),
                dropdownColor: AppColors.surfaceElevated,
                items: PriceUploadController.pageSizeOptions
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) controller.setPageLimit(v);
                },
              ),
            ),
          ),
        ),
        // const SizedBox(width: 8),
        // Text('entries per page', style: AppTextStyles.caption),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error state with retry
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 36, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('Couldn\'t load prices', style: AppTextStyles.h3),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table view
// ---------------------------------------------------------------------------

class _PriceTable extends StatelessWidget {
  final List<ProductPriceRow> list;
  final PriceUploadController controller;
  const _PriceTable({required this.list, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AppDataTable(
      columns: const [
        'S.No',
        'Pricelist',
        'Product',
        'Price',
        'Unit',
        'Discount',
        // 'Action',
      ],
      rows: list.map((row) {
        return [
          Text('${row.sno}', style: AppTextStyles.body),
          SizedBox(
            width: 190,
            child: Text(row.pricelistName,
                style: AppTextStyles.bodyStrong,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 220,
            child: Text(row.productName,
                style: AppTextStyles.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          Text(row.price.toStringAsFixed(2),
              style: AppTextStyles.bodyStrong.copyWith(color: AppColors.gold)),
          Text(row.unit, style: AppTextStyles.body),
          TablePill(
            label: row.discountEnabled ? 'ON' : 'OFF',
            color:
                row.discountEnabled ? AppColors.success : AppColors.textMuted,
          ),
          // IconButton(
          //   tooltip: 'Delete',
          //   visualDensity: VisualDensity.compact,
          //   onPressed: () => controller.deleteRow(row),
          //   icon: Icon(Icons.delete_outline_rounded,
          //       color: AppColors.danger, size: 18),
          // ),
        ];
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// List (card) view
// ---------------------------------------------------------------------------

class _PriceTile extends StatelessWidget {
  final ProductPriceRow row;
  final PriceUploadController controller;
  const _PriceTile({required this.row, required this.controller});

  @override
  Widget build(BuildContext context) {
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
                child: Text(row.productName, style: AppTextStyles.bodyStrong),
              ),
              Text('₹${row.price.toStringAsFixed(2)}',
                  style:
                      AppTextStyles.bodyStrong.copyWith(color: AppColors.gold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(row.pricelistName, style: AppTextStyles.caption),
          const SizedBox(height: 10),
          Row(
            children: [
              TablePill(label: row.unit, color: AppColors.skyBlue),
              const SizedBox(width: 8),
              TablePill(
                label: 'Discount ${row.discountEnabled ? "ON" : "OFF"}',
                color: row.discountEnabled
                    ? AppColors.success
                    : AppColors.textMuted,
              ),
              const Spacer(),
              // IconButton(
              //   visualDensity: VisualDensity.compact,
              //   onPressed: () => controller.deleteRow(row),
              //   icon: Icon(Icons.delete_outline_rounded,
              //       color: AppColors.danger, size: 18),
              // ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upload price bottom sheet
// ---------------------------------------------------------------------------

class _UploadPriceSheet extends StatefulWidget {
  final PriceUploadController controller;
  const _UploadPriceSheet({required this.controller});

  @override
  State<_UploadPriceSheet> createState() => _UploadPriceSheetState();
}

class _UploadPriceSheetState extends State<_UploadPriceSheet> {
  String? _pricelistId;
  String? _productId;
  bool _discountEnabled = true;
  final _priceCtrl = TextEditingController();

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return Container(
      constraints: BoxConstraints(maxHeight: Get.height * 0.85),
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Upload Price', style: AppTextStyles.h2),
                IconButton(
                  onPressed: Get.back,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text('Add or update a product\'s price for a pricelist',
                style: AppTextStyles.caption),
            const SizedBox(height: 18),
            Text('Pricelist', style: AppTextStyles.caption),
            const SizedBox(height: 6),
            Obx(() => _sheetDropdown(
                  value: _pricelistId,
                  hint: 'Select Pricelist',
                  items: controller.pricelistOptions
                      .map((o) => MapEntry(o.id, o.name))
                      .toList(),
                  onChanged: (v) => setState(() => _pricelistId = v),
                )),
            const SizedBox(height: 14),
            Text('Product', style: AppTextStyles.caption),
            const SizedBox(height: 6),
            Obx(() => _sheetDropdown(
                  value: _productId,
                  hint: 'Select Product',
                  items: controller.productOptions
                      .map((o) => MapEntry(o.id, o.name))
                      .toList(),
                  onChanged: (v) => setState(() => _productId = v),
                )),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Price', style: AppTextStyles.caption),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: AppTextStyles.body
                            .copyWith(color: AppColors.textPrimary),
                        decoration: const InputDecoration(hintText: '0.00'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Discount', style: AppTextStyles.caption),
                    Switch(
                      value: _discountEnabled,
                      onChanged: (v) => setState(() => _discountEnabled = v),
                      activeColor: AppColors.gold,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => controller.submitUpload(
                  pricelistId: _pricelistId,
                  productId: _productId,
                  price: double.tryParse(_priceCtrl.text.trim()),
                ),
                child: const Text('Submit'),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _sheetDropdown({
    required String? value,
    required String hint,
    required List<MapEntry<String, String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeValue = items.any((e) => e.key == value) ? value : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          hint: Text(hint,
              style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
          dropdownColor: AppColors.surfaceElevated,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMuted),
          style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
          items: items
              .map((e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pagination footer — the API doesn't return a total row count, so this
// works off "was this page full" rather than a known page total.
// ---------------------------------------------------------------------------

class _Pager extends StatelessWidget {
  final PriceUploadController controller;
  const _Pager({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final page = controller.pageNumber.value;
      final pages = controller.totalPages;
      final count = controller.rows.length;
      final start =
          count == 0 ? 0 : (page - 1) * controller.pageLimit.value + 1;
      final end = start + count - 1;
      final busy = controller.isLoading.value;

      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          Text(
            count == 0 ? 'Showing 0 entries' : 'Showing $start to $end',
            style: AppTextStyles.caption,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: controller.hasPrevPage && !busy
                    ? controller.firstPage
                    : null,
                icon: const Icon(Icons.first_page_rounded, size: 18),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: controller.hasPrevPage && !busy
                    ? controller.prevPage
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
                onPressed: controller.hasNextPage && !busy
                    ? controller.nextPage
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