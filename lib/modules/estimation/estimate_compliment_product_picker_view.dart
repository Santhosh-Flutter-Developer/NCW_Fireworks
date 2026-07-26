import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/estimate/estimate_product_list_response_model.dart';
import '../../data/models/estimate/id_name.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/custom_product_form_sheet.dart';
import 'estimation_controller.dart';

/// A product picked on this screen, kept alongside the exact pricelist
/// option (unit) it was picked under — see
/// [EstimationController.addComplimentSelections].
class _SelectedLine {
  final EstimateProductOption option;
  int qty;
  _SelectedLine({required this.option, required this.qty});
}

/// Full-screen product picker for "+ Add Compliment Products" on the
/// Add/Edit Estimate form.
///
/// Deliberately the compliment counterpart of [EstimateProductPickerView]
/// — same pricelist tabs, search, and grid/list toggle — but never shows
/// a rate: a compliment product is a free/no-charge line, name and
/// quantity only. It also never calls the network itself: it reads the
/// exact same [EstimationController.productOptions] the ordinary "Add
/// Item" picker already loaded for the selected pricelist (catalogue +
/// any not-yet-synced custom products — see
/// `EstimationController.loadProductsForSelectedPricelist`), so a custom
/// product added from either picker shows up here too.
class EstimateComplimentProductPickerView extends StatefulWidget {
  const EstimateComplimentProductPickerView({super.key});

  @override
  State<EstimateComplimentProductPickerView> createState() =>
      _EstimateComplimentProductPickerViewState();
}

class _EstimateComplimentProductPickerViewState
    extends State<EstimateComplimentProductPickerView> {
  final controller = Get.find<EstimationController>();

  /// productId -> selection picked on this screen (possibly spanning
  /// several pricelist tabs). Nothing is written to the estimate until
  /// "Add Compliment Products" is tapped.
  final Map<String, _SelectedLine> _selections = {};
  String _query = '';
  bool _isGrid = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill with compliment products already on the estimate (from
    // any pricelist) so reopening the picker to top up shows current
    // counts.
    for (final item in controller.complimentItems) {
      _selections[item.productId] = _SelectedLine(
        option: EstimateProductOption(
          productId: item.productId,
          productName: item.productName,
          unitId: item.unitId,
          unitName: item.unit,
          isCustom: item.isCustom,
        ),
        qty: item.quantity,
      );
    }
  }

  int get _totalItemsSelected =>
      _selections.values.fold(0, (a, l) => a + l.qty);

  List<EstimateProductOption> get _filtered {
    final all = controller.productOptions;
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((p) => p.productName.toLowerCase().contains(q)).toList();
  }

  void _setQty(EstimateProductOption option, int qty) {
    setState(() {
      if (qty <= 0) {
        _selections.remove(option.productId);
      } else {
        _selections[option.productId] = _SelectedLine(option: option, qty: qty);
      }
    });
  }

  void _selectPricelistTab(IdName pricelist) {
    controller.selectPricelist(pricelist);
  }

  void _addCustomProduct() {
    showAddCustomProductSheet(
      context: context,
      categories: controller.customCategories,
      units: controller.customUnits,
      onSubmit: ({
        required categoryId,
        required categoryName,
        required productName,
        required unitId,
        required unitName,
        required price,
      }) async {
        final option = await controller.addCustomProduct(
          categoryId: categoryId,
          categoryName: categoryName,
          productName: productName,
          unitId: unitId,
          unitName: unitName,
          price: price,
        );
        // Auto-select the new product the moment it's created — same
        // as tapping "Add to Cart" on an ordinary catalogue product —
        // so it shows up already picked once the sheet closes.
        if (option != null) _setQty(option, 1);
        return option != null;
      },
    );
  }

  void _confirm() {
    if (_selections.isEmpty) {
      Get.snackbar('No products selected', 'Pick at least one product first',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    controller.addComplimentSelections(
      _selections.values.map((l) => MapEntry(l.option, l.qty)).toList(),
    );
    Get.back();
  }

  Future<void> _confirmBack() async {
    final confirmed = await confirmDialog(
      title: 'Go back?',
      message: 'Are you sure you want to go back? '
          'Any product selections made here will be lost.',
    );
    if (confirmed) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _confirmBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.midnight,
        appBar: AppBar(
          title: const Text('Select Compliment Products'),
          actions: [
            IconButton(
              tooltip: 'Add custom product',
              onPressed: _addCustomProduct,
              icon: const Icon(Icons.add_box_outlined),
            ),
            IconButton(
              tooltip: _isGrid ? 'List view' : 'Grid view',
              onPressed: () => setState(() => _isGrid = !_isGrid),
              icon: Icon(
                  _isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded),
            ),
            const SizedBox(width: 8.0),
          ],
        ),
        body: Container(
          decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Column(
              children: [
                Obx(() {
                  if (controller.pricelistOptions.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _PricelistTabBar(
                    pricelists: controller.pricelistOptions,
                    selectedId: controller.selectedPricelistId.value,
                    onSelected: _selectPricelistTab,
                  );
                }),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: SearchField(
                    hint: 'Search product',
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                Expanded(
                  child: Obx(() {
                    if (controller.pricelistOptions.isEmpty ||
                        controller.isLoadingProducts.value) {
                      return Center(
                          child: CircularProgressIndicator(
                              color: AppColors.gold));
                    }
                    final items = _filtered;
                    if (items.isEmpty) {
                      return EmptyState(
                        icon: Icons.celebration_outlined,
                        title: 'No products found',
                        subtitle: _query.isEmpty
                            ? 'No products found for this pricelist'
                            : 'No matches for "$_query"',
                      );
                    }
                    return _isGrid ? _gridView(items) : _listView(items);
                  }),
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceElevated,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('$_totalItemsSelected item(s) selected',
                      style: AppTextStyles.h3.copyWith(color: AppColors.gold)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 14),
                  ),
                  onPressed: _totalItemsSelected == 0 ? null : _confirm,
                  child: const Text('Add Compliment Products'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gridView(List<EstimateProductOption> items) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, i) => _ComplimentProductCard(
        option: items[i],
        qty: _selections[items[i].productId]?.qty ?? 0,
        onChanged: (qty) => _setQty(items[i], qty),
      ),
    );
  }

  Widget _listView(List<EstimateProductOption> items) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _ComplimentProductListTile(
        option: items[i],
        qty: _selections[items[i].productId]?.qty ?? 0,
        onChanged: (qty) => _setQty(items[i], qty),
      ),
    );
  }
}

/// Horizontally-scrollable pricelist tabs shown above the product list —
/// identical to [EstimateProductPickerView]'s own `_PricelistTabBar`.
class _PricelistTabBar extends StatelessWidget {
  final List<IdName> pricelists;
  final String? selectedId;
  final ValueChanged<IdName> onSelected;
  const _PricelistTabBar({
    required this.pricelists,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: pricelists.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final pricelist = pricelists[i];
          final selected = pricelist.id == selectedId;
          return InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => onSelected(pricelist),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              decoration: BoxDecoration(
                gradient: selected ? AppColors.goldGradient : null,
                color: selected ? null : AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Colors.transparent : AppColors.divider,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                pricelist.name,
                style: AppTextStyles.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      selected ? AppColors.textOnGold : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shared "Add to Cart" button <-> quantity control — identical to
/// [EstimateProductPickerView]'s own `_AddOrStepper`.
class _AddOrStepper extends StatefulWidget {
  final int qty;
  final ValueChanged<int> onChanged;
  const _AddOrStepper({required this.qty, required this.onChanged});

  @override
  State<_AddOrStepper> createState() => _AddOrStepperState();
}

class _AddOrStepperState extends State<_AddOrStepper> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.qty > 0 ? '${widget.qty}' : '');
  late final FocusNode _focusNode = FocusNode()
    ..addListener(() {
      if (!_focusNode.hasFocus) _commit();
    });

  @override
  void didUpdateWidget(covariant _AddOrStepper old) {
    super.didUpdateWidget(old);
    if (!_focusNode.hasFocus && widget.qty != old.qty) {
      _ctrl.text = widget.qty > 0 ? '${widget.qty}' : '';
    }
  }

  void _commit() {
    final parsed = int.tryParse(_ctrl.text.trim());
    final qty = (parsed == null || parsed < 0) ? 0 : parsed;
    _ctrl.text = qty > 0 ? '$qty' : '';
    if (qty != widget.qty) widget.onChanged(qty);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.qty <= 0 && !_focusNode.hasFocus) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => widget.onChanged(1),
          child: const Text(
            'Add',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.0),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stepBtn(Icons.remove_rounded, AppColors.danger,
              () => widget.onChanged(widget.qty > 0 ? widget.qty - 1 : 0)),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: AppTextStyles.bodyStrong,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => _commit(),
            ),
          ),
          _stepBtn(Icons.add_rounded, AppColors.success,
              () => widget.onChanged(widget.qty + 1)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}

/// Grid card for a compliment product — name + quantity stepper only, no
/// rate/stock line, matching the "no need to display prices" spec.
class _ComplimentProductCard extends StatelessWidget {
  final EstimateProductOption option;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ComplimentProductCard(
      {required this.option, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return GestureDetector(
      onTap: () {
        if (qty <= 0) onChanged(1);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 62,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppColors.tealGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.celebration_rounded,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              option.productName,
              style: AppTextStyles.bodyStrong,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const Spacer(),
            const SizedBox(height: 8),
            _AddOrStepper(qty: qty, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// List tile for a compliment product — name + quantity stepper only, no
/// rate/stock line.
class _ComplimentProductListTile extends StatelessWidget {
  final EstimateProductOption option;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ComplimentProductListTile(
      {required this.option, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final selected = qty > 0;
    return GestureDetector(
      onTap: () {
        if (qty <= 0) onChanged(1);
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.gold : AppColors.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 48,
              width: 48,
              decoration: BoxDecoration(
                gradient: AppColors.tealGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.celebration_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                option.productName,
                style: AppTextStyles.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 112,
              child: _AddOrStepper(qty: qty, onChanged: onChanged),
            ),
          ],
        ),
      ),
    );
  }
}